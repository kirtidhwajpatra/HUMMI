"""Vibrato guard: verify restoration models aren't damaging the singing.

Compares pyin pitch contours of the original vs each Stage-A output.
A correlation below 0.95 on voiced frames means the model is smearing
or flattening pitch movement (vibrato, runs) and should be distrusted.
"""

import numpy as np
import soxr

from audio_io import SAMPLE_RATE

CORRELATION_FLOOR = 0.95
_PYIN_SR = 22_050  # pyin is slow; half-rate is plenty for pitch


def _pitch_track(audio: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    import librosa

    y = soxr.resample(audio, SAMPLE_RATE, _PYIN_SR).astype(np.float32)
    f0, voiced, _ = librosa.pyin(y, fmin=80, fmax=1_000, sr=_PYIN_SR)
    return f0, voiced


def pitch_correlation(reference: np.ndarray, candidate: np.ndarray) -> float:
    """Correlation of log-pitch contours over frames voiced in both."""
    f0_ref, v_ref = _pitch_track(reference)
    f0_can, v_can = _pitch_track(candidate)
    n = min(len(f0_ref), len(f0_can))
    both = v_ref[:n] & v_can[:n]
    if both.sum() < 50:  # not enough overlapping voiced frames to judge
        return float("nan")
    return float(np.corrcoef(np.log(f0_ref[:n][both]),
                             np.log(f0_can[:n][both]))[0, 1])


def run_guard(original: np.ndarray, stage_a_outputs: dict[str, np.ndarray],
              clip_name: str) -> list[str]:
    """Print the pitch-track comparison; return warning lines for models
    below the correlation floor."""
    print(f"\nVibrato guard — pitch contour vs original ({clip_name}):")
    warnings = []
    for label, audio in stage_a_outputs.items():
        corr = pitch_correlation(original, audio)
        if np.isnan(corr):
            verdict = "n/a (too few voiced frames)"
        elif corr < CORRELATION_FLOOR:
            verdict = f"WARNING — below {CORRELATION_FLOOR}, model is damaging the singing"
            warnings.append(f"{clip_name}/{label}: pitch correlation {corr:.3f}")
        else:
            verdict = "ok"
        corr_text = "  n/a" if np.isnan(corr) else f"{corr:.3f}"
        print(f"  {label:<12} {corr_text}  {verdict}")
    return warnings
