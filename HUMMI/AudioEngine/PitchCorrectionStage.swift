//
//  PitchCorrectionStage.swift
//  HUMMI
//

import Accelerate
import AVFoundation

/// Gentle auto-tune: YIN pitch track → key estimate (or manual
/// override) → each voiced segment shifted toward its nearest scale
/// note by `pitchCorrectionStrength` (0…1). Only the segment's median
/// (center) pitch is corrected, with one constant shift per segment —
/// vibrato and slides ride along untouched, matching the spike's
/// autotune.py lesson that per-frame targets flip mid-vibrato. Segments
/// more than 0.7 st from any scale note are deliberate blue/passing
/// notes and are left alone. Shifting uses AVAudioUnitTimePitch with
/// measured latency compensation and crossfaded splices.
nonisolated final class PitchCorrectionStage: BufferStage {
    let name = "Pitch correction"
    var isEnabled = true

    static let confidenceGate = 0.75
    static let maxDeviationSemitones = 0.7
    static let minCorrectionSemitones = 0.03   // < 3 cents: already in tune
    static let minSegmentFrames = 10           // 0.1 s of steady pitch
    static let crossfadeSamples = 960          // 20 ms splice fades
    static let contextSamples = 12_000         // 0.25 s shifter warm-up

    private let strength: Double
    private let keyOverride: MusicalKey?

    init(parameters: PresetParameters) {
        self.strength = parameters.pitchCorrectionStrength
        self.keyOverride = parameters.keyOverride
    }

    func process(_ samples: [Float]) throws -> [Float] {
        guard strength > 0 else { return samples }
        let frames = PitchTracker.track(samples)
        guard let key = keyOverride ?? KeyEstimator.estimate(from: frames) else {
            return samples  // not enough confident pitch to name a key
        }

        var output = samples
        for segment in Self.segments(in: frames) {
            guard let cents = Self.correctionCents(
                for: Array(frames[segment]), key: key, strength: strength)
            else { continue }
            let start = segment.lowerBound * PitchTracker.hop
            let end = min(segment.upperBound * PitchTracker.hop + 1_024, samples.count)
            let shifted = try Self.shiftedSegment(samples, range: start..<end, cents: cents)
            Self.splice(shifted, into: &output, at: start)
        }
        return output
    }

    // MARK: - Pure math (unit-tested)

    /// Contiguous runs of confident, pitched frames, at least
    /// minSegmentFrames long.
    static func segments(in frames: [PitchFrame]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var runStart: Int?
        for i in 0...frames.count {
            let voiced = i < frames.count && frames[i].f0 != nil
                && frames[i].confidence >= confidenceGate
            if voiced, runStart == nil {
                runStart = i
            } else if !voiced, let start = runStart {
                if i - start >= minSegmentFrames {
                    result.append(start..<i)
                }
                runStart = nil
            }
        }
        return result
    }

    /// Shift in cents for one segment: strength × (nearest scale note −
    /// median pitch). Nil when the segment is already in tune or too far
    /// off-key to be a mistake.
    static func correctionCents(
        for frames: [PitchFrame], key: MusicalKey, strength: Double
    ) -> Double? {
        let semitones = frames.compactMap(\.semitone)
        guard !semitones.isEmpty else { return nil }
        let center = DeEsserStage.median(semitones)
        let deviation = key.nearestScaleSemitone(to: center) - center
        guard abs(deviation) >= minCorrectionSemitones,
              abs(deviation) <= maxDeviationSemitones else { return nil }
        return strength * deviation * 100.0
    }

    // MARK: - Shifting

    private static func makeNode(cents: Double) -> AVAudioUnitTimePitch {
        let node = AVAudioUnitTimePitch()
        node.pitch = Float(cents)
        node.rate = 1
        return node
    }

    /// Renders `range` through the pitch shifter with real audio as
    /// warm-up context (padded with zeros if near the start of the file)
    /// and linear group-delay corrected, returning `range.count` samples.
    static func shiftedSegment(
        _ samples: [Float], range: Range<Int>, cents: Double
    ) throws -> [Float] {
        let latency = Int((cents * 0.3).rounded())
        let pre = contextSamples
        var input: [Float] = []
        if range.lowerBound < pre {
            let padCount = pre - range.lowerBound
            input.append(contentsOf: [Float](repeating: 0, count: padCount))
            input.append(contentsOf: samples[0..<range.upperBound])
        } else {
            input.append(contentsOf: samples[(range.lowerBound - pre)..<range.upperBound])
        }
        let padCount = 4_800 + abs(latency)
        input.append(contentsOf: [Float](repeating: 0, count: padCount))

        let rendered = try AudioUnitRenderer.render(input, through: makeNode(cents: cents))
        let offset = pre + latency
        guard offset >= 0, rendered.count >= offset + range.count else {
            throw DFNError.audioFile("pitch shifter returned a short render")
        }
        return Array(rendered[offset..<offset + range.count])
    }

    /// Replaces output[start...] with the shifted segment, raised-cosine
    /// crossfaded at both ends to avoid clicks.
    static func splice(_ shifted: [Float], into output: inout [Float], at start: Int) {
        let fade = min(crossfadeSamples, shifted.count / 4)
        for i in 0..<shifted.count {
            var weight: Float = 1
            if i < fade {
                weight = Float(0.5 * (1 - cos(.pi * Double(i) / Double(fade))))
            } else if i >= shifted.count - fade {
                let j = shifted.count - 1 - i
                weight = Float(0.5 * (1 - cos(.pi * Double(j) / Double(fade))))
            }
            output[start + i] = weight * shifted[i] + (1 - weight) * output[start + i]
        }
    }
}
