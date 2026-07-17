//
//  VoiceShapeTests.swift
//  HUMMITests
//
//  Pure-math tests for the voice-shape stage: varispeed resampling and
//  the rate/length bookkeeping. The AVAudioUnitTimePitch path is
//  graph behavior, tested manually on device per the architecture rules.
//

import Foundation
import Testing
@testable import HUMMI

struct VoiceShapeTests {
    @Test func neutralRateIsPassthrough() {
        let x: [Float] = [0.1, -0.4, 0.7, 0.2]
        #expect(VoiceShapeStage.resample(x, rate: 1.0) == x)
    }

    @Test func doubleSpeedHalvesLength() {
        let x = [Float](repeating: 0.5, count: 48_000)
        let out = VoiceShapeStage.resample(x, rate: 2.0)
        #expect(out.count == 24_000)
    }

    @Test func halfSpeedDoublesLength() {
        let x = [Float](repeating: 0.5, count: 48_000)
        let out = VoiceShapeStage.resample(x, rate: 0.5)
        #expect(out.count == 96_000)
    }

    @Test func linearRampSurvivesResampling() {
        // Linear interpolation reproduces a linear ramp exactly at any rate.
        let x = (0..<1_000).map { Float($0) / 1_000 }
        let out = VoiceShapeStage.resample(x, rate: 1.25)
        let ceiling: Float = x.last ?? 1
        for (i, sample) in out.enumerated() {
            let position: Float = Float(i) * 1.25 / 1_000
            let expected: Float = min(position, ceiling)
            #expect(abs(sample - expected) < 1e-5)
        }
    }

    @Test func resamplingDoublesFrequency() {
        // A 100 Hz sine played at rate 2 becomes 200 Hz: the resampled
        // signal should match a directly synthesized 200 Hz tone.
        let sr = 48_000.0
        let x = (0..<48_000).map { Float(sin(2 * Double.pi * 100 * Double($0) / sr)) }
        let out = VoiceShapeStage.resample(x, rate: 2.0)
        for i in stride(from: 0, to: out.count - 1, by: 997) {
            let expected = Float(sin(2 * Double.pi * 200 * Double(i) / sr))
            #expect(abs(out[i] - expected) < 1e-3)
        }
    }

    @Test func stretchedCountInvertsRate() {
        #expect(VoiceShapeStage.stretchedCount(48_000, rate: 2.0) == 24_000)
        #expect(VoiceShapeStage.stretchedCount(48_000, rate: 0.5) == 96_000)
        #expect(VoiceShapeStage.stretchedCount(48_000, rate: 1.0) == 48_000)
        #expect(VoiceShapeStage.stretchedCount(10, rate: 100) == 1)   // floor of 1
    }

    @Test func ratesAreClamped() {
        #expect(VoiceShapeStage.clampRate(0.1) == 0.5)
        #expect(VoiceShapeStage.clampRate(5.0) == 2.0)
        #expect(VoiceShapeStage.clampRate(1.3) == 1.3)
    }

    @Test func neutralStageIsPassthrough() throws {
        // All-neutral parameters must not touch the samples (and must
        // not spin up an audio engine to do so).
        let params = PresetParameters.default
        let x: [Float] = (0..<4_800).map { Float(sin(Double($0) / 50)) }
        let out = try VoiceShapeStage(parameters: params).process(x)
        #expect(out == x)
    }
}
