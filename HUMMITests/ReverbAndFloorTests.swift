//
//  ReverbAndFloorTests.swift
//  HUMMITests
//

import Foundation
import Testing
@testable import HUMMI

struct ReverbAndFloorTests {
    @Test func irNormalizationMatchesJUCE() {
        // JUCE Convolution normalise: scale to 0.125/√(Σir²) — verified
        // empirically: IR (1, 0.5, -0.25) → first tap 0.10911.
        let ir = ConvolutionReverbStage.normalizeIR([1, 0.5, -0.25])
        #expect(abs(Double(ir[0]) - 0.10911) < 1e-4)
        #expect(abs(Double(ir[1]) - 0.05455) < 1e-4)
    }

    @Test func fftConvolutionMatchesDirect() throws {
        let x: [Float] = [1, 0.5, -0.25, 0.125, 0, -1, 0.75, 0.3]
        let h: [Float] = [0.5, 0.25, -0.125]
        let fast = try ConvolutionReverbStage.convolve(x, with: h)
        for n in 0..<x.count {
            var direct: Double = 0
            for k in 0...min(n, h.count - 1) {
                direct += Double(h[k]) * Double(x[n - k])
            }
            #expect(abs(Double(fast[n]) - direct) < 1e-5)
        }
    }

    @Test func movingMeanOfSquaresReflects() {
        // scipy uniform_filter1d(x², 4, mode="reflect"): window offsets
        // [-2, 1]; at i=0 the window is [x[1], x[0], x[0], x[1]] (reflect).
        let out = AdaptiveFloor.movingMeanOfSquares([1, 2, 3, 4], size: 4)
        #expect(abs(out[0] - (4.0 + 1.0 + 1.0 + 4.0) / 4.0) < 1e-9)
        #expect(abs(out[1] - (1.0 + 1.0 + 4.0 + 9.0) / 4.0) < 1e-9)
        #expect(abs(out[2] - (1.0 + 4.0 + 9.0 + 16.0) / 4.0) < 1e-9)
        #expect(abs(out[3] - (4.0 + 9.0 + 16.0 + 16.0) / 4.0) < 1e-9)
    }

    @Test func keepSustainedDropsShortRuns() {
        var mask = [Float](repeating: 0, count: 100)
        for i in 10..<20 { mask[i] = 1 }   // run of 10
        for i in 40..<80 { mask[i] = 1 }   // run of 40
        let out = AdaptiveFloor.keepSustained(mask, minRun: 20)
        #expect(out[15] == 0)
        #expect(out[41] == 1)
        #expect(out[79] == 1)
        #expect(out[80] == 0)
    }

    @Test func adaptiveWeightsClampToLimits() {
        // Enhanced == original (model removed nothing): no quiet frames,
        // noise floor -120 → far below target → lim clamps to minLimDB = 6
        // (barely blend the original back in; the clip is already clean).
        let tone = (0..<96_000).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) * 0.3 }
        let w = AdaptiveFloor.weights(
            original: tone, enhanced: tone,
            voicedMask: [Float](repeating: 0, count: tone.count),
            targetFloorDB: 45, voicedCapDB: 12)
        let expected = Float(pow(10.0, -AdaptiveFloor.minLimDB / 20.0))
        #expect(abs(w[48_000] - expected) < 1e-6)
    }

    @Test func saturationIsParallelTanh() throws {
        var params = PresetParameters.default
        params.saturationBlend = 0.15
        let x: [Float] = [-0.8, -0.2, 0, 0.2, 0.8]
        let out = try SaturationStage(parameters: params).process(x)
        let drive = pow(10.0, 5.0 / 20.0)
        for i in 0..<x.count {
            let expected = 0.85 * Double(x[i]) + 0.15 * tanh(drive * Double(x[i]))
            #expect(abs(Double(out[i]) - expected) < 1e-5)
        }
    }

    @Test func realFFTRoundTrips() throws {
        let fft = try RealFFT(count: 1_024)
        var seed: UInt64 = 7
        let x = (0..<1_024).map { _ -> Float in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }
        let (re, im) = fft.forward(x)
        let back = fft.inverse(re: re, im: im)
        for i in 0..<x.count {
            #expect(abs(back[i] - x[i]) < 1e-4)
        }
    }

    @Test func voicedDetectorHearsPitchNotNoise() {
        let sr = 48_000
        let tone = (0..<sr).map { Float(sin(2 * Double.pi * 220 * Double($0) / 48_000)) * 0.3 }
        let toneMask = VoicedDetector.mask(tone)
        #expect(toneMask[24_000] == 1)

        var seed: UInt64 = 99
        let noise = (0..<sr).map { _ -> Float in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return (Float(seed >> 40) / Float(1 << 24) - 0.5) * 0.3
        }
        let noiseMask = VoicedDetector.mask(noise)
        #expect(noiseMask[24_000] == 0)

        // 100 Hz is below the 130 Hz singing gate (rumble guard).
        let rumble = (0..<sr).map { Float(sin(2 * Double.pi * 100 * Double($0) / 48_000)) * 0.3 }
        let rumbleMask = VoicedDetector.mask(rumble)
        #expect(rumbleMask[24_000] == 0)
    }
}
