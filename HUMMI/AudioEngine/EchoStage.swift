//
//  EchoStage.swift
//  HUMMI
//
//  Feedback-delay echo for the character presets (Canyon, Stadium).
//  The dry vocal stays at full level; a regenerating delayed copy is
//  mixed on top, truncated to the clip's length. Runs before reverb so
//  the repeats sit inside the same room.
//

import Foundation

nonisolated final class EchoStage: BufferStage {
    let name: String
    var isEnabled = true

    private let delaySamples: Int
    private let feedback: Float
    private let wet: Float

    init(parameters: PresetParameters) {
        self.delaySamples = Int(parameters.echoDelayMS * DFNContract.sampleRate / 1000)
        self.feedback = Float(parameters.echoFeedback)
        self.wet = Float(parameters.echoWet)
        self.name = "Echo \(Int(parameters.echoDelayMS)) ms"
    }

    func process(_ samples: [Float]) throws -> [Float] {
        Self.echo(samples, delaySamples: delaySamples, feedback: feedback, wet: wet)
    }

    // MARK: - Pure math (unit-tested)

    /// out[n] = x[n] + wet · d[n], where d[n] = x[n−D] + fb · d[n−D].
    /// Feedback is clamped below 1 so the tail always decays.
    static func echo(_ x: [Float], delaySamples: Int, feedback: Float, wet: Float) -> [Float] {
        guard delaySamples > 0, wet > 0, x.count > delaySamples else { return x }
        let fb = min(max(feedback, 0), 0.9)
        let mix = min(max(wet, 0), 1)

        var delayed = [Float](repeating: 0, count: x.count)
        for n in delaySamples..<x.count {
            delayed[n] = x[n - delaySamples] + fb * delayed[n - delaySamples]
        }
        var out = x
        for n in 0..<out.count {
            out[n] += mix * delayed[n]
        }
        return out
    }
}
