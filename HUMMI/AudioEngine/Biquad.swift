//
//  Biquad.swift
//  HUMMI
//

import Foundation

/// One IIR filter section, with constructors matching the exact filters
/// pedalboard/JUCE uses in the spike (verified coefficient-for-
/// coefficient against pedalboard impulse responses):
/// PeakFilter/HighShelfFilter are RBJ cookbook sections, HighpassFilter
/// is a first-order bilinear high-pass.
nonisolated struct Biquad {
    var b0: Double, b1: Double, b2: Double
    var a1: Double, a2: Double

    /// RBJ peaking EQ (pedalboard PeakFilter).
    static func peak(
        frequency: Double, gainDB: Double, q: Double,
        sampleRate: Double = DFNContract.sampleRate
    ) -> Biquad {
        let amp = pow(10.0, gainDB / 40.0)
        let w = 2.0 * .pi * frequency / sampleRate
        let alpha = sin(w) / (2.0 * q)
        let a0 = 1.0 + alpha / amp
        return Biquad(
            b0: (1.0 + alpha * amp) / a0,
            b1: -2.0 * cos(w) / a0,
            b2: (1.0 - alpha * amp) / a0,
            a1: -2.0 * cos(w) / a0,
            a2: (1.0 - alpha / amp) / a0)
    }

    /// RBJ high shelf at Q = 1/√2 (pedalboard HighShelfFilter).
    static func highShelf(
        frequency: Double, gainDB: Double,
        sampleRate: Double = DFNContract.sampleRate
    ) -> Biquad {
        let amp = pow(10.0, gainDB / 40.0)
        let w = 2.0 * .pi * frequency / sampleRate
        let cosw = cos(w)
        let alpha = sin(w) / 2.0.squareRoot()  // Q = 1/√2
        let root = 2.0 * amp.squareRoot() * alpha
        let a0 = (amp + 1.0) - (amp - 1.0) * cosw + root
        return Biquad(
            b0: amp * ((amp + 1.0) + (amp - 1.0) * cosw + root) / a0,
            b1: -2.0 * amp * ((amp - 1.0) + (amp + 1.0) * cosw) / a0,
            b2: amp * ((amp + 1.0) + (amp - 1.0) * cosw - root) / a0,
            a1: 2.0 * ((amp - 1.0) - (amp + 1.0) * cosw) / a0,
            a2: ((amp + 1.0) - (amp - 1.0) * cosw - root) / a0)
    }

    /// RBJ low shelf at Q = 1/√2 — warmth boost/cut below `frequency`.
    static func lowShelf(
        frequency: Double, gainDB: Double,
        sampleRate: Double = DFNContract.sampleRate
    ) -> Biquad {
        let amp = pow(10.0, gainDB / 40.0)
        let w = 2.0 * .pi * frequency / sampleRate
        let cosw = cos(w)
        let alpha = sin(w) / 2.0.squareRoot()  // Q = 1/√2
        let root = 2.0 * amp.squareRoot() * alpha
        let a0 = (amp + 1.0) + (amp - 1.0) * cosw + root
        return Biquad(
            b0: amp * ((amp + 1.0) - (amp - 1.0) * cosw + root) / a0,
            b1: 2.0 * amp * ((amp - 1.0) - (amp + 1.0) * cosw) / a0,
            b2: amp * ((amp + 1.0) - (amp - 1.0) * cosw - root) / a0,
            a1: -2.0 * ((amp - 1.0) + (amp + 1.0) * cosw) / a0,
            a2: ((amp + 1.0) + (amp - 1.0) * cosw - root) / a0)
    }

    /// First-order bilinear high-pass, 6 dB/oct (pedalboard
    /// HighpassFilter): b0 = 1/(1+G), pole (1−G)/(1+G), G = tan(πfc/fs).
    static func firstOrderHighPass(
        frequency: Double, sampleRate: Double = DFNContract.sampleRate
    ) -> Biquad {
        let g = tan(.pi * frequency / sampleRate)
        let b0 = 1.0 / (1.0 + g)
        return Biquad(b0: b0, b1: -b0, b2: 0, a1: -(1.0 - g) * b0, a2: 0)
    }

    /// Direct-form II transposed, double-precision state.
    func apply(_ samples: [Float]) -> [Float] {
        var s1 = 0.0
        var s2 = 0.0
        var output = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let x = Double(samples[i])
            let y = b0 * x + s1
            s1 = b1 * x - a1 * y + s2
            s2 = b2 * x - a2 * y
            output[i] = Float(y)
        }
        return output
    }
}
