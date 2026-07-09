//
//  AdaptiveFloor.swift
//  HUMMI
//

import Foundation

/// The per-clip suppression math of restore.py dfn_adaptive_floor():
/// estimate the noise floor, suppress it to ~targetFloorDB below the
/// voice and no further (full suppression gates breaths and onsets),
/// and rescue pitched passages the model over-cut. Produces a
/// per-sample blend weight w: output = w·original + (1−w)·enhanced.
nonisolated enum AdaptiveFloor {
    static let envelopeWindow = 2_400       // 50 ms @ 48 kHz
    static let minLimDB = 6.0
    static let maxLimDB = 40.0
    static let sustainedSeconds = 0.4
    static let dezipperWindow = 4_800       // 100 ms

    static func weights(
        original: [Float], enhanced: [Float], voicedMask: [Float],
        targetFloorDB: Double, voicedCapDB: Double
    ) -> [Float] {
        let n = min(original.count, enhanced.count)
        let envOriginal = envelopeDB(original, size: envelopeWindow)
        let envEnhanced = envelopeDB(enhanced, size: envelopeWindow)

        // Voice level: median of the enhanced envelope's top 40 dB.
        let peak = envEnhanced.max() ?? -120
        let loud = envEnhanced.filter { $0 > peak - 40 }
        let voiceLevel = loud.isEmpty ? -120 : median(loud)

        // Noise floor: the original's level where the model hears no voice.
        let quiet = (0..<n).compactMap {
            envEnhanced[$0] < voiceLevel - 35 ? envOriginal[$0] : nil
        }
        let noiseFloor = quiet.isEmpty ? -120 : median(quiet)

        let lim = min(max(
            noiseFloor - (voiceLevel - targetFloorDB), minLimDB), maxLimDB)
        let wFloor = Float(pow(10.0, -lim / 20.0))

        // Voice-gated rescue: pitched + over-cut by more than the cap,
        // sustained, then de-zippered.
        var rescue = [Float](repeating: 0, count: n)
        for i in 0..<n where voicedMask[i] > 0.5
            && envOriginal[i] - envEnhanced[i] > voicedCapDB {
            rescue[i] = 1
        }
        rescue = keepSustained(rescue, minRun: Int(
            sustainedSeconds * DFNContract.sampleRate))
        rescue = movingAverageReflect(rescue, size: dezipperWindow)

        let wRescue = Float(pow(10.0, -voicedCapDB / 20.0))
        return (0..<n).map { max(wFloor, wRescue * rescue[$0]) }
    }

    /// 10·log10(50 ms moving mean of x² + 1e-12), matching
    /// scipy uniform_filter1d(x², size, mode="reflect").
    static func envelopeDB(_ x: [Float], size: Int) -> [Double] {
        let meanSquares = movingMeanOfSquares(x, size: size)
        return meanSquares.map { 10 * log10($0 + 1e-12) }
    }

    static func movingMeanOfSquares(_ x: [Float], size: Int) -> [Double] {
        let n = x.count
        guard n > 0 else { return [] }
        // scipy centering: window offsets [-size/2, size - size/2 - 1].
        let left = size / 2
        let right = size - left - 1

        func squared(_ i: Int) -> Double {
            var index = i
            while index < 0 || index >= n {  // mode="reflect": d c b a | a b c d
                if index < 0 { index = -1 - index }
                if index >= n { index = 2 * n - 1 - index }
            }
            let v = Double(x[index])
            return v * v
        }

        var sum = 0.0
        for offset in -left...right {
            sum += squared(offset)
        }
        var out = [Double](repeating: 0, count: n)
        out[0] = sum / Double(size)
        for i in 1..<n {
            sum += squared(i + right) - squared(i - 1 - left)
            out[i] = sum / Double(size)
        }
        return out
    }

    /// Zero out mask runs shorter than minRun samples — singing phrases
    /// are sustained; short pitched blips in noise are false positives.
    static func keepSustained(_ mask: [Float], minRun: Int) -> [Float] {
        var out = [Float](repeating: 0, count: mask.count)
        var runStart: Int?
        for i in 0...mask.count {
            let on = i < mask.count && mask[i] > 0.5
            if on, runStart == nil {
                runStart = i
            } else if !on, let start = runStart {
                if i - start >= minRun {
                    for j in start..<i {
                        out[j] = 1
                    }
                }
                runStart = nil
            }
        }
        return out
    }

    /// uniform_filter1d(mask, size, mode="reflect") — same centering as
    /// movingMeanOfSquares, on the raw values.
    static func movingAverageReflect(_ x: [Float], size: Int) -> [Float] {
        let n = x.count
        guard n > 0 else { return [] }
        let left = size / 2
        let right = size - left - 1

        func value(_ i: Int) -> Double {
            var index = i
            while index < 0 || index >= n {
                if index < 0 { index = -1 - index }
                if index >= n { index = 2 * n - 1 - index }
            }
            return Double(x[index])
        }

        var sum = 0.0
        for offset in -left...right {
            sum += value(offset)
        }
        var out = [Float](repeating: 0, count: n)
        out[0] = Float(sum / Double(size))
        for i in 1..<n {
            sum += value(i + right) - value(i - 1 - left)
            out[i] = Float(sum / Double(size))
        }
        return out
    }

    /// numpy-style median (mean of the two middle values for even counts).
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}
