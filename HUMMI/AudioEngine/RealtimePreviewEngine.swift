//
//  RealtimePreviewEngine.swift
//  HUMMI
//

import AVFoundation
import Observation

/// A position-synchronised A/B player whose Studio path stays in an
/// AVAudioEngine graph. Filter changes only update AU parameters; the only
/// offline work is creating the ML-cleaned base and the final saved render.
@MainActor
@Observable
final class RealtimePreviewEngine {
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var listeningToProcessed = false { didSet { updateABVolumes() } }

    private let engine = AVAudioEngine()
    private let originalPlayer = AVAudioPlayerNode()
    private let studioPlayer = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let distortion = AVAudioUnitDistortion()
    private let reverb = AVAudioUnitReverb()
    /// Unity-gain trim on the wet path. Never set above 1: boosting after
    /// the reverb pushed EQ-boosted peaks over full scale and the output
    /// hard-clipped (crackle on loud notes). A distorted "limiter" here
    /// made every Studio preview sound broken, so headroom comes from the
    /// player volume instead.
    private let safetyGain = AVAudioMixerNode()
    private var format: AVAudioFormat?
    private var originalBuffer: AVAudioPCMBuffer?
    private var studioBuffer: AVAudioPCMBuffer?
    private var frameLength: AVAudioFrameCount = 0
    private var seekOffset: TimeInterval = 0
    private var isScrubbing = false
    private var ticker: Task<Void, Never>?
    private var rampTask: Task<Void, Never>?
    private var loadedSpaceID: String?
    private var loadedReverbPreset: AVAudioUnitReverbPreset?
    /// The last values handed to `apply` — what the export should render
    /// even if a ramp toward them is still in flight.
    private var targetValues: PreviewValues?

    func load(original originalURL: URL, enhancedBase baseURL: URL) throws {
        unload()
        let original = try AudioClipIO.loadMono48k(from: originalURL)
        let base = try AudioClipIO.loadMono48k(from: baseURL)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: DFNContract.sampleRate,
                                         channels: 2, interleaved: false),
              let originalBuffer = Self.buffer(from: original, format: format),
              let studioBuffer = Self.buffer(from: base, format: format)
        else { throw DFNError.audioFile("could not prepare preview audio") }

        [originalPlayer, studioPlayer, timePitch, eq, distortion, reverb, safetyGain].forEach(engine.attach)
        engine.connect(originalPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(studioPlayer, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: distortion, format: format)
        engine.connect(distortion, to: reverb, format: format)
        engine.connect(reverb, to: safetyGain, format: format)
        engine.connect(safetyGain, to: engine.mainMixerNode, format: format)
        configureStaticNodes()
        self.format = format
        self.originalBuffer = originalBuffer
        self.studioBuffer = studioBuffer
        frameLength = max(originalBuffer.frameLength, studioBuffer.frameLength)
        duration = Double(frameLength) / DFNContract.sampleRate
        updateABVolumes()
        engine.prepare()
        isLoaded = true
    }

    func apply(character: RealtimePreviewSettings, space: SpaceFilter, ramp: Duration = .milliseconds(120)) {
        rampTask?.cancel()
        if loadedSpaceID != space.id {
            if let preset = space.preset { reverb.loadFactoryPreset(preset) }
            loadedSpaceID = space.id
            loadedReverbPreset = space.preset
        }
        let start = currentValues
        let target = PreviewValues(character: character, space: space)
        targetValues = target
        rampTask = Task { @MainActor [weak self] in
            for step in 1...6 where !Task.isCancelled {
                self?.setValues(start.interpolated(to: target, amount: Double(step) / 6))
                try? await Task.sleep(for: ramp / 6)
            }
        }
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func play() {
        guard isLoaded, !isPlaying else { return }
        do {
            try AudioSessionManager.configureForPlayback()
            if !engine.isRunning { try engine.start() }
        } catch { return }
        if currentTime >= duration - 0.02 { currentTime = 0 }
        startSegment(from: currentTime)
        isPlaying = true
        startTicker()
    }

    func pause() {
        guard isPlaying else { return }
        currentTime = playheadNow()
        originalPlayer.stop(); studioPlayer.stop()
        isPlaying = false
        ticker?.cancel()
    }

    func setScrubbing(_ scrubbing: Bool) { isScrubbing = scrubbing; if !scrubbing { seek(to: currentTime) } }

    func seek(to time: TimeInterval) {
        currentTime = min(max(time, 0), max(duration - 0.001, 0))
        if isPlaying { startSegment(from: currentTime) }
    }

    /// Swaps in a re-rendered studio take (the autotuned preview) without
    /// touching the original side; playback resumes from the same spot.
    func replaceStudioSamples(_ samples: [Float]) {
        guard isLoaded, let format,
              let buffer = Self.buffer(from: samples, format: format) else { return }
        studioBuffer = buffer
        frameLength = max(originalBuffer?.frameLength ?? 0, buffer.frameLength)
        duration = Double(frameLength) / DFNContract.sampleRate
        if isPlaying { startSegment(from: playheadNow()) }
    }

    func unload() {
        rampTask?.cancel(); ticker?.cancel()
        originalPlayer.stop(); studioPlayer.stop(); engine.stop()
        [originalPlayer, studioPlayer, timePitch, eq, distortion, reverb, safetyGain]
            .filter { engine.attachedNodes.contains($0) }.forEach(engine.detach)
        originalBuffer = nil; studioBuffer = nil; format = nil
        loadedSpaceID = nil; loadedReverbPreset = nil; targetValues = nil
        frameLength = 0; duration = 0; currentTime = 0; isPlaying = false; isLoaded = false
    }

    /// Renders the studio path (same node settings as the live preview,
    /// including any autotuned buffer) faster than realtime off the main
    /// thread, then loudness-normalizes to the app target and writes the
    /// app-internal 48 kHz mono WAV.
    func exportOffline(to outputURL: URL) async throws {
        guard isLoaded, let studioBuffer else {
            throw DFNError.audioFile("the studio preview is not loaded")
        }
        let samples = Self.monoSamples(of: studioBuffer)
        let values = targetValues ?? currentValues
        let reverbPreset = loadedReverbPreset
        try await Self.renderStudioChain(
            samples: samples, values: values, reverbPreset: reverbPreset, to: outputURL)
    }

    @concurrent private static func renderStudioChain(
        samples: [Float], values: PreviewValues,
        reverbPreset: AVAudioUnitReverbPreset?, to outputURL: URL
    ) async throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: DFNContract.sampleRate,
                                         channels: 2, interleaved: false),
              let input = buffer(from: samples, format: format) else {
            throw DFNError.audioFile("could not prepare the export buffer")
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let distortion = AVAudioUnitDistortion()
        let reverb = AVAudioUnitReverb()
        [player, timePitch, eq, distortion, reverb].forEach(engine.attach)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: distortion, format: format)
        engine.connect(distortion, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        configureStaticNodes(timePitch: timePitch, eq: eq, distortion: distortion, reverb: reverb)
        if let reverbPreset { reverb.loadFactoryPreset(reverbPreset) }
        configure(values, timePitch: timePitch, eq: eq, distortion: distortion, reverb: reverb)

        let rate = timePitch.bypass ? 1.0 : Double(timePitch.rate)
        let targetFrames = max(Int((Double(samples.count) / rate).rounded()), 1)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
        try engine.start()
        defer { engine.stop() }
        player.scheduleBuffer(input, at: nil, options: [], completionHandler: nil)
        player.play()

        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
            throw DFNError.audioFile("could not allocate the export render buffer")
        }
        var output: [Float] = []
        output.reserveCapacity(targetFrames)
        while output.count < targetFrames {
            let remaining = AVAudioFrameCount(targetFrames - output.count)
            switch try engine.renderOffline(min(4_096, remaining), to: chunk) {
            case .success:
                guard let data = chunk.floatChannelData else {
                    throw DFNError.audioFile("export render produced no channel data")
                }
                for i in 0..<Int(chunk.frameLength) {  // downmix back to mono
                    output.append((data[0][i] + data[1][i]) * 0.5)
                }
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw DFNError.audioFile("offline export failed")
            @unknown default:
                throw DFNError.audioFile("offline export failed")
            }
        }
        let normalized = try LoudnessNormalizeStage(parameters: .default).process(output)
        try AudioClipIO.writeWAV(normalized, to: outputURL)
    }

    /// Inverse of `configure`'s mappings — the AU stores pitch in cents and
    /// saturation as a scaled wet-mix percent. Ramps start from these, so
    /// the units must round-trip (raw AU values made every ramp lurch).
    private var currentValues: PreviewValues {
        PreviewValues(low: Double(eq.bands[0].gain), mid: Double(eq.bands[1].gain), high: Double(eq.bands[2].gain),
                      saturation: Double(distortion.wetDryMix) * 5, pitch: Double(timePitch.pitch) / 100,
                      rate: Double(timePitch.rate), wet: Double(reverb.wetDryMix))
    }

    private func configureStaticNodes() {
        Self.configureStaticNodes(timePitch: timePitch, eq: eq, distortion: distortion, reverb: reverb)
        safetyGain.outputVolume = 1.0
    }

    private nonisolated static func configureStaticNodes(
        timePitch: AVAudioUnitTimePitch, eq: AVAudioUnitEQ,
        distortion: AVAudioUnitDistortion, reverb: AVAudioUnitReverb
    ) {
        eq.bands[0].filterType = .lowShelf; eq.bands[0].frequency = 100; eq.bands[0].bypass = false
        eq.bands[1].filterType = .parametric; eq.bands[1].frequency = 1_000; eq.bands[1].bandwidth = 1; eq.bands[1].bypass = false
        eq.bands[2].filterType = .highShelf; eq.bands[2].frequency = 8_000; eq.bands[2].bypass = false
        // Cubed soft-clip is the closest AU to the offline chain's gentle
        // parallel tanh; the squared preset crackled like a blown speaker
        // even at low wet mixes. preGain stays at the AU's -6 dB default —
        // raising it drives the waveshaper into audible breakup.
        distortion.loadFactoryPreset(.multiDistortedCubed)
        distortion.preGain = -6
        distortion.wetDryMix = 0
        distortion.bypass = true
        reverb.bypass = true
        timePitch.bypass = true
    }

    private func setValues(_ values: PreviewValues) {
        Self.configure(values, timePitch: timePitch, eq: eq, distortion: distortion, reverb: reverb)
    }

    /// One mapping from user-facing values to AU parameters, shared by the
    /// live preview and the export render so they cannot drift apart.
    private nonisolated static func configure(
        _ values: PreviewValues, timePitch: AVAudioUnitTimePitch, eq: AVAudioUnitEQ,
        distortion: AVAudioUnitDistortion, reverb: AVAudioUnitReverb
    ) {
        let hasEQ = abs(values.low) > 0.01 || abs(values.mid) > 0.01 || abs(values.high) > 0.01
        eq.bypass = !hasEQ
        if hasEQ {
            eq.bands[0].gain = Float(values.low)
            eq.bands[1].gain = Float(values.mid)
            eq.bands[2].gain = Float(values.high)
        }

        if values.saturation > 0.01 {
            distortion.bypass = false
            distortion.wetDryMix = Float(min(values.saturation * 0.2, 12))
        } else {
            distortion.bypass = true
        }

        if abs(values.pitch) > 0.01 || abs(values.rate - 1.0) > 0.01 {
            timePitch.bypass = false
            timePitch.pitch = Float(values.pitch * 100)
            timePitch.rate = Float(values.rate)
        } else {
            timePitch.bypass = true
        }

        if values.wet > 0.01 {
            reverb.bypass = false
            reverb.wetDryMix = Float(values.wet)
        } else {
            reverb.bypass = true
        }
    }

    // 0.6 leaves ~4 dB of headroom for the character EQ boosts so the
    // studio path cannot clip the output, while staying loud enough to
    // A/B against the original.
    private func updateABVolumes() { originalPlayer.volume = listeningToProcessed ? 0 : 1; studioPlayer.volume = listeningToProcessed ? 0.6 : 0 }

    private func startSegment(from time: TimeInterval) {
        guard let originalBuffer, let studioBuffer, let format, frameLength > 0 else { return }
        originalPlayer.stop(); studioPlayer.stop()
        var frame = AVAudioFrameCount(max(0, time * DFNContract.sampleRate)); if frame >= frameLength { frame = 0 }
        let when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.08))
        for (player, buffer) in [(originalPlayer, originalBuffer), (studioPlayer, studioBuffer)] {
            if frame > 0, let tail = Self.tail(buffer, from: frame, format: format) { player.scheduleBuffer(tail, at: nil) }
            player.scheduleBuffer(buffer, at: nil, options: .loops); player.play(at: when)
        }
        seekOffset = time
    }

    private func playheadNow() -> TimeInterval {
        guard duration > 0, let nodeTime = originalPlayer.lastRenderTime, nodeTime.isSampleTimeValid,
              let time = originalPlayer.playerTime(forNodeTime: nodeTime) else { return currentTime }
        return (seekOffset + Double(time.sampleTime) / time.sampleRate).truncatingRemainder(dividingBy: duration)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                if !self.isScrubbing { self.currentTime = self.playheadNow() }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Channel 0 of a preview buffer — both channels hold the same mono take.
    private nonisolated static func monoSamples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }

    private nonisolated static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData else { return nil }
        let channels = Int(format.channelCount)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                for ch in 0..<channels {
                    channel[ch].update(from: base, count: samples.count)
                }
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count); return buffer
    }

    private static func tail(_ buffer: AVAudioPCMBuffer, from frame: AVAudioFrameCount, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > frame, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength - frame),
              let source = buffer.floatChannelData, let destination = out.floatChannelData else { return nil }
        let count = buffer.frameLength - frame
        let channels = Int(format.channelCount)
        for ch in 0..<channels {
            destination[ch].update(from: source[ch].advanced(by: Int(frame)), count: Int(count))
        }
        out.frameLength = count; return out
    }
}

private struct PreviewValues {
    var low: Double = 0; var mid: Double = 0; var high: Double = 0; var saturation: Double = 0
    var pitch: Double = 0; var rate: Double = 1; var wet: Double = 0
    init(character: RealtimePreviewSettings, space: SpaceFilter) {
        low = character.lowGain; mid = character.midGain; high = character.highGain; saturation = character.saturation
        // Speed is varispeed, like tape: the offline VoiceShapeStage resamples,
        // shifting pitch with it, so the preview adds the matching pitch shift.
        let speed = max(character.speed, 0.01)
        pitch = character.pitch + 12 * log2(speed)
        rate = speed * character.tempo
        wet = space.amount
    }
    init(low: Double, mid: Double, high: Double, saturation: Double, pitch: Double, rate: Double, wet: Double) {
        self.low = low; self.mid = mid; self.high = high; self.saturation = saturation; self.pitch = pitch; self.rate = rate; self.wet = wet
    }
    func interpolated(to target: PreviewValues, amount: Double) -> PreviewValues {
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * amount }
        return .init(low: lerp(low, target.low), mid: lerp(mid, target.mid), high: lerp(high, target.high), saturation: lerp(saturation, target.saturation), pitch: lerp(pitch, target.pitch), rate: lerp(rate, target.rate), wet: lerp(wet, target.wet))
    }
}
