//
//  HighPassStage.swift
//  HUMMI
//

import Foundation

/// Removes rumble and plosive thumps below the vocal range: two cascaded
/// first-order 80 Hz high-passes = 12 dB/oct, exactly the polish.py
/// front chain's twin HighpassFilters.
nonisolated final class HighPassStage: BufferStage {
    let name: String
    var isEnabled = true
    private let frequency: Double

    init(parameters: PresetParameters) {
        self.frequency = parameters.highPassFrequency
        self.name = "High-pass \(Int(parameters.highPassFrequency)) Hz"
    }

    func process(_ samples: [Float]) throws -> [Float] {
        let highPass = Biquad.firstOrderHighPass(frequency: frequency)
        return highPass.apply(highPass.apply(samples))
    }
}
