//
//  KeyEstimator.swift
//  HUMMI
//

import Foundation

/// Estimates the take's key from the pitch track: confident frames fold
/// to a 12-bin pitch-class histogram, which is Pearson-correlated with
/// the Krumhansl-Kessler major/minor profiles in all 24 rotations.
nonisolated enum KeyEstimator {
    static let confidenceGate = 0.8
    static let minimumFrames = 50  // ~0.5 s of confident pitch

    static let majorProfile: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
        2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
    ]
    static let minorProfile: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
        2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
    ]

    static func estimate(from frames: [PitchFrame]) -> MusicalKey? {
        guard let histogram = pitchClassHistogram(frames) else { return nil }

        var best: MusicalKey?
        var bestScore = -Double.infinity
        for root in 0..<12 {
            for minor in [false, true] {
                let profile = minor ? minorProfile : majorProfile
                let rotated = (0..<12).map { profile[(($0 - root) % 12 + 12) % 12] }
                let score = pearson(histogram, rotated)
                if score > bestScore {
                    bestScore = score
                    best = MusicalKey(root: root, minor: minor)
                }
            }
        }
        return best
    }

    /// Confidence-weighted pitch-class histogram, or nil when the take
    /// has too little confident pitch to name a key.
    static func pitchClassHistogram(_ frames: [PitchFrame]) -> [Double]? {
        var histogram = [Double](repeating: 0, count: 12)
        var counted = 0
        for frame in frames {
            guard frame.confidence >= confidenceGate,
                  let semitone = frame.semitone else { continue }
            let pitchClass = ((Int(semitone.rounded()) % 12) + 12) % 12
            histogram[pitchClass] += frame.confidence
            counted += 1
        }
        guard counted >= minimumFrames else { return nil }
        return histogram
    }

    static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var covariance = 0.0
        var varianceA = 0.0
        var varianceB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            covariance += da * db
            varianceA += da * da
            varianceB += db * db
        }
        let denominator = (varianceA * varianceB).squareRoot()
        return denominator > 1e-12 ? covariance / denominator : 0
    }
}
