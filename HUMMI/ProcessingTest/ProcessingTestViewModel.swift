#if DEBUG
//
//  ProcessingTestViewModel.swift
//  HUMMI
//

#if DEBUG
import Foundation
import Observation

/// Drives the Processing Test screen: pick a recording, toggle stages,
/// render the chain offline, then A/B the result against the original.
@MainActor
@Observable
final class ProcessingTestViewModel {
    struct StageToggle: Identifiable {
        let id: String
        var isOn: Bool
    }

    private(set) var recordings: [RecordingItem] = []
    var selectedRecording: RecordingItem?
    var stageToggles: [StageToggle]
    private(set) var isProcessing = false
    /// ML enhancement progress (0…1) while the ML stage runs, nil otherwise.
    private(set) var mlProgress: Double?
    private(set) var processSeconds: Double?
    private(set) var errorMessage: String?

    let abPlayer = ABPlayer()

    init() {
        stageToggles = ProcessingPipeline.makeDefaultStages(parameters: .default)
            .map { StageToggle(id: $0.name, isOn: $0.isEnabled) }
    }

    func loadRecordings() async {
        do {
            recordings = try await Self.listRecordings()
            if selectedRecording == nil {
                selectedRecording = recordings.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func processSelected() async {
        guard let recording = selectedRecording, !isProcessing else { return }
        isProcessing = true
        errorMessage = nil
        processSeconds = nil
        mlProgress = nil
        abPlayer.unload()
        defer {
            isProcessing = false
            mlProgress = nil
        }

        let enabled = Set(stageToggles.filter(\.isOn).map(\.id))
        let onProgress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in self?.mlProgress = fraction }
        }
        do {
            let (outputURL, seconds) = try await Self.render(
                input: recording.url, enabledStages: enabled, onProgress: onProgress)
            processSeconds = seconds
            try abPlayer.load(original: recording.url, processed: outputURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `--pipeline-autorun`: renders the bundled SpikeTestClip through the
    /// full default chain and writes Documents/PipelineTest-enhanced.wav,
    /// for headless verification in the simulator.
    static let autorunArgument = "--pipeline-autorun"

    func autorunIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains(Self.autorunArgument),
              !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let (outputURL, seconds) = try await Self.renderBundledClip()
            processSeconds = seconds
            print("PipelineTest: wrote \(outputURL.path) "
                  + String(format: "(%.2fs)", seconds))
        } catch {
            errorMessage = error.localizedDescription
            print("PipelineTest: FAILED — \(error.localizedDescription)")
        }
    }

    /// `--profile-autorun`: renders a 40 s clip through the full chain
    /// with per-stage timing, prints the table, and writes it to
    /// Documents/profile-table.txt for headless reads.
    static let profileAutorunArgument = "--profile-autorun"

    func profileAutorunIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains(Self.profileAutorunArgument),
              !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let table = try await Self.renderProfiled()
            print("\n" + table + "\n")
            if let documents = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask).first {
                try? table.write(
                    to: documents.appendingPathComponent("profile-table.txt"),
                    atomically: true, encoding: .utf8)
            }
        } catch {
            errorMessage = error.localizedDescription
            print("ProfileTest: FAILED — \(error.localizedDescription)")
        }
    }

    @concurrent
    private static func renderProfiled() async throws -> String {
        let clipURL = try profileClipURL()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-render.wav")
        return try ProcessingPipeline().processProfiled(fileAt: clipURL, to: outputURL)
    }

    /// A ~40 s clip for profiling: the bundled ProfileClip40s if present,
    /// otherwise the 30 s SpikeTestClip tiled up to 40 s.
    private nonisolated static func profileClipURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "ProfileClip40s", withExtension: "m4a") {
            return url
        }
        guard let base = Bundle.main.url(forResource: "SpikeTestClip", withExtension: "m4a") else {
            throw DFNError.audioFile("no profiling clip in the app bundle")
        }
        let samples = try AudioClipIO.loadMono48k(from: base)
        let target = Int(40 * DFNContract.sampleRate)
        var tiled = samples
        while tiled.count < target { tiled.append(contentsOf: samples) }
        tiled = Array(tiled[0..<target])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-clip-40s.wav")
        try AudioClipIO.writeWAV(tiled, to: url)
        return url
    }

    @concurrent
    private static func renderBundledClip() async throws -> (URL, Double) {
        guard let clipURL = Bundle.main.url(
            forResource: "SpikeTestClip", withExtension: "m4a") else {
            throw DFNError.audioFile("SpikeTestClip.m4a is missing from the app bundle")
        }
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            throw DFNError.audioFile("the Documents folder is unavailable")
        }
        let outputURL = documents.appendingPathComponent("PipelineTest-enhanced.wav")
        let clock = ContinuousClock()
        let start = clock.now
        try ProcessingPipeline().process(fileAt: clipURL, to: outputURL)
        let elapsed = start.duration(to: clock.now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18
        return (outputURL, seconds)
    }

    @concurrent
    private static func listRecordings() async throws -> [RecordingItem] {
        try RecordingLibrary.listRecordings().map { entry in
            let metadata = (try? RecordingMetadata.loadOrCompute(for: entry.url)) ?? .empty()
            return RecordingItem(
                url: entry.url, date: entry.date,
                duration: metadata.duration, peaks: metadata.peaks)
        }
    }

    @concurrent
    private static func render(
        input: URL, enabledStages: Set<String>,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (outputURL: URL, seconds: Double) {
        let stages = ProcessingPipeline.makeDefaultStages(parameters: .default)
        for stage in stages {
            stage.isEnabled = enabledStages.contains(stage.name)
            (stage as? MLEnhanceStage)?.progressHandler = onProgress
        }
        let pipeline = ProcessingPipeline(stages: stages)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("processing-test.wav")
        let clock = ContinuousClock()
        let start = clock.now
        try pipeline.process(fileAt: input, to: outputURL)
        let elapsed = start.duration(to: clock.now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18
        return (outputURL, seconds)
    }
}
#endif
#endif
