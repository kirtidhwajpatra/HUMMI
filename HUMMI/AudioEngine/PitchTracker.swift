//
//  PitchTracker.swift
//  HUMMI
//

import Accelerate

/// One pitch estimate per ~10 ms hop.
nonisolated struct PitchFrame: Sendable {
    /// Fundamental in Hz, nil when the frame is unpitched.
    var f0: Double?
    /// 1 − YIN's normalized-difference trough depth: ~1 for clean pitch,
    /// ~0 for noise.
    var confidence: Double

    /// MIDI-style semitone value (A4 = 440 Hz = 69), nil when unpitched.
    var semitone: Double? {
        f0.map { 69.0 + 12.0 * log2($0 / 440.0) }
    }
}

/// YIN pitch tracking (de Cheveigné & Kawahara) over 480-sample hops:
/// difference function via vDSP dot products, cumulative-mean
/// normalization, absolute-threshold trough pick with parabolic lag
/// refinement for cent-level precision.
nonisolated enum PitchTracker {
    static let hop = 480                  // 10 ms @ 48 kHz
    static let window = 2_048             // correlation window W (~43 ms)
    static let minHz = 110.0
    static let maxHz = 1_000.0
    static let yinThreshold = 0.15        // classic YIN absolute threshold

    static func track(
        _ samples: [Float], sampleRate: Double = DFNContract.sampleRate
    ) -> [PitchFrame] {
        let maxLag = Int(sampleRate / minHz)          // 436
        let minLag = max(2, Int(sampleRate / maxHz))  // 48
        let span = window + maxLag
        guard samples.count >= span else { return [] }

        let frameCount = (samples.count - span) / hop + 1
        var frames = [PitchFrame](repeating: PitchFrame(f0: nil, confidence: 0), count: frameCount)

        var prefixSquares = [Double](repeating: 0, count: span + 1)
        var normalized = [Double](repeating: 0, count: maxLag + 1)

        for k in 0..<frameCount {
            let start = k * hop
            let base = samples[start..<start + window]

            prefixSquares[0] = 0
            for i in 0..<span {
                let v = Double(samples[start + i])
                prefixSquares[i + 1] = prefixSquares[i] + v * v
            }
            let energy0 = prefixSquares[window]
            guard energy0 > 1e-9 else { continue }  // digital silence

            // d'(τ) with running cumulative mean; stop early once a
            // sub-threshold trough has bottomed out.
            var cumulative = 0.0
            var pickedLag = 0
            var bestLag = 0
            var bestValue = Double.infinity
            for lag in 1...maxLag {
                let shifted = samples[(start + lag)..<(start + lag + window)]
                let dot = Double(vDSP.dot(base, shifted))
                let energyLag = prefixSquares[lag + window] - prefixSquares[lag]
                let difference = max(energy0 + energyLag - 2 * dot, 0)
                cumulative += difference
                normalized[lag] = cumulative > 0
                    ? difference * Double(lag) / cumulative
                    : 1
                if lag >= minLag, normalized[lag] < bestValue {
                    bestValue = normalized[lag]
                    bestLag = lag
                }
                // Absolute threshold: take the local minimum of the first
                // trough that dips below it.
                if pickedLag == 0, lag > minLag, normalized[lag - 1] < yinThreshold,
                   normalized[lag] >= normalized[lag - 1] {
                    pickedLag = lag - 1
                    break
                }
            }
            let lag = pickedLag != 0 ? pickedLag : bestLag
            guard lag >= minLag else { continue }

            let refined = parabolicLag(normalized, at: lag, maxLag: maxLag)
            frames[k] = PitchFrame(
                f0: sampleRate / refined,
                confidence: max(0, 1 - normalized[lag]))
        }
        return frames
    }

    /// Sub-sample trough position via parabolic interpolation on d'.
    private static func parabolicLag(
        _ normalized: [Double], at lag: Int, maxLag: Int
    ) -> Double {
        guard lag > 1, lag < maxLag else { return Double(lag) }
        let left = normalized[lag - 1]
        let mid = normalized[lag]
        let right = normalized[lag + 1]
        let denominator = left - 2 * mid + right
        guard abs(denominator) > 1e-12 else { return Double(lag) }
        let offset = 0.5 * (left - right) / denominator
        return Double(lag) + min(max(offset, -1), 1)
    }
}
