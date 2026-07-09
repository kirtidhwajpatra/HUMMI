//
//  LoudnessNormalizeTests.swift
//  HUMMITests
//

import Foundation
import Testing
@testable import HUMMI

struct LoudnessNormalizeTests {
    private func sine(_ amplitude: Float, seconds: Double) -> [Float] {
        (0..<Int(seconds * 48_000)).map {
            amplitude * Float(sin(2 * Double.pi * 440 * Double($0) / 48_000))
        }
    }

    @Test func loudnessOfSteadyToneIsMeanSquare() {
        // amp 0.1 sine: mean square 0.005 -> 10·log10 = -23.01 dB
        let loudness = LoudnessNormalizeStage.gatedLoudnessDB(sine(0.1, seconds: 2))
        #expect(loudness != nil)
        if let loudness {
            #expect(abs(loudness - -23.0103) < 0.05)
        }
    }

    @Test func gatingIgnoresSilence() {
        // Half tone, half silence: absolute gate drops the silent blocks,
        // so integrated loudness stays the tone's, not 3 dB lower.
        var clip = sine(0.1, seconds: 2)
        clip.append(contentsOf: [Float](repeating: 0, count: 96_000))
        let loudness = LoudnessNormalizeStage.gatedLoudnessDB(clip)
        #expect(loudness != nil)
        if let loudness {
            // Blocks straddling the tone/silence edge dilute the mean by
            // ~0.35 dB; without gating it would drop a full 3 dB.
            #expect(abs(loudness - -23.0103) < 0.5)
        }
    }

    @Test func silenceReturnsNil() {
        let silent = [Float](repeating: 0, count: 96_000)
        #expect(LoudnessNormalizeStage.gatedLoudnessDB(silent) == nil)
    }

    @Test func gainReachesTargetWhenPeakAllows() {
        // -23 dB loudness, peak 0.1: wanted +9 dB (×2.818), peak would
        // become 0.28 — far under the -1 dBFS ceiling, so wanted wins.
        let gain = LoudnessNormalizeStage.gain(
            loudnessDB: -23, targetDB: -14, peak: 0.1, peakCeilingDB: -1)
        #expect(abs(gain - pow(10, 9.0 / 20.0)) < 1e-9)
    }

    @Test func gainClampsAtPeakCeiling() {
        // Peak 0.9: ceiling allows only 0.891/0.9 even though the
        // loudness target wants ×2.8.
        let gain = LoudnessNormalizeStage.gain(
            loudnessDB: -23, targetDB: -14, peak: 0.9, peakCeilingDB: -1)
        #expect(abs(gain - pow(10, -1.0 / 20.0) / 0.9) < 1e-9)
    }

    @Test func loudClipIsAttenuatedToTarget() {
        // -8 dB loudness: gain is -6 dB regardless of peak.
        let gain = LoudnessNormalizeStage.gain(
            loudnessDB: -8, targetDB: -14, peak: 0.5, peakCeilingDB: -1)
        #expect(abs(gain - pow(10, -6.0 / 20.0)) < 1e-9)
    }

    @Test func stageNormalizesAQuietTone() throws {
        // amp 0.02 tone (-37 dB): wanted +23 dB, peak stays under
        // ceiling after ×~14 (0.28), so output lands on target.
        let stage = LoudnessNormalizeStage(parameters: .default)
        let out = try stage.process(sine(0.02, seconds: 2))
        let loudness = LoudnessNormalizeStage.gatedLoudnessDB(out)
        #expect(loudness != nil)
        if let loudness {
            #expect(abs(loudness - -14) < 0.1)
        }
    }
}
