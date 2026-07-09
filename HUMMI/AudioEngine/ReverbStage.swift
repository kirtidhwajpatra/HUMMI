//
//  ReverbStage.swift
//  HUMMI
//

import AVFoundation

/// Room ambience via Apple's algorithmic reverb — an A/B alternate to
/// the convolution reverb, off by default. Medium-room factory preset,
/// 12% wet.
nonisolated final class ReverbStage: BufferStage {
    let name = "Reverb (Apple room)"
    var isEnabled = false

    private let wetDryPercent: Double

    init(parameters: PresetParameters) {
        self.wetDryPercent = parameters.roomReverbWetDryPercent
    }

    func process(_ samples: [Float]) throws -> [Float] {
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = Float(wetDryPercent)
        // The reverb AU rejects mono buses; run stereo and downmix.
        return try AudioUnitRenderer.render(samples, through: reverb, channels: 2)
    }
}
