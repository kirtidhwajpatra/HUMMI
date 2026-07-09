//
//  DFNContract.swift
//  HUMMI
//

import Foundation

/// Numeric contract for the DeepFilterNet3 Core ML model. Every value here
/// mirrors docs/model-contract.md and is validated against the reference
/// implementation by tools/spike/verify_coreml.py — do not change one
/// without the other.
nonisolated enum DFNContract {
    static let sampleRate: Double = 48_000
    /// FFT size N (20 ms).
    static let fftSize = 960
    /// Hop H (10 ms).
    static let hop = 480
    /// rfft bins F = N/2 + 1.
    static let binCount = 481
    /// ERB feature bands.
    static let erbBandCount = 32
    /// Deep-filtered low bins F' (feat_spec width).
    static let dfBinCount = 96
    /// Exponential-mean coefficient for both feature normalizations.
    static let normAlpha = 0.99

    /// ERB band widths in bins; sums to 481.
    static let erbWidths: [Int] = [
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 5, 5, 7, 7, 8,
        10, 12, 13, 15, 18, 20, 24, 28, 31, 37, 42, 50, 56, 67,
    ]

    /// Vorbis window `w[n] = sin(π/2 · sin²(π(n+0.5)/N))`.
    static func vorbisWindow() -> [Float] {
        let n = Double(fftSize)
        return (0..<fftSize).map { i in
            let inner = sin(.pi * (Double(i) + 0.5) / n)
            return Float(sin(.pi / 2 * inner * inner))
        }
    }

    /// Initial state for the ERB mean normalizer: linspace(−60, −90, 32).
    static func erbNormInitialState() -> [Double] {
        linspace(from: -60, to: -90, count: erbBandCount)
    }

    /// Initial state for the unit normalizer: linspace(0.001, 0.0001, 96).
    static func unitNormInitialState() -> [Double] {
        linspace(from: 0.001, to: 0.0001, count: dfBinCount)
    }

    private static func linspace(from start: Double, to end: Double, count: Int) -> [Double] {
        (0..<count).map { start + (end - start) * Double($0) / Double(count - 1) }
    }
}
