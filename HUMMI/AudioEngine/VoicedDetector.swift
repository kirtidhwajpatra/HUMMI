//
//  VoicedDetector.swift
//  HUMMI
//

import Accelerate

/// Per-sample mask of pitched (sung) content, used to gate the DFN
/// rescue. YIN with cumulative-mean normalization — a deterministic
/// stand-in for the spike's librosa pyin voiced flag (restore.py
/// _voiced_mask). Requires f0 >= 130 Hz: pitch trackers lock onto
/// traffic/fan rumble at their fmin boundary, while sung notes sit
/// well above.
nonisolated enum VoicedDetector {
    static let frameLength = 6_144          // W + max lag headroom
    static let hop = 1_024                  // ~21 ms
    static let correlationLength = 4_096    // YIN window W, ~85 ms (pyin uses ~93 ms)
    static let fMin = 110.0
    static let minF0 = 130.0
    static let voicingThreshold = 0.5     // CMND depth; calibrated vs librosa pyin on vibrato.m4a

    /// 0/1 mask, one value per input sample.
    static func mask(
        _ samples: [Float], sampleRate: Double = DFNContract.sampleRate
    ) -> [Float] {
        let maxLag = Int(sampleRate / fMin)               // 436 @ 48 kHz
        let maxVoicedLag = Int(sampleRate / minF0)        // 369 @ 48 kHz
        var mask = [Float](repeating: 0, count: samples.count)
        guard samples.count >= frameLength else { return mask }

        var start = 0
        var frameIndex = 0
        while start + frameLength <= samples.count {
            if isVoiced(
                samples, frameStart: start, maxLag: maxLag,
                maxVoicedLag: maxVoicedLag
            ) {
                let lo = frameIndex * hop
                let hi = min(lo + hop, samples.count)
                for i in lo..<hi {
                    mask[i] = 1
                }
            }
            start += hop
            frameIndex += 1
        }
        return mask
    }

    /// YIN on one frame: difference function d(τ) = Σ (x[j] − x[j+τ])²
    /// over W samples, cumulative-mean normalized, voiced when the best
    /// trough is deep (< threshold) at a lag within the singing range.
    static func isVoiced(
        _ samples: [Float], frameStart: Int, maxLag: Int, maxVoicedLag: Int
    ) -> Bool {
        let w = correlationLength
        let base = samples[frameStart..<frameStart + w]

        // Energy of x[τ..<τ+W] for each lag via one prefix-sum pass.
        var prefixSquares = [Double](repeating: 0, count: w + maxLag + 1)
        for i in 0..<(w + maxLag) {
            let v = Double(samples[frameStart + i])
            prefixSquares[i + 1] = prefixSquares[i] + v * v
        }
        let energy0 = prefixSquares[w]

        var cumulative = 0.0
        var bestNormalized = Double.infinity
        var bestLag = 0
        for lag in 1...maxLag {
            let shifted = samples[(frameStart + lag)..<(frameStart + lag + w)]
            let dot = Double(vDSP.dot(base, shifted))
            let energyLag = prefixSquares[lag + w] - prefixSquares[lag]
            let difference = max(energy0 + energyLag - 2 * dot, 0)
            cumulative += difference
            guard cumulative > 0 else { continue }  // digital silence
            let normalized = difference * Double(lag) / cumulative
            if normalized < bestNormalized {
                bestNormalized = normalized
                bestLag = lag
            }
        }
        return bestNormalized < voicingThreshold && bestLag <= maxVoicedLag
    }
}
