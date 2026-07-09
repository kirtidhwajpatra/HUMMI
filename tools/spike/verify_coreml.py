#!/usr/bin/env python3
"""Verify the Core ML export against PyTorch DeepFilterNet3 on a real clip.

Two pipelines over the SAME audio:
  (a) reference: df.enhance() — PyTorch model + libdf DSP;
  (b) contract:  numpy preprocessing exactly per docs/model-contract.md
      + Core ML prediction + numpy ISTFT.

Every numpy DSP step is first self-checked against libdf (the contract must
hold to ≤1e-5), then the two enhanced waveforms are compared and written to
TestClips/output/coreml-verify/ for listening.

Run:  .venv/bin/python verify_coreml.py [--clip path] [--model path.mlpackage]
"""

import argparse
from pathlib import Path

import numpy as np
import soundfile as sf
import torch

import restore
from audio_io import SAMPLE_RATE, load_clip

restore._install_torchaudio_shim()

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODEL = Path(__file__).resolve().parent / "models" / "DeepFilterNet3.mlpackage"
DEFAULT_CLIP = REPO_ROOT / "TestClips" / "vibrato.m4a"
OUT_DIR = REPO_ROOT / "TestClips" / "output" / "coreml-verify"

N_FFT, HOP, N_ERB, N_DF = 960, 480, 32, 96
ALPHA = 0.99
ERB_WIDTHS = np.array([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 5, 5, 7, 7, 8,
                       10, 12, 13, 15, 18, 20, 24, 28, 31, 37, 42, 50, 56, 67])
VORBIS = np.sin(0.5 * np.pi * np.sin(np.pi * (np.arange(N_FFT) + 0.5) / N_FFT) ** 2)


# --- numpy implementation of docs/model-contract.md ---

def analysis(x: np.ndarray) -> np.ndarray:
    xh = np.concatenate([np.zeros(HOP, np.float32), x])
    T = len(x) // HOP
    frames = np.stack([xh[k * HOP:k * HOP + N_FFT] for k in range(T)])
    return np.fft.rfft(frames * VORBIS, N_FFT).astype(np.complex64) / N_FFT


def erb_features(spec: np.ndarray) -> np.ndarray:
    p2 = np.abs(spec) ** 2
    idx = np.concatenate([[0], np.cumsum(ERB_WIDTHS)])
    e = 10 * np.log10(np.stack(
        [p2[:, a:b].mean(-1) for a, b in zip(idx[:-1], idx[1:])], -1) + 1e-10)
    s = np.linspace(-60.0, -90.0, N_ERB)
    out = np.empty_like(e)
    for k in range(len(e)):
        s = (1 - ALPHA) * e[k] + ALPHA * s
        out[k] = (e[k] - s) / 40.0
    return out.astype(np.float32)


def spec_features(spec: np.ndarray) -> np.ndarray:
    z = spec[:, :N_DF]
    s = np.linspace(0.001, 0.0001, N_DF)
    out = np.empty_like(z)
    for k in range(len(z)):
        s = (1 - ALPHA) * np.abs(z[k]) + ALPHA * s
        out[k] = z[k] / np.sqrt(s)
    return out


def synthesis(spec: np.ndarray, out_len: int) -> np.ndarray:
    T = spec.shape[0]
    y = np.zeros(T * HOP + HOP)
    frames = np.fft.irfft(spec * N_FFT, N_FFT) * VORBIS
    for k in range(T):
        y[k * HOP:k * HOP + N_FFT] += frames[k]
    return y[HOP:HOP + out_len].astype(np.float32)  # N_FFT - HOP delay


def main() -> None:
    import coremltools as ct
    from df.enhance import enhance, init_df
    from libdf import erb, erb_norm, unit_norm

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", type=Path, default=DEFAULT_CLIP)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    args = parser.parse_args()

    audio = load_clip(args.clip)
    n = len(audio)
    model, df_state, _ = init_df()

    # (a) reference: PyTorch + libdf, exactly the spike's path
    ref = enhance(model, df_state, torch.from_numpy(audio[None, :]))
    ref = ref.squeeze(0).numpy().astype(np.float32)

    # (b) contract path. enhance() pads the tail with n_fft zeros; mirror it.
    padded = np.concatenate([audio, np.zeros(N_FFT, np.float32)])
    spec = analysis(padded)

    # self-check the contract against libdf before trusting it
    df_state.reset()
    spec_ld = df_state.analysis(padded[None, :].copy())[0][:len(spec)]
    a_err = np.max(np.abs(spec - spec_ld))
    e_np = erb_features(spec)
    e_ld = erb_norm(erb(spec_ld[None], ERB_WIDTHS.astype(np.uint64)), ALPHA)[0]
    e_err = np.max(np.abs(e_np - e_ld))
    z_np = spec_features(spec)
    z_ld = unit_norm(spec_ld[None, :, :N_DF].copy(), ALPHA)[0]
    z_err = np.max(np.abs(z_np - z_ld))
    df_state.reset()
    rt = df_state.synthesis(spec_ld[None].copy())[0]
    s_np = synthesis(spec, len(rt) - HOP)
    s_err = np.max(np.abs(s_np - rt[HOP:]))
    print("contract self-checks vs libdf (must be ~1e-5 or below):")
    print(f"  analysis {a_err:.2e}   erb-feat {e_err:.2e}   "
          f"spec-feat {z_err:.2e}   synthesis {s_err:.2e}")
    if max(a_err, e_err, z_err, s_err) > 1e-4:
        raise SystemExit("CONTRACT VIOLATION — docs/model-contract.md is wrong")

    # Core ML prediction
    mlmodel = ct.models.MLModel(str(args.model))
    T = spec.shape[0]
    pack = lambda z: np.stack([z.real, z.imag], -1).astype(np.float32)
    pred = mlmodel.predict({
        "spec": pack(spec)[None, None],
        "feat_erb": e_np[None, None],
        "feat_spec": pack(z_np)[None, None],
    })["enhanced_spec"].reshape(T, 481, 2)
    enh_spec = (pred[..., 0] + 1j * pred[..., 1]).astype(np.complex64)
    # synthesis() already removes the N_FFT-HOP algorithmic delay — the same
    # d = n_fft - hop trim that enhance() applies to the reference path.
    cml = synthesis(enh_spec, n)

    # compare + render
    m = min(len(ref), len(cml))
    ref, cml = ref[:m], cml[:m]
    diff = ref - cml
    rms = lambda x: np.sqrt(np.mean(x ** 2)) + 1e-12
    print(f"\nPyTorch vs Core ML over {m / SAMPLE_RATE:.1f}s:")
    print(f"  max |sample diff|   {np.max(np.abs(diff)):.3e}  "
          f"(full scale = 1.0)")
    print(f"  rms diff            {20 * np.log10(rms(diff)):.1f} dBFS")
    print(f"  diff rel. signal    {20 * np.log10(rms(diff) / rms(ref)):.1f} dB")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stem = args.clip.stem
    for name, y in (("pytorch", ref), ("coreml", cml)):
        sf.write(OUT_DIR / f"{stem}-{name}.wav", y, SAMPLE_RATE, subtype="FLOAT")
    print(f"\nListen: {OUT_DIR}/{stem}-pytorch.wav vs {stem}-coreml.wav")


if __name__ == "__main__":
    main()
