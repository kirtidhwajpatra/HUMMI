"""Stage A — restoration models.

Each function maps [(name, audio_48k_mono)] -> [(name, restored_48k_mono)].
"""

import sys

import numpy as np
import soxr

from audio_io import SAMPLE_RATE

_DFN = None
_VOICEFIXER = None

VF_SR = 44_100
VF_WINDOW_S = 24.0  # < VoiceFixer's internal 30s segment, so each call is one pass
VF_XFADE_S = 2.0


def _install_torchaudio_shim() -> None:
    """deepfilternet 0.5.6 imports torchaudio.backend, removed in torchaudio 2.x."""
    import torchaudio

    if "torchaudio.backend" in sys.modules or hasattr(torchaudio, "backend"):
        return
    import types
    common = types.ModuleType("torchaudio.backend.common")
    # Only used for type annotations inside deepfilternet; a dummy is fine.
    common.AudioMetaData = getattr(torchaudio, "AudioMetaData", object)
    backend = types.ModuleType("torchaudio.backend")
    backend.common = common
    sys.modules["torchaudio.backend"] = backend
    sys.modules["torchaudio.backend.common"] = common


def dfn_enhance(clips, atten_lim_db: float | None = None) -> list[tuple[str, np.ndarray]]:
    """DeepFilterNet3 noise suppression — native 48kHz. Model loads once.
    atten_lim_db caps suppression depth: on already-restored input, full
    suppression gates chunks of the (resynthesized) voice in and out."""
    global _DFN
    import torch

    _install_torchaudio_shim()
    from df.enhance import enhance, init_df

    if _DFN is None:
        _DFN = init_df()  # default model is DeepFilterNet3
    model, df_state, _ = _DFN
    warmup = SAMPLE_RATE  # 1s reflected pre-roll: the recurrent state starts
    out = []              # cold and gates the clip's first phrase otherwise
    for name, audio in clips:
        padded = np.concatenate([audio[:warmup][::-1], audio])
        enhanced = enhance(model, df_state, torch.from_numpy(padded[None, :]),
                           atten_lim_db=atten_lim_db)
        out.append((name, enhanced.squeeze(0).cpu().numpy()[warmup:].astype(np.float32)))
    return out


def _vf_one_pass(audio_44k: np.ndarray) -> np.ndarray:
    """One VoiceFixer pass over a segment short enough (<30s) to avoid its
    internal chunking. Returns mono, roughly the segment's length."""
    restored = np.asarray(_VOICEFIXER.restore_inmem(audio_44k, cuda=False, mode=0),
                          dtype=np.float32)
    if restored.ndim > 1:  # [channels, samples]
        restored = restored.mean(axis=0)
    return restored


def _fit_length(seg: np.ndarray, target: int) -> np.ndarray:
    """Pad/crop symmetrically — VoiceFixer trims its output from the center,
    so symmetric padding restores alignment with the input window."""
    if len(seg) > target:
        extra = len(seg) - target
        seg = seg[extra // 2:extra // 2 + target]
    elif len(seg) < target:
        short = target - len(seg)
        seg = np.pad(seg, (short // 2, short - short // 2))
    return seg


def _vf_windowed(audio_44k: np.ndarray) -> np.ndarray:
    """VoiceFixer resynthesizes fixed 30s segments independently: hard
    phase-incoherent seams every 30s, and a final segment that can be a
    short stub (audibly garbled). Instead, run ≤24s windows ourselves —
    the last one end-aligned so it is never a stub — and blend overlaps
    with a raised-cosine crossfade."""
    n = len(audio_44k)
    window = int(VF_WINDOW_S * VF_SR)
    if n <= window:
        return _vf_one_pass(audio_44k)

    xfade = int(VF_XFADE_S * VF_SR)
    starts = list(range(0, n - window, window - xfade)) + [n - window]
    # Hand-off points sit at the center of each consecutive overlap; each
    # window contributes nothing beyond its xfade ramp there. Overlaps can
    # exceed xfade (the end-aligned last window) — without the cutoff, two
    # phase-incoherent renditions would blend 50/50 across the whole overlap.
    bounds = [(starts[k] + window + starts[k + 1]) // 2 for k in range(len(starts) - 1)]
    mixed = np.zeros(n, dtype=np.float64)
    weight = np.zeros(n, dtype=np.float64)
    fade_in = np.sin(np.linspace(0.0, np.pi / 2, xfade)) ** 2
    for k, start in enumerate(starts):
        seg = _fit_length(_vf_one_pass(audio_44k[start:start + window]), window)
        w = np.ones(window)
        if k > 0:
            a = bounds[k - 1] - xfade // 2 - start
            w[:a] = 0.0
            w[a:a + xfade] = fade_in
        if k < len(starts) - 1:
            a = bounds[k] - xfade // 2 - start
            w[a:a + xfade] = fade_in[::-1]
            w[a + xfade:] = 0.0
        mixed[start:start + window] += seg * w
        weight[start:start + window] += w
    return (mixed / np.maximum(weight, 1e-9)).astype(np.float32)


def rescue_dropouts(clips, vf_outputs, fallback_outputs) -> list[tuple[str, np.ndarray]]:
    """VoiceFixer's vocoder drops or garbles the softest passages (breathy
    trail-offs): its output level falls far below the input's. Wherever the
    calibrated level deficit exceeds 6dB, crossfade to the waveform-preserving
    fallback restoration (DFN3, attenuation-limited)."""
    from scipy.ndimage import uniform_filter1d

    env_win = int(0.2 * SAMPLE_RATE)

    def env_db(x: np.ndarray) -> np.ndarray:
        energy = uniform_filter1d(x.astype(np.float64) ** 2, env_win)
        return 10 * np.log10(energy + 1e-12)

    out = []
    for (name, original), (_, vf), (_, fallback) in zip(clips, vf_outputs, fallback_outputs):
        n = min(len(original), len(vf), len(fallback))
        e_in, e_vf = env_db(original[:n]), env_db(vf[:n])
        active = e_in > e_in.max() - 40
        offset = float(np.median((e_vf - e_in)[active])) if active.any() else 0.0
        deficit = e_vf - e_in - offset
        w_vf = np.clip((deficit + 12.0) / 6.0, 0.0, 1.0)  # full fallback at -12dB
        w_vf = uniform_filter1d(w_vf, int(0.1 * SAMPLE_RATE))
        rescued_s = float(np.sum(w_vf < 0.5)) / SAMPLE_RATE
        if rescued_s > 0.05:
            print(f"    {name}: rescued {rescued_s:.1f}s where VoiceFixer dropped the audio")
        out.append((name, (w_vf * vf[:n] + (1.0 - w_vf) * fallback[:n]).astype(np.float32)))
    return out


def _voiced_mask(audio: np.ndarray, n: int) -> np.ndarray:
    """Per-sample mask of pitched frames in the original (pyin at 22.05kHz).
    Requires f0 >= 130Hz: pyin locks onto traffic/fan rumble pinned at its
    fmin boundary, while sung notes sit well above."""
    import librosa

    pyin_sr, pyin_hop = 22_050, 512
    y = soxr.resample(audio, SAMPLE_RATE, pyin_sr).astype(np.float32)
    f0, voiced, _ = librosa.pyin(y, fmin=110, fmax=1_000, sr=pyin_sr,
                                 hop_length=pyin_hop)
    ok = voiced & (np.nan_to_num(f0) >= 130.0)
    step = pyin_hop * SAMPLE_RATE / pyin_sr
    mask = np.repeat(ok.astype(np.float64), int(np.ceil(step)))
    return mask[:n] if len(mask) >= n else np.pad(mask, (0, n - len(mask)))


def _keep_sustained(mask: np.ndarray, min_s: float = 0.4) -> np.ndarray:
    """Zero out mask runs shorter than min_s — singing phrases are
    sustained; sub-0.4s pitched blips in noise are false positives."""
    edges = np.diff(np.concatenate([[0.0], mask, [0.0]]))
    starts, ends = np.where(edges == 1)[0], np.where(edges == -1)[0]
    out = np.zeros_like(mask)
    keep = (ends - starts) >= int(min_s * SAMPLE_RATE)
    for s, e in zip(starts[keep], ends[keep]):
        out[s:e] = 1.0
    return out


def dfn_adaptive_floor(clips, dfn_full, target_floor_db: float = 45.0,
                       min_lim_db: float = 6.0, max_lim_db: float = 40.0,
                       voiced_cap_db: float = 12.0) -> list[tuple[str, np.ndarray]]:
    """Right-size DFN3's suppression per clip: estimate the noise floor and
    suppress it to ~target_floor_db below the voice, no further. Full
    suppression gates breaths and voice onsets and leaves fluttery musical
    noise; a clip-appropriate residual floor sounds like a quiet room.
    Implemented as a blend of input and enhanced (equivalent to DFN3's
    atten_lim, chosen per clip), so one model pass serves all.

    Voice-gated rescue on top: where the original is pitched but the model
    cut it by more than voiced_cap_db (DFN3 deletes soft breathy singing,
    e.g. quiet intros), cap the suppression at voiced_cap_db. Unvoiced
    frames never trigger, so gaps stay deep-cleaned."""
    from scipy.ndimage import uniform_filter1d

    smooth = int(0.05 * SAMPLE_RATE)

    def env_db(x: np.ndarray) -> np.ndarray:
        return 10 * np.log10(uniform_filter1d(x.astype(np.float64) ** 2, smooth) + 1e-12)

    out = []
    for (name, orig), (_, enh) in zip(clips, dfn_full):
        n = min(len(orig), len(enh))
        e_orig, e_enh = env_db(orig[:n]), env_db(enh[:n])
        voice_level = np.median(e_enh[e_enh > e_enh.max() - 40])
        quiet = e_enh < voice_level - 35  # frames the model calls voice-free
        noise_floor = float(np.median(e_orig[quiet])) if quiet.any() else -120.0
        lim = float(np.clip(noise_floor - (voice_level - target_floor_db),
                            min_lim_db, max_lim_db))
        w_floor = 10 ** (-lim / 20)

        deficit = e_orig - e_enh  # >0 where the model attenuated
        rescue = _voiced_mask(orig[:n], n) * (deficit > voiced_cap_db)
        rescue = _keep_sustained(rescue)
        rescue = uniform_filter1d(rescue, int(0.1 * SAMPLE_RATE))  # de-zipper
        w = np.maximum(w_floor, 10 ** (-voiced_cap_db / 20) * rescue)
        rescued_s = float(np.sum(rescue > 0.5)) / SAMPLE_RATE
        print(f"    {name}: noise {noise_floor - voice_level:.0f}dB re voice -> "
              f"suppressing {lim:.0f}dB, voiced rescue {rescued_s:.1f}s")
        out.append((name, (w * orig[:n] + (1.0 - w) * enh[:n]).astype(np.float32)))
    return out


def _lag_samples(x: np.ndarray, y: np.ndarray,
                 max_lag_s: float = 0.02, probe_s: float = 10.0) -> int:
    """Lag of x relative to y (positive = x arrives later), estimated by
    cross-correlation over a centered probe window."""
    from scipy.signal import correlate

    mid, half = len(x) // 2, int(probe_s * SAMPLE_RATE / 2)
    lo, hi = max(0, mid - half), mid + half
    xs, ys = x[lo:hi], y[lo:hi]
    corr = correlate(xs, ys, mode="full", method="fft")
    lags = np.arange(-len(ys) + 1, len(xs))
    window = np.abs(lags) <= int(max_lag_s * SAMPLE_RATE)
    return int(lags[window][np.argmax(corr[window])])


def cap_hf_fizz(vf_outputs, ref_outputs, lo_hz: float = 7_000.0,
                margin_db: float = 6.0) -> list[tuple[str, np.ndarray]]:
    """VoiceFixer's bandwidth extension overshoots: its 8-16kHz band rides
    13-18dB above the real recording's — synthetic fizz that reads as a
    robotic sheen. Per STFT frame, cap VF's high band at the reference
    restoration's level + margin; normal frames are untouched."""
    from scipy.signal import istft, stft

    nperseg, hop = 1024, 256
    edges = [lo_hz, 10_000.0, 14_000.0, SAMPLE_RATE / 2]  # per-band caps: a
    out = []                # broadband average lets fizz hide in sub-ranges
    for (name, vf), (_, ref) in zip(vf_outputs, ref_outputs):
        n = min(len(vf), len(ref))
        scale = np.sqrt(np.mean(ref[:n] ** 2) / max(np.mean(vf[:n] ** 2), 1e-12))
        freqs, _, V = stft(vf[:n] * scale, fs=SAMPLE_RATE, nperseg=nperseg,
                           noverlap=nperseg - hop)
        _, _, R = stft(ref[:n], fs=SAMPLE_RATE, nperseg=nperseg,
                       noverlap=nperseg - hop)
        m = min(V.shape[1], R.shape[1])
        for lo, hi in zip(edges[:-1], edges[1:]):
            band = (freqs >= lo) & (freqs < hi)
            e_vf = 10 * np.log10(np.mean(np.abs(V[band, :m]) ** 2, axis=0) + 1e-12)
            e_ref = 10 * np.log10(np.mean(np.abs(R[band, :m]) ** 2, axis=0) + 1e-12)
            cut_db = np.maximum(e_vf - (e_ref + margin_db), 0.0)
            cut_db = np.convolve(cut_db, np.ones(3) / 3, mode="same")  # de-flutter
            V[band, :m] *= 10 ** (-cut_db[None, :] / 20)
        _, y = istft(V, fs=SAMPLE_RATE, nperseg=nperseg, noverlap=nperseg - hop)
        y = (y / scale).astype(np.float32)
        y = y[:n] if len(y) >= n else np.pad(y, (0, n - len(y)))
        out.append((name, y))
    return out


def _divergence_duck(vf: np.ndarray, anchor: np.ndarray) -> np.ndarray:
    """Per-sample scale for VF's share of the blend: 1 normally, down to
    0.25 where VF's spectrum diverges hard from the anchor's — those are
    the vocoder's localized glitches."""
    from scipy.ndimage import uniform_filter1d
    from scipy.signal import stft

    nperseg, hop = 2048, 512
    freqs, _, V = stft(vf, fs=SAMPLE_RATE, nperseg=nperseg, noverlap=nperseg - hop)
    _, _, A = stft(anchor, fs=SAMPLE_RATE, nperseg=nperseg, noverlap=nperseg - hop)
    sel = (freqs >= 200) & (freqs <= 6_000)
    m = min(V.shape[1], A.shape[1])
    div = np.mean(np.abs(20 * np.log10(np.abs(V[sel, :m]) + 1e-10)
                         - 20 * np.log10(np.abs(A[sel, :m]) + 1e-10)), axis=0)
    med = max(float(np.median(div)), 1e-9)
    s = np.clip((3.0 - div / med) / 1.5, 0.25, 1.0)
    s = np.repeat(s, hop)
    s = s[:len(vf)] if len(s) >= len(vf) else np.pad(s, (0, len(vf) - len(s)), mode="edge")
    return uniform_filter1d(s, int(0.1 * SAMPLE_RATE))


def blend_hybrid(vf_outputs, anchor_outputs, split_hz: float = 1_500.0,
                 low_vf: float = 0.35, high_vf: float = 0.6,
                 smooth_ms: float = 80.0, max_gain_db: float = 12.0) -> list[tuple[str, np.ndarray]]:
    """Anti-robot blend of VoiceFixer with the waveform-preserving DFN3
    restoration. VF contributes only a slowly-varying spectral gain:
    G = (blended magnitude) / (anchor magnitude), smoothed over smooth_ms
    and clamped to ±max_gain_db, applied to the anchor's complex spectrum.
    The anchor's phase and fine temporal structure pass through untouched —
    neither the vocoder's buzzy phase nor its frame-level magnitude wobble
    can reach the output through a smooth, bounded EQ curve.

    Magnitude weights are frequency-tilted (lows mostly anchor, highs lean
    VF for dereverb and air) and ducked where VF's spectrum diverges from
    the anchor's (localized vocoder glitches). Lag-aligned, RMS-matched."""
    from scipy.ndimage import uniform_filter1d
    from scipy.signal import istft, stft

    nperseg, hop = 1024, 256
    g_lim = 10 ** (max_gain_db / 20)
    out = []
    for (name, vf), (_, anchor) in zip(vf_outputs, anchor_outputs):
        n = min(len(vf), len(anchor))
        v, a = vf[:n].astype(np.float64), anchor[:n].astype(np.float64)
        lag = _lag_samples(v, a)
        if lag > 0:
            v = np.concatenate([v[lag:], np.zeros(lag)])
        elif lag < 0:
            v = np.concatenate([np.zeros(-lag), v[:lag]])
        v *= np.sqrt(np.mean(a ** 2) / max(np.mean(v ** 2), 1e-12))
        duck = _divergence_duck(v.astype(np.float32), a.astype(np.float32))[:n]

        freqs, _, V = stft(v, fs=SAMPLE_RATE, nperseg=nperseg, noverlap=nperseg - hop)
        _, _, A = stft(a, fs=SAMPLE_RATE, nperseg=nperseg, noverlap=nperseg - hop)
        m = min(V.shape[1], A.shape[1])
        tilt = uniform_filter1d(np.where(freqs < split_hz, low_vf, high_vf)[:, None],
                                4, axis=0)  # soften the step at the crossover
        d = duck[::hop]
        d = d[:m] if len(d) >= m else np.pad(d, (0, m - len(d)), mode="edge")
        w = tilt * d[None, :]
        mag_a = np.abs(A[:, :m])
        mag = w * np.abs(V[:, :m]) + (1 - w) * mag_a
        gain = mag / (mag_a + 1e-10)
        gain = uniform_filter1d(gain, 3, axis=0)  # no per-bin combing
        gain = uniform_filter1d(gain, max(1, int(smooth_ms / 1000 * SAMPLE_RATE / hop)),
                                axis=1)
        gain = np.clip(gain, 1.0 / g_lim, g_lim)
        _, y = istft(gain * A[:, :m], fs=SAMPLE_RATE,
                     nperseg=nperseg, noverlap=nperseg - hop)
        y = y[:n] if len(y) >= n else np.pad(y, (0, n - len(y)))
        out.append((name, y.astype(np.float32)))
    return out


def wpe_dereverb(clips, taps: int = 16, delay: int = 3, iterations: int = 3) -> list[tuple[str, np.ndarray]]:
    """WPE late-reverberation removal (nara_wpe) — pure linear filtering of
    the real recording, no resynthesis, so it cannot sound robotic.
    Only dereverbs; pair with a denoiser after."""
    from nara_wpe.utils import istft, stft
    from nara_wpe.wpe import wpe

    size, shift = 1024, 256
    out = []
    for name, audio in clips:
        spec = stft(audio[None, :], size=size, shift=shift)      # (D, T, F)
        cleaned = wpe(spec.transpose(2, 0, 1), taps=taps, delay=delay,
                      iterations=iterations).transpose(1, 2, 0)  # back to (D, T, F)
        y = istft(cleaned, size=size, shift=shift)[0]
        y = y[:len(audio)] if len(y) >= len(audio) else np.pad(y, (0, len(audio) - len(y)))
        out.append((name, y.astype(np.float32)))
    return out


def voicefixer_restore(clips) -> list[tuple[str, np.ndarray]]:
    """VoiceFixer mode 0: full restoration (denoise + dereverb + bandwidth
    extension). Runs at 44.1kHz internally; resampled back to 48kHz.
    Results are disk-cached by input hash — VoiceFixer dominates run time
    and is deterministic, so iterating on later stages is free."""
    global _VOICEFIXER
    import hashlib
    from pathlib import Path

    cache_dir = Path(__file__).resolve().parent / ".model-cache" / "voicefixer"
    cache_dir.mkdir(parents=True, exist_ok=True)

    out = []
    for name, audio in clips:
        key = hashlib.sha1(audio.tobytes()).hexdigest()[:16]
        cached = cache_dir / f"{name}-{key}-w{VF_WINDOW_S:g}x{VF_XFADE_S:g}.npy"
        if cached.exists():
            out.append((name, np.load(cached)))
            continue
        if _VOICEFIXER is None:
            from voicefixer import VoiceFixer
            _VOICEFIXER = VoiceFixer()
        restored = _vf_windowed(soxr.resample(audio, SAMPLE_RATE, VF_SR))
        restored = soxr.resample(restored, VF_SR, SAMPLE_RATE).astype(np.float32)
        np.save(cached, restored)
        out.append((name, restored))
    return out
