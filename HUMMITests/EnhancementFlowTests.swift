//
//  EnhancementFlowTests.swift
//  HUMMITests
//

import Foundation
import Testing
@testable import HUMMI

struct EnhancementFlowTests {
    // MARK: - Warmth low shelf

    @Test func lowShelfBoostsBassLeavesTrebleAtQ() {
        // +6 dB low shelf at 200 Hz: ~+6 dB at DC, ~0 dB well above corner.
        let shelf = Biquad.lowShelf(frequency: 200, gainDB: 6)
        let dcGain = magnitude(shelf, hz: 20)
        let highGain = magnitude(shelf, hz: 8_000)
        #expect(abs(20 * log10(dcGain) - 6) < 0.5)
        #expect(abs(20 * log10(highGain)) < 0.5)
    }

    @Test func lowShelfZeroGainIsUnity() {
        let shelf = Biquad.lowShelf(frequency: 200, gainDB: 0)
        for hz in [50.0, 500, 5_000] {
            #expect(abs(magnitude(shelf, hz: hz) - 1) < 1e-6)
        }
    }

    @Test func eqStageAppliesWarmthOnlyWhenNonZero() throws {
        // With warmthGainDB 0, the stage output equals the no-warmth path.
        let tone = (0..<24_000).map { Float(sin(2 * Double.pi * 100 * Double($0) / 48_000)) * 0.3 }
        var flat = PresetParameters.default
        flat.warmthGainDB = 0
        var warm = PresetParameters.default
        warm.warmthGainDB = 6
        let flatOut = try EQStage(parameters: flat).process(tone)
        let warmOut = try EQStage(parameters: warm).process(tone)
        // The 100 Hz tone should be louder with warmth engaged.
        #expect(rms(warmOut) > rms(flatOut) * 1.3)
    }

    // MARK: - Presets

    @Test func presetParameterMoves() {
        // Studio is the flagship "produced" preset: audibly more polish
        // than Default in tuning, sheen, and saturation.
        let studio = StudioPreset.studio.parameters
        let balanced = StudioPreset.balanced.parameters
        #expect(studio.pitchCorrectionStrength > balanced.pitchCorrectionStrength)
        #expect(studio.presenceGainDB > balanced.presenceGainDB)
        #expect(studio.airGainDB > balanced.airGainDB)
        #expect(studio.saturationBlend > balanced.saturationBlend)

        let warm = StudioPreset.warm.parameters
        #expect(warm.warmthGainDB > studio.warmthGainDB)     // more low EQ
        #expect(warm.reverbWet > studio.reverbWet)           // more reverb
        #expect(warm.pitchCorrectionStrength == 0.4)

        let bright = StudioPreset.bright.parameters
        #expect(bright.airGainDB > studio.airGainDB)         // more air
        #expect(bright.reverbWet < studio.reverbWet)         // tighter reverb
        #expect(bright.pitchCorrectionStrength == 0.7)
    }

    @Test func everyPresetHasDistinctFingerprint() {
        let params = StudioPreset.allCases.map { $0.parameters }
        let fingerprints = params.map {
            "\($0.pitchCorrectionStrength)|\($0.reverbWet)|\($0.airGainDB)|\($0.warmthGainDB)"
        }
        #expect(Set(fingerprints).count == StudioPreset.allCases.count)
    }

    // MARK: - Helpers

    /// |H(e^jω)| of a biquad at frequency `hz`.
    private func magnitude(_ f: Biquad, hz: Double, sampleRate: Double = 48_000) -> Double {
        let w = 2 * Double.pi * hz / sampleRate
        let cos1 = cos(w), cos2 = cos(2 * w)
        let sin1 = sin(w), sin2 = sin(2 * w)
        let numRe = f.b0 + f.b1 * cos1 + f.b2 * cos2
        let numIm = -(f.b1 * sin1 + f.b2 * sin2)
        let denRe = 1 + f.a1 * cos1 + f.a2 * cos2
        let denIm = -(f.a1 * sin1 + f.a2 * sin2)
        let num = (numRe * numRe + numIm * numIm).squareRoot()
        let den = (denRe * denRe + denIm * denIm).squareRoot()
        return num / den
    }

    private func rms(_ samples: [Float]) -> Double {
        var sum = 0.0
        for s in samples { sum += Double(s) * Double(s) }
        return (sum / Double(samples.count)).squareRoot()
    }
}
