//
//  ABPlayer.swift
//  HUMMI
//

import AVFoundation
import Observation

/// Plays two renditions of the same take in lockstep for A/B comparison:
/// both are scheduled on parallel player nodes sharing one engine clock,
/// so the A/B switch is a volume swap — instant, at the exact same
/// playback position. Adds transport: play/pause, a scrubber, and
/// seeking (both players are rescheduled together so they stay
/// sample-aligned). Playback loops so you can listen indefinitely.
@MainActor
@Observable
final class ABPlayer {
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    /// Playhead in seconds. Settable so a Slider can bind to it while
    /// scrubbing; the seek happens when scrubbing ends.
    var currentTime: TimeInterval = 0

    /// false = original (A), true = processed (B).
    var listeningToProcessed = false {
        didSet {
            originalPlayer.volume = listeningToProcessed ? 0 : 1
            processedPlayer.volume = listeningToProcessed ? 1 : 0
        }
    }

    private let engine = AVAudioEngine()
    private let originalPlayer = AVAudioPlayerNode()
    private let processedPlayer = AVAudioPlayerNode()

    private var format: AVAudioFormat?
    private var originalBuffer: AVAudioPCMBuffer?
    private var processedBuffer: AVAudioPCMBuffer?
    private var frameLength: AVAudioFrameCount = 0

    private var seekOffset: TimeInterval = 0   // clip position the segment began at
    private var isScrubbing = false
    private var ticker: Task<Void, Never>?

    func load(original originalURL: URL, processed processedURL: URL) throws {
        unload()

        let originalSamples = try AudioClipIO.loadMono48k(from: originalURL)
        let processedSamples = try AudioClipIO.loadMono48k(from: processedURL)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: DFNContract.sampleRate,
            channels: 1, interleaved: false
        ),
            let originalBuffer = Self.buffer(from: originalSamples, format: format),
            let processedBuffer = Self.buffer(from: processedSamples, format: format)
        else {
            throw DFNError.audioFile("could not prepare the A/B buffers")
        }

        engine.attach(originalPlayer)
        engine.attach(processedPlayer)
        engine.connect(originalPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(processedPlayer, to: engine.mainMixerNode, format: format)
        originalPlayer.volume = listeningToProcessed ? 0 : 1
        processedPlayer.volume = listeningToProcessed ? 1 : 0

        self.format = format
        self.originalBuffer = originalBuffer
        self.processedBuffer = processedBuffer
        frameLength = min(originalBuffer.frameLength, processedBuffer.frameLength)
        duration = Double(frameLength) / DFNContract.sampleRate
        currentTime = 0
        engine.prepare()
        isLoaded = true
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard isLoaded, !isPlaying else { return }
        do {
            try AudioSessionManager.configureForPlayback()
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        if currentTime >= duration - 0.02 { currentTime = 0 }  // replay from top
        startSegment(from: currentTime)
        isPlaying = true
        startTicker()
    }

    func pause() {
        guard isPlaying else { return }
        currentTime = playheadNow()
        originalPlayer.stop()
        processedPlayer.stop()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    /// Slider editing state: while true the ticker leaves `currentTime`
    /// alone; on release we seek to the scrubbed position.
    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if !scrubbing { seek(to: currentTime) }
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(time, 0), max(duration - 0.001, 0))
        currentTime = clamped
        if isPlaying { startSegment(from: clamped) }
    }

    func unload() {
        ticker?.cancel()
        ticker = nil
        originalPlayer.stop()
        processedPlayer.stop()
        engine.stop()
        if engine.attachedNodes.contains(originalPlayer) { engine.detach(originalPlayer) }
        if engine.attachedNodes.contains(processedPlayer) { engine.detach(processedPlayer) }
        originalBuffer = nil
        processedBuffer = nil
        frameLength = 0
        duration = 0
        currentTime = 0
        isPlaying = false
        isLoaded = false
    }

    // MARK: - Segment scheduling

    /// Reschedules both players to play from `time`: a tail buffer
    /// `[frame, end]` once, then the full buffer looping, both starting
    /// at one shared host time so they stay sample-locked. (AVAudioPlayer-
    /// Node has no mid-buffer start, so the tail is a copied sub-buffer.)
    private func startSegment(from time: TimeInterval) {
        guard let originalBuffer, let processedBuffer, let format, frameLength > 0 else { return }
        originalPlayer.stop()
        processedPlayer.stop()

        var frame = AVAudioFrameCount(max(0, time * DFNContract.sampleRate))
        if frame >= frameLength { frame = 0 }

        let start = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.08)
        let when = AVAudioTime(hostTime: start)
        for (player, buffer) in [(originalPlayer, originalBuffer), (processedPlayer, processedBuffer)] {
            if frame > 0, let tail = Self.tailBuffer(buffer, fromFrame: frame, format: format) {
                player.scheduleBuffer(tail, at: nil)
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play(at: when)
        }
        seekOffset = time
    }

    /// A copy of `buffer` from `frame` to the end.
    private static func tailBuffer(
        _ buffer: AVAudioPCMBuffer, fromFrame frame: AVAudioFrameCount, format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let count = buffer.frameLength - frame
        guard count > 0,
            let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
            let source = buffer.floatChannelData, let destination = out.floatChannelData
        else { return nil }
        destination[0].update(from: source[0].advanced(by: Int(frame)), count: Int(count))
        out.frameLength = count
        return out
    }

    /// Current playhead, driven by the player node's own render clock
    /// (`sampleTime` is samples rendered since this segment's `play`),
    /// wrapped for looping. Returns the last known value until the node
    /// starts rendering.
    private func playheadNow() -> TimeInterval {
        guard duration > 0,
            let nodeTime = originalPlayer.lastRenderTime,
            nodeTime.isSampleTimeValid,
            let playerTime = originalPlayer.playerTime(forNodeTime: nodeTime)
        else { return currentTime }
        let rate = playerTime.sampleRate > 0 ? playerTime.sampleRate : DFNContract.sampleRate
        let elapsed = max(0, Double(playerTime.sampleTime) / rate)
        return (seekOffset + elapsed).truncatingRemainder(dividingBy: duration)
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

    private static func buffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel[0].update(from: base, count: samples.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
