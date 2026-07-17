//
//  VoiceShapeStage.swift
//  HUMMI
//
//  The user-facing voice controls: Speed (varispeed — duration and pitch
//  change together, like tape), Tempo (time-stretch — duration changes,
//  pitch preserved) and Pitch (deeper ↔ lighter, duration preserved).
//  Runs last in the chain so the polish stages see the untouched take.
//  Tempo/pitch use AVAudioUnitTimePitch; varispeed is our own resampler.
//

import AVFoundation

nonisolated final class VoiceShapeStage: BufferStage {
    let name = "Voice shape (speed/tempo/pitch)"
    var isEnabled = true

    /// UI slider bounds; parameters are clamped to these.
    static let rateRange = 0.5...2.0
    static let pitchRange = -12.0...12.0

    private let speed: Double
    private let tempo: Double
    private let pitchSemitones: Double

    init(parameters: PresetParameters) {
        self.speed = Self.clampRate(parameters.voiceSpeed)
        self.tempo = Self.clampRate(parameters.voiceTempo)
        self.pitchSemitones = min(max(parameters.voicePitchSemitones,
                                      Self.pitchRange.lowerBound),
                                  Self.pitchRange.upperBound)
    }

    func process(_ samples: [Float]) throws -> [Float] {
        var output = samples

        if tempo != 1 || pitchSemitones != 0 {
            let unit = AVAudioUnitTimePitch()
            unit.rate = Float(tempo)
            unit.pitch = Float(pitchSemitones * 100)   // cents
            output = try AudioUnitRenderer.render(
                output, through: unit,
                expectedFrames: Self.stretchedCount(output.count, rate: tempo))
        }

        if speed != 1 {
            output = Self.resample(output, rate: speed)
        }
        return output
    }

    // MARK: - Pure math (unit-tested)

    static func clampRate(_ rate: Double) -> Double {
        min(max(rate, rateRange.lowerBound), rateRange.upperBound)
    }

    /// Output length of a rate change: playing N frames at `rate` yields
    /// N/rate frames.
    static func stretchedCount(_ count: Int, rate: Double) -> Int {
        guard rate > 0 else { return count }
        return max(Int((Double(count) / rate).rounded()), 1)
    }

    /// Varispeed via linear-interpolation resampling: `rate` 2 plays
    /// twice as fast (half the frames, an octave up), 0.5 the reverse.
    static func resample(_ x: [Float], rate: Double) -> [Float] {
        guard rate > 0, rate != 1, x.count > 1 else { return x }
        let outCount = stretchedCount(x.count, rate: rate)
        var out = [Float](repeating: 0, count: outCount)
        let last = x.count - 1
        for i in 0..<outCount {
            let pos = Double(i) * rate
            let j = Int(pos)
            if j >= last {
                out[i] = x[last]
            } else {
                let t = Float(pos - Double(j))
                out[i] = x[j] * (1 - t) + x[j + 1] * t
            }
        }
        return out
    }
}
