//
//  ResultViewModel.swift
//  HUMMI
//

import AVFoundation
import Foundation
import Observation

/// Deliberately conservative noise-cleanup presets. The upper bound is kept
/// below a fully-wet denoiser because fully replacing a singing voice with ML
/// output is where metallic consonants and warbling most often appear.
nonisolated enum NoiseReductionLevel: Double, CaseIterable, Identifiable {
    case off = 0
    case gentle = 0.22
    case balanced = 0.42
    case strong = 0.72

    var id: Double { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .gentle: "Gentle"
        case .balanced: "Balanced"
        case .strong: "Strong"
        }
    }

    var detail: String {
        switch self {
        case .off: "Original"
        case .gentle: "Soft room"
        case .balanced: "Everyday"
        case .strong: "Noisy room"
        }
    }
}

/// Owns the Studio session. Preview settings are applied to the live graph;
/// `renderFinalStudioVersion` is the sole path that runs the full pipeline.
@MainActor
@Observable
final class ResultViewModel {
    enum Phase: Equatable { case idle, enhancing(Double?), ready }

    let originalURL: URL
    var displayName: String
    private(set) var peaks: [Float] = []
    private(set) var duration: TimeInterval = 0
    private(set) var phase: Phase = .idle
    private(set) var isRendering = false
    private(set) var isSavingStudio = false
    var errorMessage: String?

    var selectedCharacterID = "studio"
    var selectedSpaceID = "studio-room"
    private(set) var filterTapCount = 0
    var autotuneStrength = 0.0
    var reverbAmount = 0.0
    /// 0…0.75. This feeds the actual DFN dry/wet blend used for both the
    /// Studio audition and the saved file; it is never a cosmetic control.
    var noiseRemoval = NoiseReductionLevel.off.rawValue
    var warmth = 0.0
    var voiceSpeed = 1.0
    var voiceTempo = 1.0
    var voicePitch = 0.0
    var eqLow = 0.0
    var eqMid = 0.0
    var eqHigh = 0.0
    var reverbDecay = 0.2
    var reverbPredelay = 0.0
    var saturation = 0.0

    let abPlayer = RealtimePreviewEngine()
    private(set) var isTuningPreview = false
    private var currentURL: URL?
    private var enhancedBaseURL: URL?
    private var progressTicker: Task<Void, Never>?
    private var autotunePreviewTask: Task<Void, Never>?
    private var noiseReductionTask: Task<Void, Never>?
    private var originalSamples: [Float]?
    private var noiseReducedSamples: [Float]?
    private var previewedAutotune = 0.0
    private var previewedNoiseRemoval = NoiseReductionLevel.off.rawValue
    private var noiseRenderRevision = 0
    private(set) var isUpdatingNoiseReduction = false
    private var enhanceStart: Date?
    private var lastMLFraction = 0.0

    private(set) var isExporting = false
    private(set) var videoProgress: Double?
    var shareItem: ShareItem?

    var selectedCharacter: CharacterFilter { FilterLibrary.character(id: selectedCharacterID) }
    var selectedSpace: SpaceFilter { FilterLibrary.space(id: selectedSpaceID) }
    var isVoiceShaped: Bool { voiceSpeed != 1 || voiceTempo != 1 || voicePitch != 0 }
    /// True when any Studio Panel slider has moved off the selected
    /// character/space preset — drives the "custom adjustments" badge.
    var isCustomized: Bool {
        let s = selectedCharacter.settings
        return eqLow != s.lowGain || eqMid != s.midGain || eqHigh != s.highGain
            || saturation != s.saturation || autotuneStrength != s.autotune
            || voicePitch != s.pitch || voiceSpeed != s.speed || voiceTempo != s.tempo
            || reverbAmount != selectedSpace.amount
    }
    /// Kept for the legacy voice-control component; adjustments now apply live.
    var isDirty: Bool { false }

    init(originalURL: URL) {
        self.originalURL = originalURL
        displayName = RecordingNames.name(for: originalURL)
        resetToPreset()
    }

    func onAppear() async {
        if peaks.isEmpty {
            let metadata = await Self.loadMetadata(originalURL)
            peaks = metadata.peaks; duration = metadata.duration
        }
        if !abPlayer.isLoaded {
            do { try abPlayer.load(original: originalURL, enhancedBase: originalURL) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func tearDown() {
        progressTicker?.cancel()
        autotunePreviewTask?.cancel()
        noiseReductionTask?.cancel()
        abPlayer.unload()
    }

    /// Opens Studio on the original audio. ML enhancement is deliberately
    /// excluded from the realtime path until it can pass device listening QA.
    func enhanceWithStudio() async { await prepareRealtimePreview() }

    func prepareRealtimePreview() async {
        guard !isRendering else { return }
        do {
            try abPlayer.load(original: originalURL, enhancedBase: originalURL)
            previewedAutotune = 0  // load replaced any autotuned studio buffer
            previewedNoiseRemoval = 0
            noiseReducedSamples = nil
            abPlayer.listeningToProcessed = true
            phase = .ready
            applyRealtimePreview()
        } catch { errorMessage = error.localizedDescription; phase = .idle }
    }

    func selectCharacter(_ id: String) {
        guard id != selectedCharacterID else { return }
        selectedCharacterID = id; filterTapCount += 1; resetCharacterControls()
        applyRealtimePreview(ramp: .milliseconds(150))  // musical, not clicky
    }

    func selectSpace(_ id: String) {
        guard id != selectedSpaceID else { return }
        selectedSpaceID = id; filterTapCount += 1; resetSpaceControls()
        applyRealtimePreview(ramp: .milliseconds(150))
    }

    func applyRealtimePreview(ramp: Duration = .milliseconds(60)) {
        currentURL = nil
        guard abPlayer.isLoaded else { return }
        // Panel sliders are absolute: selecting a character seeds them with
        // its values, so they replace the preset rather than stack on top
        // (stacking played Deep and Chipmunk at double their pitch shift).
        var settings = selectedCharacter.settings
        settings.lowGain = eqLow; settings.midGain = eqMid; settings.highGain = eqHigh
        settings.saturation = saturation; settings.pitch = voicePitch; settings.speed = voiceSpeed; settings.tempo = voiceTempo
        settings.autotune = autotuneStrength
        // Moving Decay off the space's own value overrides its room: the
        // Apple reverb has no decay parameter, so the nearest-sized factory
        // preset stands in. The id carries the override so the engine
        // reloads the preset only when the bucket actually changes.
        let space = selectedSpace
        let decayCustom = abs(reverbDecay - space.decay) > 0.05
        let preset = decayCustom ? Self.reverbPreset(forDecay: reverbDecay) : space.preset
        let spaceID = decayCustom ? "\(space.id)-decay\(preset.map { String($0.rawValue) } ?? "")" : space.id
        let liveSpace = SpaceFilter(id: spaceID, name: space.name, tagline: space.tagline, glyph: space.glyph,
                                    tile: space.tile, preset: preset, amount: reverbAmount,
                                    decay: reverbDecay, predelay: reverbPredelay)
        abPlayer.apply(character: settings, space: liveSpace, ramp: ramp)
        scheduleAutotunePreview()
    }

    /// Nearest-sized factory room for a decay time, smallest to largest.
    static func reverbPreset(forDecay decay: Double) -> AVAudioUnitReverbPreset {
        switch decay {
        case ..<0.5: .smallRoom
        case ..<1.0: .mediumRoom
        case ..<1.8: .largeRoom
        case ..<2.8: .largeHall
        default: .cathedral
        }
    }

    /// Autotune has no realtime AU, so the preview re-renders the studio
    /// buffer through PitchCorrectionStage in the background (debounced for
    /// slider drags) and hot-swaps it — this is what makes Hard Tune audible.
    private func scheduleAutotunePreview() {
        guard abs(autotuneStrength - previewedAutotune) > 0.001 else { return }
        autotunePreviewTask?.cancel()
        autotunePreviewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            self.isTuningPreview = true
            defer { self.isTuningPreview = false }
            do {
                let original = try await self.previewBaseSamples()
                let strength = self.autotuneStrength
                let tuned = strength > 0
                    ? try await Self.pitchCorrected(original, strength: strength)
                    : original
                guard !Task.isCancelled else { return }
                self.abPlayer.replaceStudioSamples(tuned)
                self.previewedAutotune = strength
            } catch {
                if !Task.isCancelled { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func cachedOriginalSamples() async throws -> [Float] {
        if let originalSamples { return originalSamples }
        let samples = try await Self.loadSamples(from: originalURL)
        originalSamples = samples
        return samples
    }

    /// Changes the cleanup setting and schedules one debounced offline ML
    /// pass. Rendering only at the end of a slider gesture avoids a backlog
    /// of Core ML work while the user drags.
    func selectNoiseReduction(_ level: NoiseReductionLevel) {
        noiseRemoval = level.rawValue
        scheduleNoiseReductionPreview()
    }

    func scheduleNoiseReductionPreview() {
        guard abPlayer.isLoaded else { return }
        noiseRenderRevision += 1
        let revision = noiseRenderRevision
        let requestedStrength = noiseRemoval
        noiseReductionTask?.cancel()
        noiseReductionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            self.isUpdatingNoiseReduction = true
            defer {
                if self.noiseRenderRevision == revision {
                    self.isUpdatingNoiseReduction = false
                }
            }
            do {
                let original = try await self.cachedOriginalSamples()
                let reduced = try await Self.reduceNoise(original, strength: requestedStrength)
                guard !Task.isCancelled, self.noiseRenderRevision == revision else { return }
                self.noiseReducedSamples = requestedStrength > 0 ? reduced : nil
                self.previewedNoiseRemoval = requestedStrength

                let base = self.noiseReducedSamples ?? original
                let studio = self.autotuneStrength > 0
                    ? try await Self.pitchCorrected(base, strength: self.autotuneStrength)
                    : base
                guard !Task.isCancelled, self.noiseRenderRevision == revision else { return }
                self.abPlayer.replaceStudioSamples(studio)
                self.previewedAutotune = self.autotuneStrength
            } catch {
                guard !Task.isCancelled, self.noiseRenderRevision == revision else { return }
                self.errorMessage = "Noise cleanup could not be applied: \(error.localizedDescription)"
            }
        }
    }

    private func previewBaseSamples() async throws -> [Float] {
        if abs(previewedNoiseRemoval - noiseRemoval) < 0.001,
           let noiseReducedSamples {
            return noiseReducedSamples
        }
        return try await cachedOriginalSamples()
    }

    func resetToPreset() {
        resetCharacterControls()
        resetSpaceControls()
        noiseRemoval = NoiseReductionLevel.off.rawValue
        scheduleNoiseReductionPreview()
    }

    func resetVoiceShape() { voiceSpeed = 1; voiceTempo = 1; voicePitch = 0; applyRealtimePreview() }

    func applyAdjustments() async { applyRealtimePreview() }

    func renderFinalStudioVersion() async -> Bool {
        guard !isSavingStudio else { return false }
        isSavingStudio = true
        // No toast here: every caller (Studio's Save, the export screen's
        // Save Audio / Share Video) drives its own status strip around this
        // call, so showing one here would double up.
        defer { isSavingStudio = false }
        do {
            if abs(previewedNoiseRemoval - noiseRemoval) > 0.001 {
                scheduleNoiseReductionPreview()
            }
            if let pending = noiseReductionTask { await pending.value }
            // The export renders the studio buffer, so a pending autotune
            // preview must land first or the save would miss it.
            scheduleAutotunePreview()
            if let pending = autotunePreviewTask { await pending.value }
            let destination = try EnhancementStore.url(for: originalURL, preset: .studio)
            try await abPlayer.exportOffline(to: destination)
            currentURL = destination
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func commitName() { RecordingNames.setName(displayName, for: originalURL) }

    func saveAudio() async {
        guard !isExporting else { return }
        if currentURL == nil, !(await renderFinalStudioVersion()) { return }
        guard let currentURL else { return }
        isExporting = true; defer { isExporting = false }
        ToastManager.shared.show(message: "Preparing audio...", isProcessing: true)
        do {
            let format = UserDefaults.standard.string(forKey: "exportFormat") ?? ExportFormat.m4a.rawValue
            let output = exportURL(extension: format == ExportFormat.wav.rawValue ? "wav" : "m4a")
            try? FileManager.default.removeItem(at: output)
            if format == ExportFormat.wav.rawValue { try FileManager.default.copyItem(at: currentURL, to: output) }
            else { try await AudioExporter.exportM4A(from: currentURL, to: output) }
            shareItem = ShareItem(url: output)
            ToastManager.shared.show(message: "Audio prepared", icon: "checkmark.circle.fill")
        } catch { 
            errorMessage = error.localizedDescription 
            ToastManager.shared.hide()
        }
    }

    func shareVideo() async {
        guard !isExporting else { return }
        if currentURL == nil, !(await renderFinalStudioVersion()) { return }
        guard let currentURL else { return }
        isExporting = true; videoProgress = 0
        defer { isExporting = false; videoProgress = nil }
        ToastManager.shared.show(message: "Preparing video...", isProcessing: true)
        do {
            let templateRaw = UserDefaults.standard.string(forKey: "videoTemplate") ?? VideoTemplate.voiceNote.rawValue
            let template = VideoTemplate(rawValue: templateRaw) ?? .voiceNote
            let output = exportURL(extension: "mp4")
            try await VideoExporter.exportMP4(audioURL: currentURL, peaks: peaks, duration: duration,
                                               watermark: false, template: template, to: output) { [weak self] progress in
                Task { @MainActor in self?.videoProgress = progress }
            }
            shareItem = ShareItem(url: output)
            ToastManager.shared.show(message: "Video prepared", icon: "checkmark.circle.fill")
        } catch { 
            errorMessage = error.localizedDescription 
            ToastManager.shared.hide()
        }
    }

    private func resetCharacterControls() {
        let settings = selectedCharacter.settings
        autotuneStrength = settings.autotune; saturation = settings.saturation
        voiceSpeed = settings.speed; voiceTempo = settings.tempo; voicePitch = settings.pitch
        eqLow = settings.lowGain; eqMid = settings.midGain; eqHigh = settings.highGain
        warmth = settings.lowGain
    }

    private func resetSpaceControls() {
        let space = selectedSpace
        reverbAmount = space.amount; reverbDecay = space.decay; reverbPredelay = space.predelay
    }

    private func offlineParameters() -> PresetParameters {
        var p = StudioPreset.studio.parameters
        p.mlEnhanceDryWet = 1; p.warmthGainDB = eqLow
        p.presenceGainDB = eqMid
        p.airGainDB = eqHigh
        p.saturationBlend = min(max(saturation / 100, 0), 1)
        p.pitchCorrectionStrength = autotuneStrength; p.reverbWet = min(max(reverbAmount / 100, 0), 0.7)
        p.voiceSpeed = voiceSpeed; p.voiceTempo = voiceTempo; p.voicePitchSemitones = voicePitch
        return p
    }

    private func createEnhancedBase(at output: URL) async throws {
        isRendering = true; phase = .enhancing(nil); startProgress()
        defer { isRendering = false; stopProgress() }
        try await Self.renderBase(originalURL: originalURL, outputURL: output) { [weak self] fraction in
            Task { @MainActor in self?.lastMLFraction = fraction }
        }
    }

    private func startProgress() {
        enhanceStart = .now
        progressTicker = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isRendering {
                let elapsed = Date().timeIntervalSince(self.enhanceStart ?? .now)
                self.phase = .enhancing(min(max(self.lastMLFraction * 0.8, elapsed / max(4, self.duration * 0.6)), 0.95))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopProgress() { progressTicker?.cancel(); progressTicker = nil; enhanceStart = nil }

    private func exportURL(extension ext: String) -> URL {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(name.isEmpty ? AppBranding.name : name).\(ext)")
    }

    @concurrent private static func renderBase(originalURL: URL, outputURL: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        var p = PresetParameters(); p.mlEnhanceDryWet = 1; p.normalizePeakCeilingDB = -3
        let stage = MLEnhanceStage(parameters: p); stage.progressHandler = onProgress
        let samples = try AudioClipIO.loadMono48k(from: originalURL)
        let enhanced = try stage.process(samples)
        let safe = try LoudnessNormalizeStage(parameters: p).process(enhanced)
        try AudioClipIO.writeWAV(safe, to: outputURL)
    }

    @concurrent private static func render(originalURL: URL, parameters: PresetParameters, outputURL: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let stages = ProcessingPipeline.makeDefaultStages(parameters: parameters)
        stages.compactMap { $0 as? MLEnhanceStage }.forEach { $0.progressHandler = onProgress }
        try ProcessingPipeline(stages: stages).process(fileAt: originalURL, to: outputURL)
    }

    @concurrent private static func loadSamples(from url: URL) async throws -> [Float] {
        try AudioClipIO.loadMono48k(from: url)
    }

    @concurrent private static func pitchCorrected(_ samples: [Float], strength: Double) async throws -> [Float] {
        var p = PresetParameters()
        p.pitchCorrectionStrength = strength
        return try PitchCorrectionStage(parameters: p).process(samples)
    }

    @concurrent private static func reduceNoise(_ samples: [Float], strength: Double) async throws -> [Float] {
        guard strength > 0 else { return samples }
        var parameters = PresetParameters.default
        parameters.mlEnhanceDryWet = min(max(strength, 0), NoiseReductionLevel.strong.rawValue)
        parameters.mlVocalWetCeiling = 0.55
        return try MLEnhanceStage(parameters: parameters).process(samples)
    }

    @concurrent private static func loadMetadata(_ url: URL) async -> (peaks: [Float], duration: TimeInterval) {
        let metadata = (try? RecordingMetadata.loadOrCompute(for: url)) ?? .empty()
        return (metadata.peaks, metadata.duration)
    }
}

extension ResultViewModel: Hashable {
    nonisolated static func == (lhs: ResultViewModel, rhs: ResultViewModel) -> Bool {
        return lhs === rhs
    }
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
