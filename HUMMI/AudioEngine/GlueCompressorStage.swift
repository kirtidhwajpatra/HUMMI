//
//  GlueCompressorStage.swift
//  HUMMI
//

import Foundation

/// Final gentle 2:1 compression that glues the chain together.
/// Port of the polish.py glue Pedalboard (threshold -14 dB, ratio 2,
/// attack 30 ms, release 200 ms).
nonisolated final class GlueCompressorStage: BufferStage {
    let name = "Glue compressor"
    var isEnabled = true

    private let compressor: PeakCompressor

    init(parameters: PresetParameters) {
        self.compressor = PeakCompressor(
            thresholdDB: parameters.glueThresholdDB,
            ratio: parameters.glueRatio,
            attackMS: parameters.glueAttackMS,
            releaseMS: parameters.glueReleaseMS)
    }

    func process(_ samples: [Float]) throws -> [Float] {
        compressor.process(samples)
    }
}
