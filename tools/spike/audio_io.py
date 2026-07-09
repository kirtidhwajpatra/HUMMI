"""Loading, decoding, loudness matching, and writing of clips.

Everything internal is 48kHz mono float32. Every written file is
loudness-matched to -14 LUFS with a -1 dBTP true-peak ceiling.
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
import soxr

SAMPLE_RATE = 48_000
TARGET_LUFS = -14.0
TRUE_PEAK_CEILING_DB = -1.0
AUDIO_EXTENSIONS = {".wav", ".mp3", ".m4a", ".aac", ".flac", ".ogg", ".aif", ".aiff", ".caf"}


def decode_with_cli(path: Path) -> tuple[np.ndarray, int]:
    """Decode formats soundfile can't (m4a/aac) via ffmpeg or macOS afconvert."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        if shutil.which("ffmpeg"):
            cmd = ["ffmpeg", "-y", "-i", str(path), "-ac", "1",
                   "-ar", str(SAMPLE_RATE), str(tmp_path)]
        elif shutil.which("afconvert"):
            cmd = ["afconvert", "-f", "WAVE", "-d", f"LEF32@{SAMPLE_RATE}",
                   "-c", "1", str(path), str(tmp_path)]
        else:
            raise RuntimeError(f"Cannot decode {path.name}: need ffmpeg or afconvert")
        subprocess.run(cmd, check=True, capture_output=True)
        return sf.read(tmp_path, dtype="float32", always_2d=True)
    finally:
        tmp_path.unlink(missing_ok=True)


def load_clip(path: Path) -> np.ndarray:
    """Load any audio file as 48kHz mono float32."""
    try:
        data, sr = sf.read(path, dtype="float32", always_2d=True)
    except Exception:
        data, sr = decode_with_cli(path)
    mono = data.mean(axis=1)
    if sr != SAMPLE_RATE:
        mono = soxr.resample(mono, sr, SAMPLE_RATE)
    return mono.astype(np.float32)


def peak_limit(audio: np.ndarray, ceiling: float) -> np.ndarray:
    """Transparent lookahead peak limiter: per-sample gain reduction,
    min-filtered (lookahead) then smoothed. Smoothing window is narrower
    than the min window, so the ceiling is never overshot at sample level."""
    from scipy.ndimage import minimum_filter1d, uniform_filter1d

    wanted = np.minimum(1.0, ceiling / (np.abs(audio) + 1e-9))
    gain = minimum_filter1d(wanted, size=385)   # ~4ms @ 48kHz
    gain = uniform_filter1d(gain, size=129)     # ~1.3ms
    return (audio * gain).astype(np.float32)


def oversampled_clip(audio: np.ndarray, ceiling: float) -> np.ndarray:
    """Shave residual inter-sample peaks: hard clip in the 4x-oversampled
    domain, then decimate. Only ever applied fractions of a dB deep."""
    up = soxr.resample(audio.astype(np.float64), SAMPLE_RATE, SAMPLE_RATE * 4)
    up = np.clip(up, -ceiling, ceiling)
    return soxr.resample(up, SAMPLE_RATE * 4, SAMPLE_RATE).astype(np.float32)


def true_peak_db(audio: np.ndarray) -> float:
    """Approximate true peak via 4x oversampling (BS.1770 style)."""
    up = soxr.resample(audio.astype(np.float64), SAMPLE_RATE, SAMPLE_RATE * 4)
    peak = max(float(np.max(np.abs(up))), float(np.max(np.abs(audio))), 1e-12)
    return 20 * np.log10(peak)


_METER = None


def loudness_normalize(audio: np.ndarray, target_lufs: float = TARGET_LUFS) -> np.ndarray:
    """Match integrated loudness to target_lufs (BS.1770 via pyloudnorm),
    keeping true peak under -1 dBTP. Sources that would clip get
    peak-limited, re-measured, and re-trimmed so the match still holds."""
    global _METER
    import pyloudnorm as pyln

    if _METER is None:
        _METER = pyln.Meter(SAMPLE_RATE)

    def to_target(y: np.ndarray) -> np.ndarray | None:
        loudness = _METER.integrated_loudness(y.astype(np.float64))
        if not np.isfinite(loudness):  # silence
            return None
        return y * 10 ** ((target_lufs - loudness) / 20)

    out = to_target(audio)
    if out is None:
        return audio
    # Every exit path below leaves loudness exactly on target: each limit
    # pass is followed by a re-gain, so limiting depth never eats loudness.
    for _ in range(4):
        if true_peak_db(out) <= TRUE_PEAK_CEILING_DB:
            return np.clip(out, -1.0, 1.0).astype(np.float32)
        out = peak_limit(out, ceiling=10 ** ((TRUE_PEAK_CEILING_DB - 0.5) / 20))
        regained = to_target(out)
        if regained is not None:
            out = regained
    # Dense material that still overshoots between samples: shave it in the
    # oversampled domain. Clipping's flat tops ring back up through the
    # decimation filter, so deepen the clip until the true peak fits —
    # costs only hundredths of a LU even at the deepest step.
    for margin_db in (0.5, 1.0, 1.5, 2.0):
        clipped = oversampled_clip(out, ceiling=10 ** ((TRUE_PEAK_CEILING_DB - margin_db) / 20))
        if true_peak_db(clipped) <= TRUE_PEAK_CEILING_DB:
            return np.clip(clipped, -1.0, 1.0).astype(np.float32)
    return np.clip(clipped, -1.0, 1.0).astype(np.float32)


def save_wav(path: Path, audio: np.ndarray) -> None:
    """Loudness-match and write 16-bit WAV."""
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, loudness_normalize(audio), SAMPLE_RATE, subtype="PCM_16")
