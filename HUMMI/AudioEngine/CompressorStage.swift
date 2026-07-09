//
//  CompressorStage.swift
//  HUMMI
//

import Accelerate
import AVFoundation
import AudioToolbox

/// Compression via Apple's DynamicsProcessor audio unit — an A/B
/// alternate to the multiband + glue pair, off by default. Threshold
/// -18 dB, ~3:1, attack 5 ms, release 100 ms, with makeup gain computed
/// afterward so the stage's integrated RMS matches its input.
///
/// The unit has no ratio parameter; its curve is shaped by HeadRoom.
/// headRoomDB below is calibrated so the measured static curve's slope
/// above threshold is 1/3 (see the harness calibration sweep).
nonisolated final class CompressorStage: BufferStage {
    let name = "Compressor (Apple DP)"
    var isEnabled = false

    /// Calibrated for compressorRatio 3:1 at threshold -18 dB: measured
    /// static-curve slope above threshold is 0.329 at HeadRoom 7 (the
    /// unit is soft-knee; this is the average over threshold..0 dBFS).
    static let headRoomDB: Double = 7
    /// Makeup never boosts more than this (protects near-silent takes).
    static let makeupCap: Double = 4  // +12 dB

    private let parameters: PresetParameters

    init(parameters: PresetParameters) {
        self.parameters = parameters
    }

    func process(_ samples: [Float]) throws -> [Float] {
        let compressed = try AudioUnitRenderer.render(samples, through: makeNode())
        let rmsIn = MultibandCompressorStage.rms(samples)
        let rmsOut = MultibandCompressorStage.rms(compressed)
        guard rmsIn > 1e-6, rmsOut > 1e-9 else { return compressed }
        let makeup = Float(min(rmsIn / rmsOut, Self.makeupCap))
        return vDSP.multiply(makeup, compressed)
    }

    private func makeNode() -> AVAudioUnit {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        let effect = AVAudioUnitEffect(audioComponentDescription: description)
        let unit = effect.audioUnit

        func set(_ parameter: AudioUnitParameterID, _ value: Double) {
            AudioUnitSetParameter(
                unit, parameter, kAudioUnitScope_Global, 0,
                AudioUnitParameterValue(value), 0)
        }
        set(kDynamicsProcessorParam_Threshold, parameters.compressorThresholdDB)
        set(kDynamicsProcessorParam_HeadRoom, Self.headRoomDB)
        set(kDynamicsProcessorParam_AttackTime, parameters.compressorAttackMS / 1000)
        set(kDynamicsProcessorParam_ReleaseTime, parameters.compressorReleaseMS / 1000)
        return effect
    }
}
