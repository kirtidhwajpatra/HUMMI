//
//  PeakCompressor.swift
//  HUMMI
//

import Foundation

/// Feed-forward peak compressor matching pedalboard/JUCE dsp::Compressor:
/// one-pole peak envelope with cte = exp(-2π / (fs · t)) ballistics
/// (verified empirically against pedalboard), hard knee, gain =
/// (env/threshold)^(1/ratio - 1) above threshold. Used by the multiband
/// and glue stages.
nonisolated struct PeakCompressor {
    var thresholdDB: Double
    var ratio: Double
    var attackMS: Double
    var releaseMS: Double
    var sampleRate: Double = DFNContract.sampleRate

    func process(_ samples: [Float]) -> [Float] {
        let threshold = pow(10.0, thresholdDB / 20.0)
        let exponent = 1.0 / ratio - 1.0
        let cteAttack = exp(-2.0 * .pi / (sampleRate * attackMS / 1000.0))
        let cteRelease = exp(-2.0 * .pi / (sampleRate * releaseMS / 1000.0))

        var envelope = 0.0
        var output = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let input = Double(abs(samples[i]))
            let cte = input > envelope ? cteAttack : cteRelease
            envelope = input + cte * (envelope - input)
            let gain = envelope < threshold
                ? 1.0
                : pow(envelope / threshold, exponent)
            output[i] = Float(gain * Double(samples[i]))
        }
        return output
    }
}
