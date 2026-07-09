//
//  MLEnhanceStage.swift
//  HUMMI
//

import Foundation

/// Stage A: DeepFilterNet3 neural enhancement, the first stage in the
/// chain. Reuses the contract port (VorbisSTFT / DFNFeatures / DFNModel
/// via DFNEnhancer) but processes the clip in overlapping chunks so
/// memory stays bounded and songs longer than the model's maximum frame
/// count (16,384 frames ≈ 2.7 min) still process. Each chunk carries a
/// real-audio warm-up context ahead of its valid region — the Core ML
/// model's recurrent state and the α = 0.99 feature normalizations both
/// start cold and need ~1 s to converge — and chunks are crossfade-
/// spliced. The enhanced signal is then mixed with the original by
/// `dryWet` (1 = fully enhanced), because full ML output can sound
/// over-processed on already-clean takes.
nonisolated final class MLEnhanceStage: BufferStage {
    let name = "ML enhance (DFN3)"
    var isEnabled = true

    /// Valid (kept) frames per chunk. 4,000 frames = 40 s; with the
    /// warm-up context this stays well under the model's 16,384 limit.
    static let validChunkFrames = 4_000
    /// Warm-up context frames before each valid region (~3 s), long
    /// enough for the recurrent state and α = 0.99 norm (100-frame time
    /// constant) to converge before the kept region begins.
    static let contextFrames = 300
    /// Crossfade at chunk seams (10 ms).
    static let crossfadeSamples = 480

    private let dryWet: Double

    /// Called with a 0…1 fraction after each chunk. Set by the caller
    /// before `process`; invoked on the processing thread, so hop to the
    /// main actor inside the handler for UI updates.
    var progressHandler: (@Sendable (Double) -> Void)?

    /// Wall-clock breakdown of the most recent `process`, for profiling.
    struct Profile: Sendable {
        var modelLoadSeconds = 0.0
        var preprocessSeconds = 0.0
        var inferenceSeconds = 0.0
        var postprocessSeconds = 0.0
        var chunkCount = 0
    }
    private(set) var lastProfile: Profile?

    init(parameters: PresetParameters) {
        self.dryWet = parameters.mlEnhanceDryWet
    }

    func process(_ samples: [Float]) throws -> [Float] {
        guard dryWet > 0, !samples.isEmpty else { return samples }

        progressHandler?(0)
        let clock = ContinuousClock()
        let loadStart = clock.now
        let enhancer = try DFNEnhancer()
        let loadParts = loadStart.duration(to: clock.now).components
        let modelLoadSeconds = Double(loadParts.seconds) + Double(loadParts.attoseconds) * 1e-18

        let accumulator = ProfileAccumulator()
        let enhanced = try Self.enhanceChunked(
            samples, enhancer: enhancer, progress: progressHandler,
            profile: accumulator)
        lastProfile = Profile(
            modelLoadSeconds: modelLoadSeconds,
            preprocessSeconds: accumulator.timings.preprocessSeconds,
            inferenceSeconds: accumulator.timings.inferenceSeconds,
            postprocessSeconds: accumulator.timings.postprocessSeconds,
            chunkCount: accumulator.chunkCount)

        // Dry/wet mix.
        let output = Self.mix(enhanced: enhanced, dry: samples, dryWet: dryWet)
        progressHandler?(1)
        return output
    }

    /// Mutable accumulator threaded through the chunk loop (reference so
    /// the per-chunk timings and count add up across the loop).
    final class ProfileAccumulator {
        var timings = DFNEnhancer.Timings()
        var chunkCount = 0
    }

    // MARK: - Chunk planning (pure, unit-tested)

    /// One chunk of work: `context ..< validEnd` is fed to the model,
    /// `position ..< validEnd` is the valid region kept from it.
    struct Chunk: Equatable {
        var contextStart: Int
        var position: Int
        var validEnd: Int
    }

    /// Tiles `[0, total)` into valid regions of `validChunk` samples, each
    /// preceded by up to `context` samples of warm-up. Valid regions abut
    /// exactly (no gaps, no double coverage), so memory per chunk is
    /// bounded by `validChunk + context` regardless of song length.
    static func chunkPlan(
        total: Int, validChunk: Int, context: Int
    ) -> [Chunk] {
        guard total > 0 else { return [] }
        var chunks: [Chunk] = []
        var position = 0
        while position < total {
            let validEnd = min(position + validChunk, total)
            chunks.append(Chunk(
                contextStart: max(0, position - context),
                position: position, validEnd: validEnd))
            position = validEnd
        }
        return chunks
    }

    /// enhanced·dryWet + dry·(1−dryWet).
    static func mix(enhanced: [Float], dry: [Float], dryWet: Double) -> [Float] {
        let wet = Float(dryWet)
        let dryGain = Float(1 - dryWet)
        var output = [Float](repeating: 0, count: enhanced.count)
        for i in 0..<enhanced.count {
            output[i] = wet * enhanced[i] + dryGain * dry[i]
        }
        return output
    }

    // MARK: - Chunked enhancement

    /// Full-length enhanced signal, built from overlapping chunks.
    /// `validFrames`/`contextFrames` are injectable for testing; the
    /// defaults are the shipping sizes.
    static func enhanceChunked(
        _ samples: [Float], enhancer: DFNEnhancer,
        validFrames: Int = validChunkFrames, contextFrames: Int = contextFrames,
        progress: (@Sendable (Double) -> Void)? = nil,
        profile: ProfileAccumulator? = nil
    ) throws -> [Float] {
        let total = samples.count
        let validChunk = validFrames * DFNContract.hop
        let context = contextFrames * DFNContract.hop
        let plan = chunkPlan(total: total, validChunk: validChunk, context: context)

        var enhanced = [Float](repeating: 0, count: total)
        for (index, chunk) in plan.enumerated() {
            let input = Array(samples[chunk.contextStart..<chunk.validEnd])
            let enhancedChunk: [Float]
            if let profile {
                profile.chunkCount += 1
                enhancedChunk = try enhancer.enhance(input, accumulating: &profile.timings)
            } else {
                enhancedChunk = try enhancer.enhance(input)
            }

            if index == 0 {
                for j in chunk.position..<chunk.validEnd {
                    enhanced[j] = enhancedChunk[j - chunk.contextStart]
                }
            } else {
                // The seam sits inside this chunk's (now warm) context, so
                // both sides are reliable; crossfade over the overlap.
                let blendStart = max(chunk.position - crossfadeSamples, chunk.contextStart)
                let fade = Double(chunk.position - blendStart)
                for j in blendStart..<chunk.position {
                    let phase = Double.pi * Double(j - blendStart) / fade
                    let w = Float(0.5 * (1 - cos(phase)))
                    enhanced[j] = (1 - w) * enhanced[j] + w * enhancedChunk[j - chunk.contextStart]
                }
                for j in chunk.position..<chunk.validEnd {
                    enhanced[j] = enhancedChunk[j - chunk.contextStart]
                }
            }
            progress?(Double(chunk.validEnd) / Double(total))
        }
        return enhanced
    }
}
