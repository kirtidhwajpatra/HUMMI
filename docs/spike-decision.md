# Spike decision — enhancement pipeline

*(This file did not exist when the Core ML conversion was requested; it was
written 2026-07-06 to record the decision reached in the bake-off. Review
and amend if it misstates the intent.)*

## Outcome

The winning listening variant is **Hybrid+B (tuned)** — column 4 of the
spike's A/B grid — with **A1+B (DFN3)** as the no-frills reference that
also passed listening.

The architecture that emerged from the bake-off:

1. **DeepFilterNet3 (DFN3)** produces the *only* waveform we ship: the
   real recording, denoised, with an adaptive suppression floor, a voiced
   rescue, and a warm-up pre-roll (see `tools/spike/restore.py`).
2. **VoiceFixer** never contributes waveform or phase — vocoder output
   proved irreducibly robotic. Its surviving role is a *smooth, bounded
   spectral gain* (dereverb + air, ±12dB, 80ms-smoothed) applied over the
   DFN3 signal, plus fizz-capping and dropout-rescue guards.
3. **Stage B polish** (EQ → de-esser → multiband comp → saturation →
   presence/air → convolution reverb → glue) and **gentle chromatic
   auto-tune** (Praat PSOLA, strength 0.4) finish the sound.

## What ships on-device

**DFN3 is the model converted to Core ML** (`tools/spike/convert_coreml.py`
→ `models/DeepFilterNet3.mlpackage`, contract in `docs/model-contract.md`).
It is the neural core of every approved variant, is designed for embedded
use (~2M params), and its STFT-domain interface ports cleanly.

VoiceFixer (625MB, three sub-networks, PyTorch-only) is **not** converted:
impractical on iOS and no longer load-bearing — its spectral-gain role can
be approximated later by static/learned EQ, or dropped (column 2 passed
listening without it). The Stage B chain and auto-tune are DSP, to be
ported to Swift (AVAudioEngine / vDSP), not ML conversion targets.
