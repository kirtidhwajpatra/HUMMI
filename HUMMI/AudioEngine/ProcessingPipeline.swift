//
//  ProcessingPipeline.swift
//  HUMMI
//

import Foundation

/// Offline enhancement chain: 48 kHz mono Float32 samples in, processed
/// samples out. Stages run in order on the sample array; disabled
/// stages are skipped.
nonisolated final class ProcessingPipeline {
    let stages: [any ProcessingStage]

    init(stages: [any ProcessingStage]) {
        self.stages = stages
    }

    convenience init(parameters: PresetParameters = .default) {
        self.init(stages: Self.makeDefaultStages(parameters: parameters))
    }

    /// The v1 enhancement chain, in processing order: ML enhancement
    /// (Stage A, chunked DFN3 + dry/wet), pitch correction, then the
    /// polish chain (tools/spike/polish.py): high-pass -> surgical EQ ->
    /// de-esser -> multiband compression -> parallel saturation ->
    /// presence/air -> convolution reverb -> glue, then loudness
    /// normalization. Three stages are A/B alternates disabled by
    /// default — their `isEnabled` seeds the debug screen's toggles:
    /// DFNRestorationStage (adaptive-floor alternative to ML enhance),
    /// and the Apple-AU compressor and room reverb (alternates to the
    /// spike compressor/reverb pair). Enabling an alternate alongside
    /// its counterpart double-processes; that is intentional A/B latitude.
    static func makeDefaultStages(parameters: PresetParameters) -> [any ProcessingStage] {
        [
            MLEnhanceStage(parameters: parameters),
            DFNRestorationStage(parameters: parameters),
            PitchCorrectionStage(parameters: parameters),
            HighPassStage(parameters: parameters),
            EQStage(parameters: parameters),
            CompressorStage(parameters: parameters),
            DeEsserStage(parameters: parameters),
            MultibandCompressorStage(parameters: parameters),
            SaturationStage(parameters: parameters),
            PresenceAirStage(parameters: parameters),
            ConvolutionReverbStage(parameters: parameters),
            ReverbStage(parameters: parameters),
            GlueCompressorStage(parameters: parameters),
            LoudnessNormalizeStage(parameters: parameters),
        ]
    }

    func process(_ input: [Float]) throws -> [Float] {
        var samples = input
        for stage in stages where stage.isEnabled {
            samples = try stage.process(samples)
        }
        return samples
    }

    // MARK: - Profiling

    /// Wall-clock time spent in one enabled stage; `mlDetail` is set only
    /// for the ML enhancement stage.
    struct StageProfile: Sendable {
        let name: String
        let seconds: Double
        let mlDetail: MLEnhanceStage.Profile?
    }

    /// Runs the chain, measuring each enabled stage. Returns the output
    /// alongside per-stage timings for `profileTable`.
    func processProfiled(_ input: [Float]) throws -> (output: [Float], profile: [StageProfile]) {
        let clock = ContinuousClock()
        var samples = input
        var profiles: [StageProfile] = []
        for stage in stages where stage.isEnabled {
            let start = clock.now
            samples = try stage.process(samples)
            let elapsed = Self.durationSeconds(start.duration(to: clock.now))
            profiles.append(StageProfile(
                name: stage.name, seconds: elapsed,
                mlDetail: (stage as? MLEnhanceStage)?.lastProfile))
        }
        return (samples, profiles)
    }

    /// Reads a recording, renders it profiled, writes the WAV, and
    /// returns the formatted timing table.
    func processProfiled(fileAt inputURL: URL, to outputURL: URL) throws -> String {
        let samples = try AudioClipIO.loadMono48k(from: inputURL)
        let (output, profile) = try processProfiled(samples)
        try AudioClipIO.writeWAV(output, to: outputURL)
        let clipSeconds = Double(samples.count) / DFNContract.sampleRate
        return Self.profileTable(profile, clipSeconds: clipSeconds)
    }

    private static func durationSeconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }

    /// A fixed-width console table of per-stage timings, with the ML
    /// stage broken down into preprocess / inference / postprocess and
    /// its chunk count, plus a total and real-time factor.
    static func profileTable(_ profiles: [StageProfile], clipSeconds: Double) -> String {
        let total = profiles.reduce(0) { $0 + $1.seconds }
        func ms(_ seconds: Double) -> String { String(format: "%9.1f", seconds * 1000) }
        func pct(_ seconds: Double) -> String {
            total > 0 ? String(format: "%6.1f%%", seconds / total * 100) : "     —"
        }
        func row(_ label: String, _ time: String, _ percent: String) -> String {
            label.padding(toLength: 30, withPad: " ", startingAt: 0) + time + "   " + percent
        }

        let rule = String(repeating: "─", count: 30 + 9 + 3 + 7)
        var lines: [String] = []
        lines.append(row("Stage", "Time (ms)".leftPadded(to: 9), "  % total"))
        lines.append(rule)
        for profile in profiles {
            lines.append(row(profile.name, ms(profile.seconds), pct(profile.seconds)))
            if let ml = profile.mlDetail {
                lines.append(row("  ├ model load (one-time)", ms(ml.modelLoadSeconds), ""))
                lines.append(row("  ├ preprocess (STFT+feat)", ms(ml.preprocessSeconds), ""))
                lines.append(row("  ├ Core ML inference", ms(ml.inferenceSeconds), ""))
                lines.append(row("  ├ postprocess (iSTFT)", ms(ml.postprocessSeconds), ""))
                lines.append(row("  └ chunks", String(format: "%9d", ml.chunkCount), ""))
            }
        }
        lines.append(rule)
        lines.append(row("Total", ms(total), total > 0 ? "100.0%" : "     —"))
        let rtf = clipSeconds > 0 ? total / clipSeconds : 0
        let speedup = total > 0 ? clipSeconds / total : 0
        lines.append(String(
            format: "Clip: %.1fs   RTF: %.4fx   (%.1fx realtime)",
            clipSeconds, rtf, speedup))
        return lines.joined(separator: "\n")
    }

    /// Convenience: reads a recording, processes it, writes a WAV.
    func process(fileAt inputURL: URL, to outputURL: URL) throws {
        let samples = try AudioClipIO.loadMono48k(from: inputURL)
        try AudioClipIO.writeWAV(try process(samples), to: outputURL)
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: " ", count: length - count) + self
    }
}
