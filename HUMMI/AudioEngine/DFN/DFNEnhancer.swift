//
//  DFNEnhancer.swift
//  HUMMI
//

import Foundation

/// Offline DeepFilterNet3 enhancement: 48 kHz mono Float32 samples in,
/// enhanced samples of the same length out. Implements the full
/// preprocessing → inference → postprocessing chain from
/// docs/model-contract.md.
nonisolated struct DFNEnhancer {
    private let model: DFNModel
    private let stft: VorbisSTFT

    /// Wall-clock split of one or more `enhance` calls. Times accumulate,
    /// so a caller processing chunks sees the sum across chunks.
    struct Timings: Sendable {
        /// STFT analysis + ERB / unit-norm feature extraction.
        var preprocessSeconds = 0.0
        /// Core ML prediction (input marshalling + inference).
        var inferenceSeconds = 0.0
        /// iSTFT overlap-add synthesis.
        var postprocessSeconds = 0.0
    }

    init() throws {
        model = try DFNModel()
        stft = try VorbisSTFT()
    }

    func enhance(_ samples: [Float]) throws -> [Float] {
        var ignored = Timings()
        return try enhance(samples, accumulating: &ignored)
    }

    /// Same as `enhance`, adding this call's preprocess / inference /
    /// postprocess wall-clock into `timings`.
    func enhance(_ samples: [Float], accumulating timings: inout Timings) throws -> [Float] {
        let clock = ContinuousClock()

        // Preprocessing: delay-compensation tail, STFT, features.
        let preStart = clock.now
        var padded = samples
        padded.append(contentsOf: [Float](repeating: 0, count: DFNContract.fftSize))
        let (spec, frames) = stft.analysis(padded)
        let erb = DFNFeatures.erb(spec: spec, frames: frames)
        let unitNorm = DFNFeatures.unitNorm(spec: spec, frames: frames)
        let inferenceStart = clock.now

        // Inference.
        let enhanced = try model.predict(
            spec: spec, erb: erb, unitNorm: unitNorm, frames: frames)
        let postStart = clock.now

        // Postprocessing: overlap-add synthesis.
        let output = stft.synthesis(
            spec: enhanced, frames: frames, outputLength: samples.count)
        let end = clock.now

        timings.preprocessSeconds += Self.seconds(preStart, inferenceStart)
        timings.inferenceSeconds += Self.seconds(inferenceStart, postStart)
        timings.postprocessSeconds += Self.seconds(postStart, end)
        return output
    }

    private static func seconds(
        _ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant
    ) -> Double {
        let parts = start.duration(to: end).components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}
