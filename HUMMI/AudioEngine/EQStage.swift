//
//  EQStage.swift
//  HUMMI
//

import Foundation

/// Tone shaping early in the chain: an optional low-shelf "warmth" boost,
/// then surgical cuts of mud around 300 Hz and boxiness around 500 Hz.
/// RBJ sections identical to the spike's pedalboard filters.
nonisolated final class EQStage: BufferStage {
    let name = "EQ (warmth + mud/box cut)"
    var isEnabled = true
    private let parameters: PresetParameters

    init(parameters: PresetParameters) {
        self.parameters = parameters
    }

    func process(_ samples: [Float]) throws -> [Float] {
        var output = samples
        if parameters.warmthGainDB != 0 {
            output = Biquad.lowShelf(
                frequency: parameters.warmthFrequency,
                gainDB: parameters.warmthGainDB).apply(output)
        }
        let mud = Biquad.peak(
            frequency: parameters.mudFrequency,
            gainDB: parameters.mudGainDB, q: parameters.mudQ)
        let box = Biquad.peak(
            frequency: parameters.boxFrequency,
            gainDB: parameters.boxGainDB, q: parameters.boxQ)
        return box.apply(mud.apply(output))
    }
}
