//
//  PresenceAirStage.swift
//  HUMMI
//

import Foundation

/// Late-chain lift: presence bell at 3 kHz and an air shelf at 10 kHz.
/// Runs after compression/saturation so the top end stays open. RBJ
/// sections identical to the spike's pedalboard presence_air board.
nonisolated final class PresenceAirStage: BufferStage {
    let name = "Presence + air"
    var isEnabled = true
    private let parameters: PresetParameters

    init(parameters: PresetParameters) {
        self.parameters = parameters
    }

    func process(_ samples: [Float]) throws -> [Float] {
        let presence = Biquad.peak(
            frequency: parameters.presenceFrequency,
            gainDB: parameters.presenceGainDB, q: parameters.presenceQ)
        let air = Biquad.highShelf(
            frequency: parameters.airFrequency, gainDB: parameters.airGainDB)
        return air.apply(presence.apply(samples))
    }
}
