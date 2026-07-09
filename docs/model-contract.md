# DeepFilterNet3 Core ML — preprocessing contract

The Core ML model (`tools/spike/models/DeepFilterNet3.mlpackage`) is the
neural network only. Everything below must be implemented in Swift, exactly
as specified; every formula here was verified numerically against the
reference implementation (`libdf`) to ≤1e-5 (see
`tools/spike/verify_coreml.py`, which self-checks this document on every
run).

## Audio format

- **48,000 Hz, mono, float32**, any length. (App-internal standard.)
- Processing is offline; the whole clip goes through in one prediction.

## STFT (analysis)

| Parameter | Value |
|---|---|
| FFT size N | 960 (20 ms) |
| Hop H | 480 (10 ms) |
| Window | **Vorbis**: `w[n] = sin(π/2 · sin²(π(n+0.5)/960))`, n = 0…959 |
| Scale | multiply spectrum by **1/960** |
| Bins F | 481 (`rfft`) |

Streaming alignment with **one hop of zero history**: with
`xh = concat(zeros(480), x)`, frame `k` (k = 0…T−1, `T = floor(len(x)/480)`)
is

```
spec[k] = rfft(w · xh[k·480 : k·480+960]) / 960        // complex, 481 bins
```

Before analysis, **pad the end of the audio with 960 zeros** (delay
compensation, see ISTFT).

## Model inputs (all float; complex packed as […, 2] = (re, im))

1. `spec` `[1, 1, T, 481, 2]` — the STFT above.
2. `feat_erb` `[1, 1, T, 32]` — ERB log-power, mean-normalized:
   - Band widths in bins (sum = 481):
     `[2,2,2,2,2,2,2,2,2,2,2,2,2,5,5,7,7,8,10,12,13,15,18,20,24,28,31,37,42,50,56,67]`
   - `E[k,b] = 10·log10( mean(|spec[k, bins of b]|²) + 1e-10 )`
   - Exponential-mean normalization, α = 0.99, per band, sequential over k:
     `s[b] ← (1−α)·E[k,b] + α·s[b]`, **init `s = linspace(−60, −90, 32)`**
     `feat_erb[k,b] = (E[k,b] − s[b]) / 40`
3. `feat_spec` `[1, 1, T, 96, 2]` — first 96 bins of `spec`, unit-normalized:
   - `s[f] ← (1−α)·|spec[k,f]| + α·s[f]`, α = 0.99,
     **init `s = linspace(0.001, 0.0001, 96)`**
   - `feat_spec[k,f] = spec[k,f] / sqrt(s[f])` (complex ÷ real)

Both normalizations are stateful left-to-right scans — do not vectorize the
time axis independently.

## Model output

`enhanced_spec` `[1, 1, T, 481, 2]` — enhanced complex STFT, same frame
grid and scaling as the input `spec`.

## ISTFT (synthesis)

Overlap-add with the same Vorbis window (it satisfies the Princen-Bradley
condition, so analysis·synthesis windows sum to 1 at 50% overlap):

```
y = zeros(T·480 + 480)
for k in 0…T−1:
    y[k·480 : k·480+960] += irfft(enhanced_spec[k] · 960) · w
```

The analysis/synthesis loop has an algorithmic delay of **N − H = 480
samples**: the final output is `y[480 : 480 + originalLength]`. (The 960
zeros appended before analysis guarantee the last real samples flush
through.)

## Noise-suppression depth (post-model, in Swift)

The raw model applies full suppression. The shipped pipeline blends the
enhanced signal with the input per clip (adaptive floor / voiced rescue,
reference: `dfn_adaptive_floor` in `tools/spike/restore.py`); that stage is
plain sample math on the two waveforms and carries no model contract.

## Precision

The default export is **float16** (Core ML `mlprogram`, iOS 17, compute
units `.all`). Measured deviation vs PyTorch float32 is reported by
`verify_coreml.py`; re-export with `--fp32` if it ever matters.
