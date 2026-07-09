"""Stage B — the studio-polish chain, applied after restoration.

Order: 12dB/oct high-pass -> surgical EQ -> de-esser -> multiband
compression -> parallel saturation -> presence/air EQ -> convolution
reverb (real IR, 20ms pre-delay) -> glue compressor.
"""

from dataclasses import dataclass
from pathlib import Path

import numpy as np
import soundfile as sf
import soxr

from audio_io import SAMPLE_RATE

SPIKE_DIR = Path(__file__).resolve().parent
IR_DIR = SPIKE_DIR / "irs"
PREPARED_IR_DIR = SPIKE_DIR / ".model-cache" / "prepared-irs"


@dataclass(frozen=True)
class PolishPreset:
    reverb_wet: float = 0.18
    sat_blend: float = 0.15   # parallel saturation mix; 0 disables
    air_db: float = 3.5       # high shelf @ 10kHz
    tune: float = 0.0         # gentle chromatic auto-tune strength; 0 disables


STANDARD = PolishPreset()
TUNED = PolishPreset(tune=0.4)
STRONG = PolishPreset(reverb_wet=0.25, sat_blend=0.25, air_db=5.0)
TUNED_STRONG = PolishPreset(reverb_wet=0.25, sat_blend=0.25, air_db=5.0, tune=0.4)


def deess(audio: np.ndarray, ratio: float = 4.0) -> np.ndarray:
    """STFT de-esser: dynamic cut of 6-9kHz. Threshold sits 8dB above the
    clip's typical (median) band level, so it only bites on sibilants."""
    from scipy.signal import istft, stft

    nperseg = 1024  # ~21ms @ 48kHz
    noverlap = nperseg * 3 // 4
    freqs, _, spec = stft(audio, fs=SAMPLE_RATE, nperseg=nperseg, noverlap=noverlap)
    band = (freqs >= 6_000) & (freqs <= 9_000)
    band_db = 20 * np.log10(np.sqrt(np.mean(np.abs(spec[band]) ** 2, axis=0)) + 1e-12)

    active = band_db[band_db > -80]
    if active.size == 0:
        return audio
    threshold_db = np.median(active) + 8.0
    cut_db = np.maximum(band_db - threshold_db, 0.0) * (1.0 - 1.0 / ratio)
    cut_db = np.convolve(cut_db, np.ones(3) / 3, mode="same")  # de-flutter

    spec[band] *= 10 ** (-cut_db[None, :] / 20)
    _, out = istft(spec, fs=SAMPLE_RATE, nperseg=nperseg, noverlap=noverlap)
    out = out.astype(np.float32)
    if len(out) < len(audio):
        out = np.pad(out, (0, len(audio) - len(out)))
    return out[:len(audio)]


def multiband_compress(audio: np.ndarray, ratio: float = 3.0) -> np.ndarray:
    """3-band compression (<250Hz, 250Hz-4kHz, >4kHz) at moderate ratio.
    Zero-phase crossovers so the bands sum back exactly; threshold sits
    relative to each band's own level, RMS-restoring auto makeup per band."""
    from pedalboard import Compressor
    from scipy.signal import butter, sosfiltfilt

    low = sosfiltfilt(butter(4, 250, "lowpass", fs=SAMPLE_RATE, output="sos"), audio)
    high = sosfiltfilt(butter(4, 4_000, "highpass", fs=SAMPLE_RATE, output="sos"), audio)
    mid = audio - low - high

    out = np.zeros_like(audio, dtype=np.float32)
    for band in (low, mid, high):
        rms_in = float(np.sqrt(np.mean(band ** 2)))
        if rms_in < 1e-6:  # effectively empty band
            out += band.astype(np.float32)
            continue
        threshold_db = 20 * np.log10(rms_in) + 6.0  # bites on the band's peaks
        compressed = Compressor(threshold_db=threshold_db, ratio=ratio,
                                attack_ms=15, release_ms=150)(
            band.astype(np.float32), SAMPLE_RATE)
        rms_out = float(np.sqrt(np.mean(compressed ** 2)))
        makeup = min(rms_in / max(rms_out, 1e-9), 4.0)  # cap at +12dB
        out += compressed * makeup
    return out


def saturate(audio: np.ndarray, blend: float) -> np.ndarray:
    """Low-drive tanh saturation, mixed in parallel — warmth, not fuzz."""
    if blend <= 0:
        return audio
    from pedalboard import Distortion

    driven = Distortion(drive_db=5.0)(audio, SAMPLE_RATE)
    return ((1.0 - blend) * audio + blend * driven).astype(np.float32)


def prepared_ir(pre_delay_ms: float = 20.0) -> Path:
    """First IR file in irs/, mono 48kHz, onset-trimmed, peak-normalized,
    with pre-delay baked in as leading silence (keeps the voice upfront).
    Synthesizes a plate-style IR as fallback if irs/ is empty."""
    PREPARED_IR_DIR.mkdir(parents=True, exist_ok=True)
    sources = sorted(p for p in IR_DIR.glob("*") if p.suffix.lower() in {".wav", ".aif", ".aiff", ".flac"})

    if sources:
        source = sources[0]
        prepared = PREPARED_IR_DIR / f"{source.stem}-pd{int(pre_delay_ms)}ms.wav"
        if prepared.exists():
            return prepared
        data, sr = sf.read(source, dtype="float32", always_2d=True)
        ir = data.mean(axis=1)
        if sr != SAMPLE_RATE:
            ir = soxr.resample(ir, sr, SAMPLE_RATE)
    else:
        print("  note: no IR in irs/, synthesizing a plate-style fallback")
        prepared = PREPARED_IR_DIR / f"synthetic-plate-pd{int(pre_delay_ms)}ms.wav"
        if prepared.exists():
            return prepared
        t = np.arange(int(1.2 * SAMPLE_RATE)) / SAMPLE_RATE
        rng = np.random.default_rng(7)
        ir = rng.standard_normal(t.size) * np.exp(-6.91 * t / 0.9)  # ~0.9s T60

    peak = float(np.max(np.abs(ir)))
    onset = int(np.argmax(np.abs(ir) > 0.01 * peak))  # trim silence before direct sound
    ir = ir[onset:] / max(peak, 1e-9)
    ir = np.concatenate([np.zeros(int(pre_delay_ms / 1000 * SAMPLE_RATE)), ir])
    sf.write(prepared, ir.astype(np.float32), SAMPLE_RATE)
    return prepared


def conv_reverb(audio: np.ndarray, wet: float, ir_path: Path) -> np.ndarray:
    from pedalboard import Convolution

    return Convolution(str(ir_path), mix=wet)(audio, SAMPLE_RATE)


def polish(audio: np.ndarray, preset: PolishPreset) -> np.ndarray:
    """Run the full Stage B chain."""
    from pedalboard import (Compressor, HighpassFilter, HighShelfFilter,
                            Pedalboard, PeakFilter)

    front = Pedalboard([
        HighpassFilter(cutoff_frequency_hz=80),  # x2 = 12dB/oct
        HighpassFilter(cutoff_frequency_hz=80),
        PeakFilter(cutoff_frequency_hz=300, gain_db=-3.0, q=1.2),  # mud
        PeakFilter(cutoff_frequency_hz=500, gain_db=-2.0, q=2.0),  # boxiness
    ])
    presence_air = Pedalboard([
        PeakFilter(cutoff_frequency_hz=3_000, gain_db=2.0, q=1.0),
        HighShelfFilter(cutoff_frequency_hz=10_000, gain_db=preset.air_db),
    ])
    glue = Pedalboard([
        Compressor(threshold_db=-14, ratio=2.0, attack_ms=30, release_ms=200),
    ])

    y = audio.astype(np.float32)
    if preset.tune > 0:
        from autotune import autotune
        y = autotune(y, preset.tune)
    y = front(y, SAMPLE_RATE)
    y = deess(y)
    y = multiband_compress(y)
    y = saturate(y, preset.sat_blend)
    y = presence_air(y, SAMPLE_RATE)
    y = conv_reverb(y, preset.reverb_wet, prepared_ir())
    return glue(y, SAMPLE_RATE)
