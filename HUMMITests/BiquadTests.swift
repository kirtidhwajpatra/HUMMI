//
//  BiquadTests.swift
//  HUMMITests
//

import Testing
@testable import HUMMI

/// Coefficient formulas verified against pedalboard (JUCE) impulse
/// responses extracted on 2026-07-06 — see the spike's filter probe.
struct BiquadTests {
    @Test func peakFilterMatchesPedalboard() {
        // pedalboard PeakFilter(300, -3, q=1.2) @ 48 kHz
        let f = Biquad.peak(frequency: 300, gainDB: -3, q: 1.2)
        #expect(abs(f.b0 - 0.99443022) < 1e-6)
        #expect(abs(f.b1 - -1.96034538) < 1e-6)
        #expect(abs(f.b2 - 0.96742768) < 1e-6)
        #expect(abs(f.a1 - -1.96034538) < 1e-6)
        #expect(abs(f.a2 - 0.96185790) < 1e-6)
    }

    @Test func highShelfMatchesPedalboard() {
        // pedalboard HighShelfFilter(10_000, +3.5) @ 48 kHz
        let f = Biquad.highShelf(frequency: 10_000, gainDB: 3.5)
        #expect(abs(f.b0 - 1.26165125) < 1e-6)
        #expect(abs(f.b1 - -0.53145131) < 1e-6)
        #expect(abs(f.b2 - 0.25626128) < 1e-6)
        #expect(abs(f.a1 - -0.19160932) < 1e-6)
        #expect(abs(f.a2 - 0.17807054) < 1e-6)
    }

    @Test func firstOrderHighPassMatchesPedalboard() {
        // pedalboard HighpassFilter(80) @ 48 kHz: b0 = 1/(1+G),
        // pole = (1-G)/(1+G), G = tan(π·80/48000)
        let f = Biquad.firstOrderHighPass(frequency: 80)
        #expect(abs(f.b0 - 0.99479127) < 1e-6)
        #expect(abs(f.b1 + 0.99479127) < 1e-6)
        #expect(abs(-f.a1 - 0.98958881) < 1e-5)
        #expect(f.b2 == 0)
        #expect(f.a2 == 0)
    }

    @Test func applyReproducesImpulseResponse() {
        let f = Biquad.peak(frequency: 300, gainDB: -3, q: 1.2)
        var impulse = [Float](repeating: 0, count: 8)
        impulse[0] = 1
        let h = f.apply(impulse)
        // Direct recursion on the coefficients.
        var expected = [Double](repeating: 0, count: 8)
        var x = [Double](repeating: 0, count: 8)
        x[0] = 1
        for n in 0..<8 {
            expected[n] = f.b0 * x[n]
                + (n >= 1 ? f.b1 * x[n - 1] - f.a1 * expected[n - 1] : 0)
                + (n >= 2 ? f.b2 * x[n - 2] - f.a2 * expected[n - 2] : 0)
        }
        for n in 0..<8 {
            #expect(abs(Double(h[n]) - expected[n]) < 1e-6)
        }
    }

    @Test func dcBlockedByHighPass() {
        let f = Biquad.firstOrderHighPass(frequency: 80)
        let dc = [Float](repeating: 1, count: 48_000)
        let out = f.apply(f.apply(dc))
        #expect(abs(out[47_999]) < 1e-3)
    }
}
