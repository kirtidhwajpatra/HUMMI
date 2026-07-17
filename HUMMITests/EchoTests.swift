//
//  EchoTests.swift
//  HUMMITests
//
//  Pure-math tests for the feedback-delay echo.
//

import Testing
@testable import HUMMI

struct EchoTests {
    @Test func impulseProducesDecayingTaps() {
        var x = [Float](repeating: 0, count: 100)
        x[0] = 1
        let out = EchoStage.echo(x, delaySamples: 10, feedback: 0.5, wet: 0.4)

        #expect(abs(out[0] - 1.0) < 1e-6)                     // dry, untouched
        #expect(abs(out[10] - 0.4) < 1e-6)                    // wet · x[n−D]
        #expect(abs(out[20] - 0.4 * 0.5) < 1e-6)              // wet · fb
        #expect(abs(out[30] - 0.4 * 0.25) < 1e-6)             // wet · fb²
        #expect(abs(out[5]) < 1e-6)                           // silence between taps
    }

    @Test func zeroWetOrZeroDelayPassesThrough() {
        let x: [Float] = [0.3, -0.5, 0.8, 0.1]
        #expect(EchoStage.echo(x, delaySamples: 2, feedback: 0.5, wet: 0) == x)
        #expect(EchoStage.echo(x, delaySamples: 0, feedback: 0.5, wet: 0.5) == x)
    }

    @Test func lengthIsPreserved() {
        let x = [Float](repeating: 0.25, count: 1_234)
        let out = EchoStage.echo(x, delaySamples: 100, feedback: 0.6, wet: 0.5)
        #expect(out.count == x.count)
    }

    @Test func runawayFeedbackIsClamped() {
        var x = [Float](repeating: 0, count: 48_000)
        x[0] = 1
        // feedback 2.0 would explode; the clamp keeps the tail decaying.
        let out = EchoStage.echo(x, delaySamples: 100, feedback: 2.0, wet: 1.0)
        let peak = out.map(abs).max() ?? 0
        #expect(peak <= 1.0 + 1e-6)
        // Tap 400 delays in: 0.9^399 ≈ 0 — verifiably finite and tiny.
        #expect(abs(out[40_000]) < 0.02)
    }

    @Test func delayLongerThanClipPassesThrough() {
        let x: [Float] = [0.1, 0.2, 0.3]
        #expect(EchoStage.echo(x, delaySamples: 10, feedback: 0.5, wet: 0.5) == x)
    }
}
