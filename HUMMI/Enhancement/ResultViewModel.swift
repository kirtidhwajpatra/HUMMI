//
//  ResultViewModel.swift
//  HUMMI
//

import Foundation
import Observation

/// Drives the Result screen: renders the enhancement pipeline for the
/// chosen preset (with live progress), caches one render per
/// preset/adjustment so switching back is instant, persists the three
/// base presets alongside the original, and feeds the A/B player.
@MainActor
@Observable
final class ResultViewModel {
    enum Phase: Equatable {
        case idle              // recorded but not yet enhanced
        case enhancing(Double?)  // rendering; fraction if known
        case ready             // a render is loaded for A/B
    }

    let originalURL: URL
    /// The user-facing take name, editable on the Save screen.
    var displayName: String
    private(set) var peaks: [Float] = []
    private(set) var duration: TimeInterval = 0
    private(set) var phase: Phase = .idle
    private(set) var isRendering = false
    var errorMessage: String?

    private(set) var selectedPreset: StudioPreset = .studio

    // The four adjustable fields, initialized from the selected preset.
    var autotuneStrength: Double
    var reverbAmount: Double
    var noiseRemoval: Double
    var warmth: Double

    let abPlayer = ABPlayer()

    // Export state.
    private(set) var isExporting = false
    private(set) var videoProgress: Double?
    var shareItem: ShareItem?
    var paywallReason: PaywallPlaceholderView.Reason?
    var removeWatermark = false
    private let pro = ProStore.shared

    /// The enhanced render currently loaded for A/B — the export source.
    private var currentURL: URL?

    /// Rendered file per parameter key; base presets also persist to disk.
    private var cache: [String: URL] = [:]
    /// The key whose render is currently loaded, so we can tell when the
    /// sliders have diverged (→ show "Apply").
    private var lastRenderedKey: String?
    private var progressTicker: Task<Void, Never>?
    private var enhanceStart: Date?
    private var lastMLFraction: Double = 0

    init(originalURL: URL) {
        self.originalURL = originalURL
        self.displayName = RecordingNames.name(for: originalURL)
        let p = StudioPreset.default.parameters
        autotuneStrength = p.pitchCorrectionStrength
        reverbAmount = p.reverbWet
        noiseRemoval = p.mlEnhanceDryWet
        warmth = p.warmthGainDB
    }

    /// Sliders diverged from the loaded render → an Apply is pending.
    var isDirty: Bool {
        guard case .ready = phase, let lastRenderedKey else { return false }
        return key() != lastRenderedKey
    }

    // MARK: - Lifecycle

    func onAppear() async {
        if peaks.isEmpty {
            let meta = await Self.loadMetadata(originalURL)
            peaks = meta.peaks
            duration = meta.duration
        }
        // Preload any renders already on disk into the cache.
        for preset in EnhancementStore.existingPresets(for: originalURL) {
            if let url = try? EnhancementStore.url(for: originalURL, preset: preset) {
                cache[baseKey(for: preset)] = url
            }
        }
        // If this take was already enhanced, open straight into A/B,
        // listening to the enhanced ("After") rendition.
        if case .idle = phase, let studioURL = cache[baseKey(for: .studio)] {
            selectedPreset = .studio
            syncSliders(to: .studio)
            await loadIntoPlayer(studioURL)
            abPlayer.listeningToProcessed = true
            lastRenderedKey = baseKey(for: .studio)
            phase = .ready
        } else if !abPlayer.isLoaded {
            do {
                try abPlayer.load(original: originalURL, processed: originalURL)
                abPlayer.listeningToProcessed = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func tearDown() {
        progressTicker?.cancel()
        progressTicker = nil
        abPlayer.unload()
    }

    // MARK: - Actions

    /// The prominent "✨ Studio" button.
    func enhanceWithStudio() async {
        selectedPreset = .studio
        syncSliders(to: .studio)
        await render()
        // Land on the enhanced rendition so the effect is audible.
        if case .ready = phase { abPlayer.listeningToProcessed = true }
    }

    func selectPreset(_ preset: StudioPreset) async {
        guard preset != selectedPreset, !isRendering else { return }
        selectedPreset = preset
        syncSliders(to: preset)
        await render()
    }

    func applyAdjustments() async {
        guard !isRendering else { return }
        await render()
    }

    /// Persist the current name so the library reflects it.
    func commitName() {
        RecordingNames.setName(displayName, for: originalURL)
    }

    // MARK: - Rendering

    private func render() async {
        let k = key()
        if let cached = cache[k] {                 // instant switch
            await loadIntoPlayer(cached)
            lastRenderedKey = k
            phase = .ready
            return
        }

        isRendering = true
        phase = .enhancing(nil)
        startProgressEstimator()
        defer {
            isRendering = false
            stopProgressEstimator()
        }

        let parameters = effectiveParameters()
        let base = isBaseRender
        let preset = selectedPreset
        do {
            let outputURL: URL = base
                ? try EnhancementStore.url(for: originalURL, preset: preset)
                : FileManager.default.temporaryDirectory
                    .appendingPathComponent("enhanced-\(UUID().uuidString).wav")
            try await Self.render(
                originalURL: originalURL, parameters: parameters, outputURL: outputURL
            ) { [weak self] fraction in
                Task { @MainActor in self?.registerMLProgress(fraction) }
            }
            cache[k] = outputURL
            lastRenderedKey = k
            await loadIntoPlayer(outputURL)
            phase = .ready
        } catch {
            errorMessage = error.localizedDescription
            phase = abPlayer.isLoaded ? .ready : .idle
        }
    }

    /// Loads a processed render for A/B, keeping the current playhead and
    /// play/pause state so switching presets doesn't interrupt listening.
    private func loadIntoPlayer(_ processedURL: URL) async {
        currentURL = processedURL
        let wasPlaying = abPlayer.isPlaying
        let time = abPlayer.currentTime
        do {
            try abPlayer.load(original: originalURL, processed: processedURL)
            if time > 0, time < abPlayer.duration { abPlayer.seek(to: time) }
            if wasPlaying { abPlayer.play() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Export

    /// Whether the free tier allows exporting this take.
    var canExport: Bool { pro.isPro || pro.canExportForFree(duration: duration) }

    var isPro: Bool { pro.isPro }

    func saveAudio() async {
        guard let source = currentURL, !isExporting else { return }
        guard canExport else { paywallReason = .longExport; return }
        isExporting = true
        defer { isExporting = false }
        do {
            let formatRaw = UserDefaults.standard.string(forKey: "exportFormat") ?? ExportFormat.m4a.rawValue
            if formatRaw == ExportFormat.wav.rawValue {
                let output = exportURL(extension: "wav")
                if FileManager.default.fileExists(atPath: output.path) {
                    try FileManager.default.removeItem(at: output)
                }
                try FileManager.default.copyItem(at: source, to: output)
                shareItem = ShareItem(url: output)
            } else {
                let output = exportURL(extension: "m4a")
                try await AudioExporter.exportM4A(from: source, to: output)
                shareItem = ShareItem(url: output)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func shareVideo() async {
        guard let source = currentURL, !isExporting else { return }
        guard canExport else { paywallReason = .longExport; return }
        // Free tier always watermarks; only Pro can remove it.
        let watermark = !(pro.isPro && removeWatermark)
        isExporting = true
        videoProgress = 0
        defer {
            isExporting = false
            videoProgress = nil
        }
        do {
            let output = exportURL(extension: "mp4")
            try await VideoExporter.exportMP4(
                audioURL: source, peaks: peaks, duration: duration,
                watermark: watermark, to: output
            ) { [weak self] fraction in
                Task { @MainActor in self?.videoProgress = fraction }
            }
            shareItem = ShareItem(url: output)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The watermark-removal toggle is Pro-gated.
    func toggleRemoveWatermark() {
        if pro.isPro {
            removeWatermark.toggle()
        } else {
            paywallReason = .removeWatermark
        }
    }

    private func exportURL(extension ext: String) -> URL {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? AppBranding.name : trimmed
        let name = base.replacingOccurrences(of: " ", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).\(ext)")
    }

    // MARK: - Parameters & keys

    private func effectiveParameters() -> PresetParameters {
        var p = selectedPreset.parameters
        p.pitchCorrectionStrength = autotuneStrength
        p.reverbWet = reverbAmount
        p.mlEnhanceDryWet = noiseRemoval
        p.warmthGainDB = warmth
        return p
    }

    private func syncSliders(to preset: StudioPreset) {
        let d = preset.parameters
        autotuneStrength = d.pitchCorrectionStrength
        reverbAmount = d.reverbWet
        noiseRemoval = d.mlEnhanceDryWet
        warmth = d.warmthGainDB
    }

    private var isBaseRender: Bool {
        key() == baseKey(for: selectedPreset)
    }

    private func key() -> String {
        Self.key(preset: selectedPreset, autotune: autotuneStrength,
                 reverb: reverbAmount, noise: noiseRemoval, warmth: warmth)
    }

    private func baseKey(for preset: StudioPreset) -> String {
        let d = preset.parameters
        return Self.key(preset: preset, autotune: d.pitchCorrectionStrength,
                        reverb: d.reverbWet, noise: d.mlEnhanceDryWet, warmth: d.warmthGainDB)
    }

    private static func key(
        preset: StudioPreset, autotune: Double, reverb: Double,
        noise: Double, warmth: Double
    ) -> String {
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        return "\(preset.rawValue)|\(f(autotune))|\(f(reverb))|\(f(noise))|\(f(warmth))"
    }

    // MARK: - Progress

    private func registerMLProgress(_ fraction: Double) {
        lastMLFraction = fraction
        refreshProgress()
    }

    private func startProgressEstimator() {
        enhanceStart = Date()
        lastMLFraction = 0
        progressTicker?.cancel()
        progressTicker = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                guard case .enhancing = self.phase else { break }
                self.refreshProgress()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopProgressEstimator() {
        progressTicker?.cancel()
        progressTicker = nil
        enhanceStart = nil
    }

    /// Blends a time-based estimate (so the bar always moves) with the
    /// ML stage's real progress (≈60% of the work), capped below 1.
    private func refreshProgress() {
        guard case .enhancing = phase, let start = enhanceStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        let estimatedTotal = max(4.0, duration * 0.6)
        let timeEased = min(elapsed / estimatedTotal, 0.9)
        let mlEased = lastMLFraction * 0.6
        phase = .enhancing(max(timeEased, mlEased))
    }

    // MARK: - Off-main work

    @concurrent
    private static func render(
        originalURL: URL, parameters: PresetParameters, outputURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let stages = ProcessingPipeline.makeDefaultStages(parameters: parameters)
        for stage in stages {
            (stage as? MLEnhanceStage)?.progressHandler = onProgress
        }
        try ProcessingPipeline(stages: stages).process(fileAt: originalURL, to: outputURL)
    }

    @concurrent
    private static func loadMetadata(_ url: URL) async -> (peaks: [Float], duration: TimeInterval) {
        let meta = (try? RecordingMetadata.loadOrCompute(for: url)) ?? .empty()
        return (meta.peaks, meta.duration)
    }
}
