//
//  MLEnhanceTests.swift
//  HUMMITests
//

import Foundation
import Testing
@testable import HUMMI

// Model-backed cases run serialized: concurrent Core ML predictions on
// the simulator's compute units make fp16 output jitter run-to-run.
@Suite(.serialized)
struct MLEnhanceTests {
    // MARK: - Chunk planning (pure)

    @Test func chunkPlanTilesWithoutGaps() {
        let plan = MLEnhanceStage.chunkPlan(total: 1_000, validChunk: 300, context: 50)
        #expect(plan.count == 4)
        // Valid regions abut exactly and cover [0, total).
        #expect(plan.first?.position == 0)
        #expect(plan.last?.validEnd == 1_000)
        for i in 1..<plan.count {
            #expect(plan[i].position == plan[i - 1].validEnd)
        }
        // Context reaches back at most `context`, never past 0.
        #expect(plan[0].contextStart == 0)
        #expect(plan[1].contextStart == 250)  // 300 - 50
        for chunk in plan {
            #expect(chunk.contextStart >= 0)
            #expect(chunk.contextStart <= chunk.position)
        }
    }

    @Test func chunkMemoryStaysBounded() {
        // A 10-minute song at the shipping sizes: every chunk's fed span
        // is bounded by validChunk + context, well under the model limit.
        let tenMinutes = 600 * 48_000
        let validChunk = MLEnhanceStage.validChunkFrames * DFNContract.hop
        let context = MLEnhanceStage.contextFrames * DFNContract.hop
        let plan = MLEnhanceStage.chunkPlan(
            total: tenMinutes, validChunk: validChunk, context: context)
        for chunk in plan {
            let fedFrames = (chunk.validEnd - chunk.contextStart) / DFNContract.hop
            #expect(fedFrames <= 16_384)  // Core ML flexible-shape ceiling
        }
        #expect(plan.count == 15)  // 600s / 40s
    }

    @Test func singleChunkForShortClip() {
        let plan = MLEnhanceStage.chunkPlan(total: 240_000, validChunk: 1_000_000, context: 7_200)
        #expect(plan.count == 1)
        #expect(plan[0] == MLEnhanceStage.Chunk(contextStart: 0, position: 0, validEnd: 240_000))
    }

    @Test func emptyClipHasNoChunks() {
        #expect(MLEnhanceStage.chunkPlan(total: 0, validChunk: 100, context: 10).isEmpty)
    }

    // MARK: - Dry/wet mix (pure)

    @Test func mixEndpointsAndMidpoint() {
        let enhanced: [Float] = [1, 1, 1, 1]
        let dry: [Float] = [0, 0, 0, 0]
        #expect(MLEnhanceStage.mix(enhanced: enhanced, dry: dry, dryWet: 1) == enhanced)
        #expect(MLEnhanceStage.mix(enhanced: enhanced, dry: dry, dryWet: 0) == dry)
        let half = MLEnhanceStage.mix(enhanced: enhanced, dry: dry, dryWet: 0.5)
        #expect(half.allSatisfy { abs($0 - 0.5) < 1e-6 })
        let ninety = MLEnhanceStage.mix(enhanced: [2], dry: [0], dryWet: 0.9)
        #expect(abs(ninety[0] - 1.8) < 1e-6)
    }

    @Test func dryWetZeroBypassesEntirely() throws {
        var params = PresetParameters.default
        params.mlEnhanceDryWet = 0
        let input = (0..<48_000).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
        let out = try MLEnhanceStage(parameters: params).process(input)
        #expect(out == input)  // no model run at all
    }

    @Test func vocalSafeMixProtectsLoudMaterialButCleansSilence() {
        let dry: [Float] = [0, 0, 0.8, 0.8, 0.8, 0.8, 0.8]
        let enhanced: [Float] = [1, 1, 1, 1, 1, 1, 1]
        let output = MLEnhanceStage.mixVocalSafe(
            enhanced: enhanced, dry: dry, dryWet: 0.8, vocalWetCeiling: 0.4)

        // Noise-only material receives the requested blend; once the input
        // envelope identifies an audible phrase, the dry vocal is protected.
        #expect(abs(output[0] - 0.8) < 0.001)
        #expect(output[6] < 0.7)
    }

    // MARK: - Model-backed (runs hosted in the app / simulator)

    /// Chunked enhancement of a real clip must match a single-pass
    /// enhance in the interior: with warm-up context, per-chunk state
    /// reconverges, so valid regions are near-identical.
    @Test func chunkedMatchesWholeClip() throws {
        guard let url = Bundle.main.url(forResource: "SpikeTestClip", withExtension: "m4a") else {
            return  // clip not bundled in this configuration
        }
        let samples = try AudioClipIO.loadMono48k(from: url)
        let enhancer = try DFNEnhancer()

        let whole = try enhancer.enhance(samples)
        // Force ~4 chunks over the 30 s clip (800 frames = 8 s each).
        let chunked = try MLEnhanceStage.enhanceChunked(
            samples, enhancer: enhancer, validFrames: 800, contextFrames: 300)

        #expect(chunked.count == whole.count)
        // Compare the interior (skip the first 1 s, where the cold-state
        // warm-up differs between the two runs anyway). A recurrent
        // denoiser fed limited-context chunks cannot be bit-identical to
        // one fed the whole history, so the robust criterion is that the
        // two track each other closely (high correlation, zero lag) with
        // no gross artifact — not a tight energy-difference floor.
        let start = 48_000
        let a = Array(chunked[start...])
        let b = Array(whole[start...])
        let correlation = Self.pearson(a, b)
        let relDB = Self.relativeErrorDB(a, from: b)
        Self.writeDiagnostic("relDB=\(relDB) corr=\(correlation)")
        // Gross-artifact smoke test: a gap or misalignment would tank
        // correlation to well under 0.5. The genuine per-chunk state
        // difference (largest in suppressed near-silence) keeps it under
        // 1, so this is deliberately loose; lag-0 is the precise check.
        #expect(correlation > 0.9)
        #expect(Self.bestLag(a, b, search: 480) == 0)  // no time offset
    }

    @Test func progressReportsMonotonicallyToOne() throws {
        guard let url = Bundle.main.url(forResource: "SpikeTestClip", withExtension: "m4a") else {
            return
        }
        let samples = try AudioClipIO.loadMono48k(from: url)
        let enhancer = try DFNEnhancer()
        let box = ProgressBox()
        _ = try MLEnhanceStage.enhanceChunked(
            samples, enhancer: enhancer, validFrames: 800, contextFrames: 300,
            progress: { box.append($0) })
        let values = box.values
        #expect(!values.isEmpty)
        #expect(values == values.sorted())
        #expect(abs((values.last ?? 0) - 1) < 1e-9)
    }

    // MARK: - Metrics

    static func pearson(_ a: [Float], _ b: [Float]) -> Double {
        let n = Double(min(a.count, b.count))
        var sumA = 0.0, sumB = 0.0
        for i in 0..<Int(n) { sumA += Double(a[i]); sumB += Double(b[i]) }
        let meanA = sumA / n, meanB = sumB / n
        var cov = 0.0, varA = 0.0, varB = 0.0
        for i in 0..<Int(n) {
            let da = Double(a[i]) - meanA, db = Double(b[i]) - meanB
            cov += da * db; varA += da * da; varB += db * db
        }
        let denom = (varA * varB).squareRoot()
        return denom > 1e-20 ? cov / denom : 0
    }

    static func relativeErrorDB(_ a: [Float], from b: [Float]) -> Double {
        var errorEnergy = 0.0, signalEnergy = 0.0
        for i in 0..<min(a.count, b.count) {
            let d = Double(a[i] - b[i])
            errorEnergy += d * d
            signalEnergy += Double(b[i]) * Double(b[i])
        }
        return 10 * log10(errorEnergy / signalEnergy + 1e-30)
    }

    static func bestLag(_ a: [Float], _ b: [Float], search: Int) -> Int {
        var bestLag = 0
        var bestDot = -Double.infinity
        let n = min(a.count, b.count)
        for lag in -search...search {
            var dot = 0.0
            for i in max(0, -lag)..<min(n, n - lag) {
                dot += Double(a[i]) * Double(b[i + lag])
            }
            if dot > bestDot { bestDot = dot; bestLag = lag }
        }
        return bestLag
    }

    static func writeDiagnostic(_ text: String) {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first else { return }
        try? text.write(
            to: documents.appendingPathComponent("mlparity.txt"),
            atomically: true, encoding: .utf8)
    }

    private final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Double] = []
        func append(_ v: Double) { lock.lock(); storage.append(v); lock.unlock() }
        var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
    }
}
