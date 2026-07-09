//
//  RealFFT.swift
//  HUMMI
//

import Accelerate

/// Real FFT/inverse (numpy rfft/irfft semantics) on top of vDSP.DFT,
/// shared by the offline DSP stages. `count` must be a size vDSP.DFT
/// accepts (f · 2^n, f ∈ {1, 3, 5, 15}).
nonisolated struct RealFFT {
    let count: Int
    var binCount: Int { count / 2 + 1 }
    private let forwardDFT: vDSP.DFT<Float>
    private let inverseDFT: vDSP.DFT<Float>

    init(count: Int) throws {
        guard
            let forward = vDSP.DFT(
                count: count, direction: .forward,
                transformType: .complexComplex, ofType: Float.self),
            let inverse = vDSP.DFT(
                count: count, direction: .inverse,
                transformType: .complexComplex, ofType: Float.self)
        else {
            throw DFNError.dspUnavailable
        }
        self.count = count
        self.forwardDFT = forward
        self.inverseDFT = inverse
    }

    /// rfft: `real.count == count` in, `binCount` (re, im) pairs out.
    func forward(_ real: [Float]) -> (re: [Float], im: [Float]) {
        let zeros = [Float](repeating: 0, count: count)
        var outRe = [Float](repeating: 0, count: count)
        var outIm = [Float](repeating: 0, count: count)
        forwardDFT.transform(
            inputReal: real, inputImaginary: zeros,
            outputReal: &outRe, outputImaginary: &outIm)
        return (Array(outRe[0..<binCount]), Array(outIm[0..<binCount]))
    }

    /// irfft: `binCount` (re, im) pairs in, `count` real samples out,
    /// scaled so that inverse(forward(x)) == x.
    func inverse(re: [Float], im: [Float]) -> [Float] {
        var fullRe = [Float](repeating: 0, count: count)
        var fullIm = [Float](repeating: 0, count: count)
        for b in 0..<binCount {
            fullRe[b] = re[b]
            fullIm[b] = im[b]
        }
        // Real-signal spectrum: DC/Nyquist real, upper half conjugate.
        fullIm[0] = 0
        fullIm[count / 2] = 0
        for b in 1..<(count / 2) {
            fullRe[count - b] = fullRe[b]
            fullIm[count - b] = -fullIm[b]
        }
        var outRe = [Float](repeating: 0, count: count)
        var outIm = [Float](repeating: 0, count: count)
        inverseDFT.transform(
            inputReal: fullRe, inputImaginary: fullIm,
            outputReal: &outRe, outputImaginary: &outIm)
        return vDSP.multiply(1 / Float(count), outRe)
    }
}
