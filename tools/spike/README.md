# Enhancement spike

Bake-off chasing a dramatic before/after for StudioVocals. Two-stage
pipeline: **Stage A** restores the recording (ML), **Stage B** polishes
it like a studio engineer (DSP). Every clip in `TestClips/` is rendered
through each variant, and `index.html` gives instant A/B switching.

## Variants (index.html columns)

| Key | Column | Stage A | Stage B |
|---|---|---|---|
| 1 | Original | — | loudness match only |
| 2 | A1+B | DeepFilterNet3, adaptive floor (suppress only to ~45dB below the voice — full depth gates breaths/onsets and flutters) | standard |
| 3 | A2+B | Full VoiceFixer magnitude re-phased onto the real recording (fizz-capped, rescued) | standard + tune 0.4 |
| 4 | Hybrid+B | VF·DFN3 spectral-gain blend: 35% VF <1.5kHz / 60% above, glitch-ducked, 80ms-smoothed gain | standard + tune 0.4 |
| 5 | WPE+B | WPE dereverb → DFN3 — pure filtering, no vocoder, cannot be robotic | standard |
| 6 | Hybrid+B-Strong | same as 4 | 25% reverb, 25% saturation, +5dB air, tune 0.4 |
| 7 | WPE+B-Strong | WPE → DFN3 | 25% reverb, 25% saturation, +5dB air |

Columns 3/4/6 include **gentle chromatic auto-tune** (`autotune.py`, Praat
PSOLA): the correction curve is smoothed over ~150ms so vibrato and glides
pass through — only sustained center-pitch drift is pulled toward the
nearest semitone. Both VF columns ship **zero vocoder phase**: VoiceFixer
contributes only a smooth, bounded spectral gain over the real recording.

**Stage B (standard)**: 80Hz high-pass (12dB/oct) → -3dB bell @ 300Hz
Q1.2 + -2dB bell @ 500Hz Q2 → de-esser (dynamic 6-9kHz cut, bites only
on sibilants) → 3-band compression (<250Hz / 250Hz-4kHz / >4kHz, 3:1,
auto makeup) → parallel saturation 15% → +2dB bell @ 3kHz + +3.5dB shelf
@ 10kHz → convolution reverb (real IR from `irs/`, 20ms pre-delay, 18%
wet) → glue compressor 2:1 @ -14dB, 30ms attack.

**Loudness**: everything (originals included) is matched to **-14 LUFS**
with a **-1 dBTP** true-peak ceiling — level never biases the A/B.

**Reverb IR**: `irs/french-salon.wav` ("French 18th Century Salon",
Voxengo IMreverbs free pack, ~0.8s decay). Drop any other .wav IR into
`irs/` to use it instead (first file alphabetically wins).

## Artifact guards

VoiceFixer's own long-file handling resynthesizes fixed 30s segments with
no overlap — a hard phase seam every 30s and a possibly tiny, garbled
final segment (robotic glitches). We bypass it: `restore.py` runs ≤24s
windows (last one end-aligned, never a stub) and crossfades 2s overlaps.
The A3 DeepFilterNet3 pass runs with a 10dB attenuation limit — at full
depth it gates chunks of VoiceFixer's resynthesized voice in and out.
VoiceFixer also drops/garbles the softest breathy passages (trail-offs):
wherever its output level falls 6dB+ below the input (calibrated), the
A2 stage crossfades to an attenuation-limited DFN3 restoration instead.

## Vibrato guard

For clips named `*vibrato*`, the run prints a pitch-contour correlation
(librosa pyin) between the original and each Stage-A output. Below 0.95
it warns — that means the restoration model is damaging the singing.

## Setup

Requires Python 3.10–3.12 (`deepfilternet` has no wheels for newer).
Easiest with [uv](https://docs.astral.sh/uv/):

```sh
cd tools/spike
uv venv --python 3.11
uv pip install -r requirements.txt
```

No ffmpeg needed on macOS — m4a clips are decoded with the built-in
`afconvert`. On other platforms install ffmpeg.

## Run

```sh
cd tools/spike
.venv/bin/python spike.py
open ../../TestClips/output/index.html
```

First run downloads model weights (DeepFilterNet3 ~60MB, VoiceFixer
~625MB); after that it runs fully offline. Full run over 8 clips takes
a few minutes on CPU (VoiceFixer dominates).

In the HTML page: **play any clip, then press number keys 1-6 to switch
variant in place** — playback position carries over, like an A/B toggle.

Useful flags:

```sh
# Fast iteration on the DSP chain only (skips VoiceFixer):
.venv/bin/python spike.py --variants a1_b --skip-pitch-guard

# Clips somewhere else:
.venv/bin/python spike.py --clips-dir /path/to/clips
```

## Core ML export (what ships on-device)

Per `docs/spike-decision.md`, DeepFilterNet3 is the only model ported to
iOS. The export is the neural network alone — STFT, features, and ISTFT
are implemented in Swift against `docs/model-contract.md`:

```sh
.venv/bin/python convert_coreml.py    # → models/DeepFilterNet3.mlpackage
.venv/bin/python verify_coreml.py     # contract self-check vs libdf +
                                      # Core ML vs PyTorch on a real clip
```

`verify_coreml.py` fails loudly if the contract doc drifts from libdf
(>1e-4) and writes both renders to `TestClips/output/coreml-verify/` for
listening. Measured fp16 deviation: −61.5 dB (vibrato) / −50.0 dB
(fan-noise) relative to signal — far below audibility.

## Files

```
spike.py          orchestration + CLI
restore.py        Stage A (DeepFilterNet3, VoiceFixer)
polish.py         Stage B chain + presets
autotune.py       gentle chromatic auto-tune (Praat PSOLA)
audio_io.py       decode, LUFS matching, true-peak limiting
pitch_guard.py    vibrato pitch-contour check
html_index.py     A/B grid page generator
convert_coreml.py DFN3 → Core ML export (docs/model-contract.md)
verify_coreml.py  contract + Core ML numerical verification
irs/              convolution reverb impulse responses
models/           exported .mlpackage (gitignored — regenerate to update)
```
