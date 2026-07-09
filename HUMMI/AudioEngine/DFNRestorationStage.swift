//
//  DFNRestorationStage.swift
//  HUMMI
//

import Foundation

/// Stage A: DeepFilterNet3 noise suppression with the spike's adaptive
/// floor (restore.py dfn_enhance + dfn_adaptive_floor). One full-
/// suppression model pass — with a 1 s reflected pre-roll so the cold
/// recurrent state doesn't gate the first phrase — then a per-clip
/// blend of original and enhanced sets the residual noise ~45 dB below
/// the voice, with a voiced rescue where the model over-cut soft
/// breathy singing.
nonisolated final class DFNRestorationStage: BufferStage {
    let name = "DFN3 restore (adaptive)"
    /// Off by default: MLEnhanceStage is the primary ML front-end. This
    /// is the adaptive-floor alternate, toggleable for A/B.
    var isEnabled = false

    private let targetFloorDB: Double
    private let voicedCapDB: Double

    init(parameters: PresetParameters) {
        self.targetFloorDB = parameters.dfnTargetFloorDB
        self.voicedCapDB = parameters.dfnVoicedCapDB
    }

    func process(_ samples: [Float]) throws -> [Float] {
        guard !samples.isEmpty else { return samples }

        let warmup = min(Int(DFNContract.sampleRate), samples.count)
        var padded = Array(samples[0..<warmup].reversed())
        padded.append(contentsOf: samples)

        let enhancer = try DFNEnhancer()
        let enhanced = Array(try enhancer.enhance(padded)[warmup...])

        let voiced = VoicedDetector.mask(samples)
        let weights = AdaptiveFloor.weights(
            original: samples, enhanced: enhanced, voicedMask: voiced,
            targetFloorDB: targetFloorDB, voicedCapDB: voicedCapDB)

        var output = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let w = weights[i]
            output[i] = w * samples[i] + (1 - w) * enhanced[i]
        }
        return output
    }
}
