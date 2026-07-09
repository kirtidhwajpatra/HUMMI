#!/usr/bin/env python3
"""Export DeepFilterNet3 to Core ML (.mlpackage), iOS 17, compute units ALL.

The exported model is the neural network only: complex spectrum + features
in, enhanced complex spectrum out. The STFT/ISTFT and feature extraction
stay outside (Swift on device) — the exact preprocessing contract lives in
docs/model-contract.md and is validated end-to-end by verify_coreml.py.

Run:  .venv/bin/python convert_coreml.py [--fp32] [--out path.mlpackage]
"""

import argparse
from pathlib import Path

import torch

import restore

restore._install_torchaudio_shim()

DEFAULT_OUT = Path(__file__).resolve().parent / "models" / "DeepFilterNet3.mlpackage"
MAX_FRAMES = 16_384  # ~163s of audio at the 10ms hop; raise for longer clips
TRACE_FRAMES = 100


class DfNetWrapper(torch.nn.Module):
    """Re-implements DfNet.forward for conversion: Core ML supports neither
    complex tensors (df_op's view_as_complex einsum) nor the original's
    in-place slice assignments, so the deep-filter runs here as real-packed
    (re,im) math and the low/high bins are joined with cat. Numeric parity
    with the original forward is asserted in main() before tracing.
    Ships only enhanced_spec (original also returns mask, lsnr, coefs)."""

    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model
        self.frame_size = model.df_op.frame_size  # 5 taps, lookahead 2
        self.num_freqs = model.df_op.num_freqs    # 96 deep-filtered bins

    def forward(self, spec, feat_erb, feat_spec):
        m = self.model
        feat_spec = feat_spec.squeeze(1).permute(0, 3, 1, 2)
        feat_erb = m.pad_feat(feat_erb)
        feat_spec = m.pad_feat(feat_spec)
        e0, e1, e2, e3, emb, c0, _lsnr = m.enc(feat_erb, feat_spec)
        mask = m.erb_dec(emb, e3, e2, e1, e0)
        spec_m = m.mask(spec, mask)
        coefs = m.df_out_transform(m.df_dec(emb, c0))
        low = self._real_df(spec, coefs)
        return torch.cat([low, spec_m[..., self.num_freqs:, :]], dim=3)

    def _real_df(self, spec, coefs):
        """df_op without complex dtypes: out[t] = Σ_n spec[t-2+n]·coefs[n,t]
        over the first num_freqs bins. spec [B,1,T,481,2] (re,im);
        coefs [B,frame_size,T,num_freqs,2]."""
        N, F = self.frame_size, self.num_freqs
        x = spec[..., :F, :]
        z = torch.zeros_like(x[:, :, :N // 2])
        xp = torch.cat([z, x, z], dim=2)
        acc_re = torch.zeros_like(x[..., 0])
        acc_im = torch.zeros_like(x[..., 1])
        for n in range(N):
            # xp[:, :, n : n+T] with only static/negative bounds — dynamic
            # slice ends don't convert (see _TimeShift).
            w = xp[:, :, n:] if n == N - 1 else xp[:, :, n:n - (N - 1)]
            c = coefs[:, n].unsqueeze(1)
            ar, ai = w[..., 0], w[..., 1]
            cr, ci = c[..., 0], c[..., 1]
            acc_re = acc_re + ar * cr - ai * ci
            acc_im = acc_im + ar * ci + ai * cr
        return torch.stack([acc_re, acc_im], dim=-1)


class _TimeShift(torch.nn.Module):
    """Replaces DfNet's lookahead ConstantPad·d((..., -l, l)): Core ML's pad
    op rejects negative (cropping) pads, so shift via slice + zero-append.
    Open-ended slices (not narrow) — narrow's length is dynamic when the
    time dim is flexible, which Core ML's converter cannot handle."""

    def __init__(self, lookahead: int, time_dim: int):
        super().__init__()
        self.l, self.dim = lookahead, time_dim

    def forward(self, x):
        if self.dim == -2:
            head, tail_src = x[..., self.l:, :], x[..., :self.l, :]
        else:  # -3
            head, tail_src = x[..., self.l:, :, :], x[..., :self.l, :, :]
        return torch.cat([head, torch.zeros_like(tail_src)], dim=self.dim)


def _patch_negative_pads(model: torch.nn.Module) -> None:
    if isinstance(getattr(model, "pad_feat", None), torch.nn.ConstantPad2d):
        lookahead = model.pad_feat.padding[3]  # (0, 0, -l, l)
        model.pad_feat = _TimeShift(lookahead, time_dim=-2)
    if isinstance(getattr(model, "pad_spec", None), torch.nn.ConstantPad3d):
        lookahead = model.pad_spec.padding[5]  # (0, 0, 0, 0, -l, l)
        model.pad_spec = _TimeShift(lookahead, time_dim=-3)


def main() -> None:
    import coremltools as ct
    from df.enhance import init_df

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--fp32", action="store_true",
                        help="Keep float32 weights/compute (default: float16)")
    args = parser.parse_args()

    model, _, _ = init_df()
    model = model.cpu().eval()

    example = (torch.randn(1, 1, TRACE_FRAMES, 481, 2),
               torch.randn(1, 1, TRACE_FRAMES, 32),
               torch.randn(1, 1, TRACE_FRAMES, 96, 2))
    with torch.no_grad():
        reference = model(*example)[0]

    _patch_negative_pads(model)
    wrapper = DfNetWrapper(model).eval()
    with torch.no_grad():
        rewritten = wrapper(*example)
    err = (reference - rewritten).abs().max().item()
    print(f"wrapper parity vs original DfNet forward: max|diff| = {err:.2e}")
    if err > 1e-5:
        raise SystemExit("wrapper diverges from the original model — aborting")

    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example)

    def frames_dim():
        return ct.RangeDim(lower_bound=1, upper_bound=MAX_FRAMES,
                           default=TRACE_FRAMES)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="spec", shape=(1, 1, frames_dim(), 481, 2)),
            ct.TensorType(name="feat_erb", shape=(1, 1, frames_dim(), 32)),
            ct.TensorType(name="feat_spec", shape=(1, 1, frames_dim(), 96, 2)),
        ],
        outputs=[ct.TensorType(name="enhanced_spec")],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT32 if args.fp32 else ct.precision.FLOAT16,
        convert_to="mlprogram",
    )

    mlmodel.short_description = (
        "DeepFilterNet3 speech enhancement (neural core). STFT-domain I/O; "
        "preprocessing contract in docs/model-contract.md.")
    mlmodel.input_description["spec"] = "Complex STFT [1,1,T,481,2] (re,im), vorbis window 960/480 @48kHz, x1/960"
    mlmodel.input_description["feat_erb"] = "Normalized ERB log-power features [1,1,T,32]"
    mlmodel.input_description["feat_spec"] = "Unit-normalized complex spec, first 96 bins [1,1,T,96,2]"
    mlmodel.output_description["enhanced_spec"] = "Enhanced complex STFT [1,1,T,481,2]; ISTFT per contract"

    args.out.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.out))
    size_mb = sum(f.stat().st_size for f in args.out.rglob("*") if f.is_file()) / 1e6
    print(f"Saved {args.out} ({size_mb:.1f} MB, "
          f"{'fp32' if args.fp32 else 'fp16'}, iOS17, compute units ALL)")


if __name__ == "__main__":
    main()
