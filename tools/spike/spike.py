#!/usr/bin/env python3
"""Vocal-enhancement bake-off: Stage A restoration x Stage B polish.

Stage A (restoration): A1 = DeepFilterNet3, A2 = VoiceFixer (mode 0,
kept as the vocoder reference), hybrid = 50/50 VF·DFN3 blend (masks the
vocoder's robotic phase), wpe = WPE dereverb -> DFN3 (no vocoder at all).
Stage B (polish): EQ, de-esser, multiband compression, saturation,
convolution reverb, glue compressor — see polish.py.

Everything is loudness-matched to -14 LUFS / -1 dBTP. Outputs land in
TestClips/output/<variant>/<clipname>.wav plus an index.html A/B grid.
"""

import argparse
import sys
from pathlib import Path

import numpy as np

import polish as pol
import restore
from audio_io import AUDIO_EXTENSIONS, load_clip, save_wav
from html_index import write_index
from pitch_guard import run_guard

REPO_ROOT = Path(__file__).resolve().parents[2]

COLUMNS = [
    ("original", "Original"),
    ("a1_b", "A1+B (DFN3)"),
    ("a2_b", "A2+B (VF, tuned)"),
    ("hybrid_b", "Hybrid+B (tuned)"),
    ("wpe_b", "WPE+B (no vocoder)"),
    ("hybrid_b_strong", "Hybrid+B-Strong (tuned)"),
    ("wpe_b_strong", "WPE+B-Strong"),
]

# variant -> (stage A key, polish preset)
VARIANTS = {
    "a1_b": ("a1", pol.STANDARD),
    "a2_b": ("a2", pol.TUNED),
    "hybrid_b": ("hybrid", pol.TUNED),
    "wpe_b": ("wpe", pol.STANDARD),
    "hybrid_b_strong": ("hybrid", pol.TUNED_STRONG),
    "wpe_b_strong": ("wpe", pol.STRONG),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clips-dir", type=Path, default=REPO_ROOT / "TestClips")
    parser.add_argument("--variants", default=",".join(VARIANTS),
                        help=f"Comma-separated subset of: {', '.join(VARIANTS)}")
    parser.add_argument("--skip-pitch-guard", action="store_true")
    args = parser.parse_args()

    selected = [v.strip() for v in args.variants.split(",") if v.strip()]
    unknown = [v for v in selected if v not in VARIANTS]
    if unknown:
        parser.error(f"Unknown variant(s): {', '.join(unknown)}")

    clip_paths = sorted(p for p in args.clips_dir.iterdir()
                        if p.suffix.lower() in AUDIO_EXTENSIONS)
    if not clip_paths:
        print(f"No audio files found in {args.clips_dir}", file=sys.stderr)
        return 1

    output_dir = args.clips_dir / "output"
    print(f"Loading {len(clip_paths)} clips (48kHz mono)...")
    clips = [(p.stem, load_clip(p)) for p in clip_paths]
    for name, audio in clips:
        save_wav(output_dir / "original" / f"{name}.wav", audio)

    failures: list[str] = []

    # --- Stage A: compute each restoration output once, fail-soft.
    stage_a: dict[str, list[tuple[str, np.ndarray]]] = {}
    need = {VARIANTS[v][0] for v in selected}
    if need & {"a2", "hybrid"}:
        need |= {"a1", "a2"}  # both are built on VF + the DFN3 anchor

    dfn_full: list[tuple[str, np.ndarray]] = []
    if need & {"a1"}:
        try:
            print("Stage A1: DeepFilterNet3, adaptive suppression floor...")
            dfn_full = restore.dfn_enhance(clips)
            stage_a["a1"] = restore.dfn_adaptive_floor(clips, dfn_full)
        except Exception as exc:
            print(f"  SKIPPED A1: {type(exc).__name__}: {exc}", file=sys.stderr)
    vf_res: list[tuple[str, np.ndarray]] = []
    if need & {"a2"}:
        try:
            print("Stage A2: VoiceFixer (mode 0)...")
            vf_out = restore.voicefixer_restore(clips)
            print("  HF governor: cap VoiceFixer's synthetic fizz...")
            # Reference the full-suppression DFN3 (true voice HF); the
            # attenuation-limited fallback's residual noise inflates the cap.
            hf_ref = dfn_full or restore.dfn_enhance(clips)
            vf_out = restore.cap_hf_fizz(vf_out, hf_ref)
            print("  rescue pass: DFN3 fallback where VoiceFixer drops the audio...")
            fallback = restore.dfn_enhance(clips, atten_lim_db=10.0)
            vf_res = restore.rescue_dropouts(clips, vf_out, fallback)
            # Both VF columns are re-phased: VF supplies only a spectral
            # gain over the real recording; its vocoder phase never ships.
            print("  re-phase: full VoiceFixer magnitude on the real phase...")
            stage_a["a2"] = restore.blend_hybrid(vf_res, hf_ref,
                                                 low_vf=1.0, high_vf=1.0)
        except Exception as exc:
            print(f"  SKIPPED A2: {type(exc).__name__}: {exc}", file=sys.stderr)
    if "hybrid" in need and dfn_full and vf_res:
        # Anchor on the full-suppression DFN3, not the adaptive-floor a1:
        # the blend's noise floor comes from the VoiceFixer side.
        print("Stage A hybrid: tilted, glitch-ducked VoiceFixer·DFN3 blend...")
        stage_a["hybrid"] = restore.blend_hybrid(vf_res, dfn_full)
    if "wpe" in need:
        try:
            print("Stage A WPE: dereverb (linear, no vocoder) then DeepFilterNet3...")
            stage_a["wpe"] = restore.dfn_enhance(restore.wpe_dereverb(clips))
        except Exception as exc:
            print(f"  SKIPPED WPE: {type(exc).__name__}: {exc}", file=sys.stderr)

    # --- Vibrato guard: is Stage A damaging pitch (vibrato, runs)?
    guard_warnings: list[str] = []
    if not args.skip_pitch_guard:
        labels = {"a1": "DFN3", "a2": "VoiceFixer",
                  "hybrid": "VF·DFN3 blend", "wpe": "WPE→DFN3"}
        for name, audio in clips:
            if "vibrato" not in name.lower():
                continue
            outputs = {labels[k]: dict(v)[name] for k, v in stage_a.items()}
            if outputs:
                guard_warnings += run_guard(audio, outputs, name)

    # --- Stage B: polish each selected variant.
    for variant in selected:
        source_key, preset = VARIANTS[variant]
        if source_key not in stage_a:
            failures.append(variant)
            continue
        print(f"Stage B: {variant}...")
        try:
            for name, audio in stage_a[source_key]:
                save_wav(output_dir / variant / f"{name}.wav", pol.polish(audio, preset))
        except Exception as exc:
            failures.append(variant)
            print(f"  SKIPPED {variant}: {type(exc).__name__}: {exc}", file=sys.stderr)

    index = write_index(output_dir, COLUMNS)
    print(f"\nDone. Open: {index}")
    if guard_warnings:
        print("\nVIBRATO GUARD WARNINGS:", file=sys.stderr)
        for w in guard_warnings:
            print(f"  {w}", file=sys.stderr)
    if failures:
        print(f"Skipped variants (see errors above): {', '.join(failures)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
