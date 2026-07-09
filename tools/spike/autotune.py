"""Gentle chromatic pitch correction, applied before the polish chain.

Praat PSOLA (via the psola package) resynthesizes the voice with a
corrected pitch contour. The correction curve is smoothed over ~150ms, so
vibrato and note glides pass through untouched — only the sustained
center pitch gets pulled toward the nearest semitone. Chromatic snapping
needs no key detection and stays safe on any melody.
"""

import numpy as np
import soxr

from audio_io import SAMPLE_RATE

PYIN_SR = 22_050
PYIN_HOP = 512
MAX_CORRECTABLE_ST = 0.7  # notes further off-center are ambiguous: leave them


def autotune(audio: np.ndarray, strength: float) -> np.ndarray:
    """Pull sustained pitch toward the nearest semitone by `strength`
    (0..1). Returns the input unchanged if nothing voiced is found."""
    import librosa
    import psola
    from scipy.ndimage import uniform_filter1d

    y = soxr.resample(audio, SAMPLE_RATE, PYIN_SR).astype(np.float32)
    f0, voiced, _ = librosa.pyin(y, fmin=80, fmax=1_000, sr=PYIN_SR,
                                 hop_length=PYIN_HOP)
    if not np.any(voiced):
        return audio

    # continuous contour: interpolate f0 through unvoiced gaps
    idx = np.arange(len(f0))
    known = np.isfinite(f0)
    f0c = np.interp(idx, idx[known], f0[known])

    midi = 69.0 + 12.0 * np.log2(f0c / 440.0)
    # Correct the note's CENTER pitch, not the frame pitch: averaging over
    # ~250ms strips the vibrato, so the nearest-note target stays stable
    # across a vibrato cycle and the vibrato itself passes through intact.
    center = uniform_filter1d(midi, max(1, int(0.25 * PYIN_SR / PYIN_HOP)))
    offset = center - np.round(center)  # semitones off the nearest note
    correction = -offset * strength
    correction[np.abs(offset) > MAX_CORRECTABLE_ST] = 0.0
    correction[~voiced] = 0.0
    # smooth the on/off transitions so corrections fade in, never step
    correction = uniform_filter1d(correction,
                                  max(1, int(0.1 * PYIN_SR / PYIN_HOP)))

    target = f0c * 2.0 ** (correction / 12.0)
    out = psola.vocode(audio.astype(np.float64), SAMPLE_RATE,
                       target_pitch=target, fmin=75.0, fmax=1_000.0)
    out = np.asarray(out, dtype=np.float32)
    if len(out) < len(audio):
        out = np.pad(out, (0, len(audio) - len(out)))
    return out[:len(audio)]
