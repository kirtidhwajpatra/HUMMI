//
//  VorbisSTFT.swift
//  HUMMI
//

import Accelerate

/// STFT analysis/synthesis per docs/model-contract.md: 960-point FFT,
/// 480-sample hop, vorbis window, spectrum scaled by 1/960. Spectra are
/// packed float arrays of shape [frames × 481 × 2] as (re, im).
nonisolated struct VorbisSTFT {
    private let forward: vDSP.DFT<Float>
    private let inverse: vDSP.DFT<Float>
    private let window: [Float]

    init() throws {
        let n = DFNContract.fftSize
        guard
            let forward = vDSP.DFT(
                count: n, direction: .forward,
                transformType: .complexComplex, ofType: Float.self),
            let inverse = vDSP.DFT(
                count: n, direction: .inverse,
                transformType: .complexComplex, ofType: Float.self)
        else {
            throw DFNError.dspUnavailable
        }
        self.forward = forward
        self.inverse = inverse
        self.window = DFNContract.vorbisWindow()
    }

    /// Analyzes `samples`, which must already carry the 960-zero
    /// delay-compensation tail required by the contract. Frames align to
    /// one hop of zero history: frame k covers xh[k·480 ..< k·480+960]
    /// with xh = zeros(480) + samples.
    func analysis(_ samples: [Float]) -> (spec: [Float], frames: Int) {
        let n = DFNContract.fftSize
        let hop = DFNContract.hop
        let bins = DFNContract.binCount
        let frames = samples.count / hop

        var history = [Float](repeating: 0, count: hop)
        history.append(contentsOf: samples)

        var spec = [Float](repeating: 0, count: frames * bins * 2)
        var windowed = [Float](repeating: 0, count: n)
        let zeroImaginary = [Float](repeating: 0, count: n)
        var outRe = [Float](repeating: 0, count: n)
        var outIm = [Float](repeating: 0, count: n)
        let scale = 1 / Float(n)

        for k in 0..<frames {
            let start = k * hop
            vDSP.multiply(window, history[start..<start + n], result: &windowed)
            forward.transform(
                inputReal: windowed, inputImaginary: zeroImaginary,
                outputReal: &outRe, outputImaginary: &outIm)
            let base = k * bins * 2
            for b in 0..<bins {
                spec[base + 2 * b] = outRe[b] * scale
                spec[base + 2 * b + 1] = outIm[b] * scale
            }
        }
        return (spec, frames)
    }

    /// Overlap-adds the enhanced spectrum back to audio and strips the
    /// N − H = 480-sample algorithmic delay, returning `outputLength`
    /// samples.
    func synthesis(spec: [Float], frames: Int, outputLength: Int) -> [Float] {
        let n = DFNContract.fftSize
        let hop = DFNContract.hop
        let bins = DFNContract.binCount

        var output = [Float](repeating: 0, count: frames * hop + hop)
        var fullRe = [Float](repeating: 0, count: n)
        var fullIm = [Float](repeating: 0, count: n)
        var outRe = [Float](repeating: 0, count: n)
        var outIm = [Float](repeating: 0, count: n)
        var frame = [Float](repeating: 0, count: n)

        for k in 0..<frames {
            let base = k * bins * 2
            for b in 0..<bins {
                fullRe[b] = spec[base + 2 * b]
                fullIm[b] = spec[base + 2 * b + 1]
            }
            // irfft semantics: DC and Nyquist are real, upper half is the
            // conjugate mirror of the lower half.
            fullIm[0] = 0
            fullIm[n / 2] = 0
            for b in 1..<(n / 2) {
                fullRe[n - b] = fullRe[b]
                fullIm[n - b] = -fullIm[b]
            }
            // The contract synthesizes irfft(spec · 960); the analysis
            // already divided by 960, so the unscaled inverse DFT is exact.
            inverse.transform(
                inputReal: fullRe, inputImaginary: fullIm,
                outputReal: &outRe, outputImaginary: &outIm)
            vDSP.multiply(window, outRe, result: &frame)
            let offset = k * hop
            for i in 0..<n {
                output[offset + i] += frame[i]
            }
        }
        return Array(output[hop..<hop + outputLength])
    }
}
