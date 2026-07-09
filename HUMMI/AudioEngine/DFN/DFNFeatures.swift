//
//  DFNFeatures.swift
//  HUMMI
//

import Foundation

/// Feature extraction for the DeepFilterNet3 model, per
/// docs/model-contract.md. Both normalizations are stateful left-to-right
/// scans over the time axis — they must not be vectorized across frames.
nonisolated enum DFNFeatures {
    /// `feat_erb` [frames × 32]: ERB-banded log power with exponential
    /// mean normalization (α = 0.99), divided by 40.
    static func erb(spec: [Float], frames: Int) -> [Float] {
        let bins = DFNContract.binCount
        let bands = DFNContract.erbBandCount
        let alpha = DFNContract.normAlpha

        var state = DFNContract.erbNormInitialState()
        var features = [Float](repeating: 0, count: frames * bands)

        for k in 0..<frames {
            let base = k * bins * 2
            var bin = 0
            for (band, width) in DFNContract.erbWidths.enumerated() {
                var power: Double = 0
                for _ in 0..<width {
                    let re = Double(spec[base + 2 * bin])
                    let im = Double(spec[base + 2 * bin + 1])
                    power += re * re + im * im
                    bin += 1
                }
                let energy = 10 * log10(power / Double(width) + 1e-10)
                state[band] = (1 - alpha) * energy + alpha * state[band]
                features[k * bands + band] = Float((energy - state[band]) / 40)
            }
        }
        return features
    }

    /// `feat_spec` [frames × 96 × 2]: the first 96 complex bins divided by
    /// the square root of their exponential mean magnitude (α = 0.99).
    static func unitNorm(spec: [Float], frames: Int) -> [Float] {
        let bins = DFNContract.binCount
        let dfBins = DFNContract.dfBinCount
        let alpha = DFNContract.normAlpha

        var state = DFNContract.unitNormInitialState()
        var features = [Float](repeating: 0, count: frames * dfBins * 2)

        for k in 0..<frames {
            let specBase = k * bins * 2
            let outBase = k * dfBins * 2
            for f in 0..<dfBins {
                let re = Double(spec[specBase + 2 * f])
                let im = Double(spec[specBase + 2 * f + 1])
                state[f] = (1 - alpha) * (re * re + im * im).squareRoot() + alpha * state[f]
                let denominator = state[f].squareRoot()
                features[outBase + 2 * f] = Float(re / denominator)
                features[outBase + 2 * f + 1] = Float(im / denominator)
            }
        }
        return features
    }
}
