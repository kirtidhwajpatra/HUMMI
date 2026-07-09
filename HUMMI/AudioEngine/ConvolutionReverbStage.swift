//
//  ConvolutionReverbStage.swift
//  HUMMI
//

import Accelerate
import Foundation

/// Convolution reverb with the bundled prepared IR (onset-trimmed,
/// peak-normalized, 20 ms pre-delay baked in as leading silence). Port
/// of tools/spike/polish.py conv_reverb(): pedalboard/JUCE scales the
/// IR by 0.125/√(Σir²) and mixes linearly (verified empirically), so
/// output = (1-wet)·x + wet·(x ∗ ir_normalized), truncated to x's length.
nonisolated final class ConvolutionReverbStage: BufferStage {
    let name = "Reverb (convolution)"
    var isEnabled = true

    static let bundledIRName = "FrenchSalonIR"

    private let wet: Float
    private let irURL: URL?

    /// Pass `irURL` to override the bundled IR (used by test harnesses
    /// that run outside the app bundle).
    init(parameters: PresetParameters, irURL: URL? = nil) {
        self.wet = Float(parameters.reverbWet)
        self.irURL = irURL
    }

    func process(_ samples: [Float]) throws -> [Float] {
        guard wet > 0 else { return samples }
        guard let url = irURL ?? Bundle.main.url(
            forResource: Self.bundledIRName, withExtension: "wav")
        else {
            throw DFNError.audioFile("reverb impulse response missing from bundle")
        }
        let ir = Self.normalizeIR(try AudioClipIO.loadMono48k(from: url))
        let wetSignal = try Self.convolve(samples, with: ir)
        return vDSP.add(
            vDSP.multiply(1 - wet, samples), vDSP.multiply(wet, wetSignal))
    }

    // MARK: - Pure math (unit-tested)

    /// JUCE Convolution's normalise rule: scale to 0.125/√(Σir²).
    static func normalizeIR(_ ir: [Float]) -> [Float] {
        var energy = 0.0
        for s in ir {
            energy += Double(s) * Double(s)
        }
        guard energy > 0 else { return ir }
        return vDSP.multiply(Float(0.125 / energy.squareRoot()), ir)
    }

    /// FFT convolution, output truncated to `samples.count`.
    static func convolve(_ samples: [Float], with ir: [Float]) throws -> [Float] {
        var fftSize = 1024
        while fftSize < samples.count + ir.count { fftSize *= 2 }
        let fft = try RealFFT(count: fftSize)

        var padded = samples
        padded.append(contentsOf: [Float](repeating: 0, count: fftSize - samples.count))
        var irPadded = ir
        irPadded.append(contentsOf: [Float](repeating: 0, count: fftSize - ir.count))

        let (xRe, xIm) = fft.forward(padded)
        let (hRe, hIm) = fft.forward(irPadded)
        var yRe = [Float](repeating: 0, count: xRe.count)
        var yIm = [Float](repeating: 0, count: xRe.count)
        for b in 0..<xRe.count {
            yRe[b] = xRe[b] * hRe[b] - xIm[b] * hIm[b]
            yIm[b] = xRe[b] * hIm[b] + xIm[b] * hRe[b]
        }
        let full = fft.inverse(re: yRe, im: yIm)
        return Array(full[0..<samples.count])
    }
}
