//
//  LoudnessNormalizeStage.swift
//  HUMMI
//

import Accelerate

/// Final output leveling to -14 "LUFS", approximated as BS.1770 gated
/// RMS without the K-weighting filter (the user-facing target; full
/// LUFS would add a ~1 dB shelf correction for voice). Gating keeps
/// long silences from inflating the gain: 400 ms blocks at 100 ms hop,
/// blocks below -70 dBFS are dropped, then blocks more than 10 dB
/// below the first-pass average are dropped. The gain is capped so the
/// output peak stays under the ceiling.
nonisolated final class LoudnessNormalizeStage: BufferStage {
    let name = "Normalize -14"
    var isEnabled = true

    static let blockSeconds = 0.4
    static let hopSeconds = 0.1
    static let absoluteGateDB = -70.0
    static let relativeGateDB = -10.0

    private let targetDB: Double
    private let peakCeilingDB: Double

    init(parameters: PresetParameters) {
        self.targetDB = parameters.normalizeTargetDB
        self.peakCeilingDB = parameters.normalizePeakCeilingDB
    }

    func process(_ samples: [Float]) throws -> [Float] {
        guard let loudness = Self.gatedLoudnessDB(samples) else {
            return samples  // silence: nothing to normalize
        }
        let peak = Double(vDSP.maximumMagnitude(samples))
        let gain = Self.gain(
            loudnessDB: loudness, targetDB: targetDB,
            peak: peak, peakCeilingDB: peakCeilingDB)
        return vDSP.multiply(Float(gain), samples)
    }

    // MARK: - Pure math (unit-tested)

    /// Gated integrated loudness in dBFS (RMS approximation of LUFS),
    /// or nil when no block passes the absolute gate.
    static func gatedLoudnessDB(
        _ samples: [Float], sampleRate: Double = DFNContract.sampleRate
    ) -> Double? {
        let blockLoudness = blockLoudnessDB(samples, sampleRate: sampleRate)

        let absGated = blockLoudness.filter { $0 > absoluteGateDB }
        guard !absGated.isEmpty else { return nil }
        let firstPass = meanEnergyDB(absGated)

        let relGated = absGated.filter { $0 > firstPass + relativeGateDB }
        guard !relGated.isEmpty else { return firstPass }
        return meanEnergyDB(relGated)
    }

    /// Mean-square loudness of each 400 ms block, 100 ms hop. A clip
    /// shorter than one block is one whole-clip block.
    static func blockLoudnessDB(
        _ samples: [Float], sampleRate: Double = DFNContract.sampleRate
    ) -> [Double] {
        let block = Int(blockSeconds * sampleRate)
        let hop = Int(hopSeconds * sampleRate)
        guard samples.count >= block else {
            return samples.isEmpty ? [] : [meanSquareDB(samples[0...])]
        }
        var out: [Double] = []
        var start = 0
        while start + block <= samples.count {
            out.append(meanSquareDB(samples[start..<start + block]))
            start += hop
        }
        return out
    }

    /// Gain to reach the target, capped so peak·gain stays under the
    /// ceiling. Never attenuates below what the ceiling requires; a
    /// too-loud clip is still pulled down to target.
    static func gain(
        loudnessDB: Double, targetDB: Double, peak: Double, peakCeilingDB: Double
    ) -> Double {
        let wanted = pow(10.0, (targetDB - loudnessDB) / 20.0)
        guard peak > 0 else { return wanted }
        let ceiling = pow(10.0, peakCeilingDB / 20.0) / peak
        return min(wanted, max(ceiling, 1e-6))
    }

    private static func meanSquareDB(_ samples: ArraySlice<Float>) -> Double {
        var sum = 0.0
        for s in samples {
            sum += Double(s) * Double(s)
        }
        return 10 * log10(sum / Double(samples.count) + 1e-20)
    }

    /// Average of block energies (not dB values), back in dB — how
    /// BS.1770 integrates.
    private static func meanEnergyDB(_ loudnessDB: [Double]) -> Double {
        let mean = loudnessDB.reduce(0.0) { $0 + pow(10.0, $1 / 10.0) }
            / Double(loudnessDB.count)
        return 10 * log10(mean)
    }
}
