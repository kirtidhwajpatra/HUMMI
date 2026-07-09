//
//  PitchCorrectionTests.swift
//  HUMMITests
//

import Foundation
import Testing
@testable import HUMMI

struct PitchCorrectionTests {
    private func sine(_ hz: Double, seconds: Double, amplitude: Float = 0.3) -> [Float] {
        (0..<Int(seconds * 48_000)).map {
            amplitude * Float(sin(2 * Double.pi * hz * Double($0) / 48_000))
        }
    }

    /// Median tracked frequency over the middle of a clip, in Hz.
    private func measuredHz(_ samples: [Float]) -> Double {
        let quarter = samples.count / 4
        let middle = Array(samples[quarter..<(3 * quarter)])
        let f0s = PitchTracker.track(middle)
            .filter { $0.confidence > 0.8 }
            .compactMap(\.f0)
        return f0s.isEmpty ? 0 : DeEsserStage.median(f0s)
    }

    private func cents(_ a: Double, from b: Double) -> Double {
        1_200 * log2(a / b)
    }

    private var cMajor: PresetParameters {
        var p = PresetParameters()
        p.keyOverride = MusicalKey(root: 0, minor: false)
        p.pitchCorrectionStrength = 1.0
        return p
    }

    // MARK: - Tracker and key

    @Test func yinTracksASineWithinHalfAHertz() {
        let track = PitchTracker.track(sine(220, seconds: 1))
        let confident = track.filter { $0.confidence > 0.9 }.compactMap(\.f0)
        #expect(confident.count > 50)
        #expect(abs(DeEsserStage.median(confident) - 220) < 0.5)
    }

    @Test func keyEstimatorRecoversCMajorScale() {
        // C major scale, tonic and dominant emphasized.
        let midiAndSeconds: [(Int, Double)] = [
            (60, 0.6), (62, 0.3), (64, 0.45), (65, 0.3),
            (67, 0.6), (69, 0.3), (71, 0.3), (72, 0.45),
        ]
        var clip: [Float] = []
        for (midi, seconds) in midiAndSeconds {
            clip.append(contentsOf: sine(440 * pow(2, Double(midi - 69) / 12), seconds: seconds))
        }
        let key = KeyEstimator.estimate(from: PitchTracker.track(clip))
        #expect(key != nil)
        // C major and A minor share pitch classes; correction only uses
        // the scale set, so that's what must match.
        #expect(key?.scalePitchClasses == MusicalKey(root: 0, minor: false).scalePitchClasses)
    }

    @Test func nearestScaleNoteMath() {
        let key = MusicalKey(root: 0, minor: false)
        #expect(key.nearestScaleSemitone(to: 69.3) == 69)   // A4+30c -> A4
        #expect(key.nearestScaleSemitone(to: 65.6) == 65)   // F#-ish -> F (F# not in C)
        #expect(key.nearestScaleSemitone(to: 71.8) == 72)   // B+80c -> C5
        #expect(MusicalKey(root: 9, minor: true).scalePitchClasses
            == MusicalKey(root: 0, minor: false).scalePitchClasses)  // A minor == C major set
    }

    // MARK: - Correction acceptance (10-cent criterion)

    @Test func offKeySineCorrectedWithinTenCents() throws {
        // A4 + 30 cents, full strength: must land within 10 cents of A4.
        let out = try PitchCorrectionStage(parameters: cMajor)
            .process(sine(440 * pow(2, 30.0 / 1_200), seconds: 2))
        #expect(abs(cents(measuredHz(out), from: 440)) < 10)
    }

    @Test func strengthScalesTheCorrection() throws {
        // Same +30c tone at strength 0.5: expect half the pull, +15c ± 5.
        var params = cMajor
        params.pitchCorrectionStrength = 0.5
        let out = try PitchCorrectionStage(parameters: params)
            .process(sine(440 * pow(2, 30.0 / 1_200), seconds: 2))
        #expect(abs(cents(measuredHz(out), from: 440) - 15) < 5)
    }

    @Test func inTuneSineUntouched() throws {
        let input = sine(440, seconds: 1)
        let out = try PitchCorrectionStage(parameters: cMajor).process(input)
        #expect(out == input)  // deviation < 3 cents: no render at all
    }

    @Test func farOffKeyNoteLeftAlone() throws {
        // F#4 sits a full semitone from F and G in C major: a deliberate
        // chromatic note, not a mistake — must pass through untouched.
        let input = sine(369.994, seconds: 1)
        let out = try PitchCorrectionStage(parameters: cMajor).process(input)
        #expect(out == input)
    }

    // MARK: - Modulation preserved

    @Test func vibratoDepthSurvivesCorrection() throws {
        // +30c-centered tone with ±20c 5.5 Hz vibrato: center corrected,
        // vibrato depth preserved.
        let center = 440 * pow(2, 30.0 / 1_200)
        var phase = 0.0
        let clip: [Float] = (0..<96_000).map { i in
            let t = Double(i) / 48_000
            let hz = center * pow(2, 0.2 / 12 * sin(2 * .pi * 5.5 * t))
            phase += 2 * .pi * hz / 48_000
            return 0.3 * Float(sin(phase))
        }
        let out = try PitchCorrectionStage(parameters: cMajor).process(clip)
        let track = PitchTracker.track(out).filter { $0.confidence > 0.8 }.compactMap(\.f0)
        let centsTrack = track.map { cents($0, from: 440) }.sorted()
        let median = centsTrack[centsTrack.count / 2]
        let p5 = centsTrack[centsTrack.count / 20]
        let p95 = centsTrack[centsTrack.count - 1 - centsTrack.count / 20]
        #expect(abs(median) < 10)                       // center on A4
        let depth = (p95 - p5) / 2
        #expect(depth > 12 && depth < 28)               // ~±20c wobble kept
    }

    @Test func slideShapePreserved() throws {
        // Slow glide 445 -> 455 Hz (center ~+39c off A4): the center is
        // pulled down but the glide's span in cents must survive.
        var phase = 0.0
        let clip: [Float] = (0..<96_000).map { i in
            let t = Double(i) / 96_000
            let hz = 445 + 10 * t
            phase += 2 * .pi * hz / 48_000
            return 0.3 * Float(sin(phase))
        }
        let inputSpan = cents(455, from: 445)  // ~38.6c
        let out = try PitchCorrectionStage(parameters: cMajor).process(clip)
        let track = PitchTracker.track(out).filter { $0.confidence > 0.8 }.compactMap(\.f0)
        #expect(track.count > 100)
        let early = DeEsserStage.median(Array(track.prefix(20)))
        let late = DeEsserStage.median(Array(track.suffix(20)))
        #expect(abs(cents(late, from: early) - inputSpan) < 8)
    }

    // MARK: - Alignment and presets

    @Test func shifterOutputIsTimeAligned() throws {
        var seed: UInt64 = 42
        let noise = (0..<48_000).map { _ -> Float in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return (Float(seed >> 40) / Float(1 << 24) - 0.5) * 0.5
        }
        let range = 12_000..<36_000
        let shifted = try PitchCorrectionStage.shiftedSegment(noise, range: range, cents: 1)
        // Cross-correlate against the dry segment: peak must sit at lag 0
        // within ±96 samples (2 ms).
        let dry = Array(noise[range])
        var bestLag = 0
        var bestDot = -Float.infinity
        for lag in -960...960 {
            var dot: Float = 0
            for i in max(0, -lag)..<min(dry.count, dry.count - lag) {
                dot += dry[i] * shifted[i + lag]
            }
            if dot > bestDot {
                bestDot = dot
                bestLag = lag
            }
        }
        #expect(abs(bestLag) <= 96)
    }

    @Test func strengthPresetsExist() {
        #expect(PresetParameters.natural.pitchCorrectionStrength == 0.4)
        #expect(PresetParameters.tuned.pitchCorrectionStrength == 0.7)
        #expect(PresetParameters.hard.pitchCorrectionStrength == 1.0)
        #expect(PresetParameters.default.pitchCorrectionStrength == 0.55)
    }
}
