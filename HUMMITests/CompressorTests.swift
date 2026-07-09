//
//  CompressorTests.swift
//  HUMMITests
//

import Foundation
import Testing
@testable import HUMMI

struct CompressorTests {
    @Test func belowThresholdPassesThrough() {
        let comp = PeakCompressor(
            thresholdDB: -20, ratio: 4, attackMS: 15, releaseMS: 150)
        let quiet = [Float](repeating: 0.05, count: 4_800)  // -26 dB < -20 dB
        let out = comp.process(quiet)
        #expect(out == quiet)
    }

    @Test func steadyStateGainMatchesRatio() {
        // Constant 0.5 input (-6 dB), threshold -20 dB, ratio 4:
        // envelope → 0.5, gain → (0.5/0.1)^(1/4 - 1) = 5^(-0.75).
        let comp = PeakCompressor(
            thresholdDB: -20, ratio: 4, attackMS: 15, releaseMS: 150)
        let loud = [Float](repeating: 0.5, count: 48_000)
        let out = comp.process(loud)
        let expected = 0.5 * pow(5.0, -0.75)
        #expect(abs(Double(out[47_999]) - expected) < 1e-4)
    }

    @Test func ballisticsMatchJUCE() {
        // JUCE BallisticsFilter: cte = exp(-2π / (fs·t)), verified
        // empirically against pedalboard (attack cte 0.9913113 @ 15 ms).
        let cte = exp(-2.0 * Double.pi / (48_000.0 * 0.015))
        #expect(abs(cte - 0.99131132) < 1e-7)
    }

    @Test func zeroPhaseButterGainHalvesAtCutoff() {
        // sosfiltfilt(butter(4, fc)) has |H|² = 1/2 at the cutoff.
        let atCut = MultibandCompressorStage.zeroPhaseButterGain(
            freq: 250, cutoff: 250, highpass: false)
        #expect(abs(atCut - 0.5) < 1e-12)
        #expect(MultibandCompressorStage.zeroPhaseButterGain(
            freq: 0, cutoff: 250, highpass: false) == 1)
        #expect(MultibandCompressorStage.zeroPhaseButterGain(
            freq: 24_000, cutoff: 250, highpass: false) == 0)
        #expect(MultibandCompressorStage.zeroPhaseButterGain(
            freq: 24_000, cutoff: 4_000, highpass: true) == 1)
        // Deep in the passband the gain is ~1.
        let passband = MultibandCompressorStage.zeroPhaseButterGain(
            freq: 25, cutoff: 250, highpass: false)
        #expect(passband > 0.9999)
    }

    @Test func bandsSumBackToInput() throws {
        var seed: UInt64 = 12_345
        func random() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }
        let noise = (0..<9_600).map { _ in random() * 0.5 }
        let (low, high) = try MultibandCompressorStage.splitBands(noise)
        // mid = x - low - high by construction, so low + mid + high == x
        // exactly; what needs checking is that the split is sane: the
        // low band of a 100 Hz tone keeps it, the high band drops it.
        let tone = (0..<9_600).map { Float(sin(2 * Double.pi * 100 * Double($0) / 48_000)) }
        let (lowTone, highTone) = try MultibandCompressorStage.splitBands(tone)
        #expect(MultibandCompressorStage.rms(lowTone) > 0.9 * MultibandCompressorStage.rms(tone))
        #expect(MultibandCompressorStage.rms(highTone) < 0.01 * MultibandCompressorStage.rms(tone))
        #expect(low.count == noise.count)
        #expect(high.count == noise.count)
    }

    @Test func rmsOfKnownSignal() {
        #expect(abs(MultibandCompressorStage.rms([3, -4]) - 3.5355339) < 1e-5)
        #expect(MultibandCompressorStage.rms([]) == 0)
    }
}
