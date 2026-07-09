//
//  Recorder.swift
//  HUMMI
//

import AVFoundation
import Accelerate

/// Records the microphone to a Float32 48 kHz mono WAV file in
/// Documents/Recordings/ via an AVAudioEngine input tap, converting from
/// the hardware format when it differs. Route changes are survived by
/// restarting the engine against the new input format into the same file;
/// interruptions and unrecoverable changes finalize the file, so a partial
/// recording is always playable.
///
/// `start()`/`stop()` are main-actor; the tap callback writes from the
/// capture thread, with shared state guarded by `lock`.
nonisolated final class Recorder: @unchecked Sendable {
    /// Level/elapsed updates, ~20×/sec while recording. Main actor.
    var onLevels: (@MainActor @Sendable (_ rms: Float, _ peak: Float, _ elapsed: TimeInterval) -> Void)?
    /// The recorder stopped on its own; the finalized file is at the URL.
    var onAutoStop: (@MainActor @Sendable (RecorderStopReason, URL) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    // Guarded by `lock`:
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var converter: AVAudioConverter?
    private var framesWritten: AVAudioFramePosition = 0
    private var pendingWriteFailure = false

    private var observers: [NSObjectProtocol] = []

    var isRecording: Bool {
        lock.withLock { file != nil }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        engine.stop()
        lock.withLock {
            file?.close()
            file = nil
        }
    }

    // MARK: - Control (main actor)

    /// Starts a new recording and returns the destination file URL.
    @MainActor
    func start() throws -> URL {
        guard !isRecording else { throw RecorderError.alreadyRecording }

        // Configure session for recording
        try AudioSessionManager.configureForRecording()

        let url = try RecordingLibrary.newRecordingURL()
        let newFile = try AVAudioFile(
            forWriting: url, settings: AudioClipIO.wavSettings48kMono(),
            commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.withLock {
            file = newFile
            fileURL = url
            framesWritten = 0
            pendingWriteFailure = false
        }

        do {
            try attachTapAndStartEngine()
        } catch {
            lock.withLock {
                file?.close()
                file = nil
                fileURL = nil
            }
            try? FileManager.default.removeItem(at: url)
            try? AudioSessionManager.configureForPlayback() // Switch back to playback category on failure
            throw error
        }
        observeWhileRecording()
        return url
    }

    /// Stops and finalizes the recording, returning the file URL.
    @MainActor
    @discardableResult
    func stop() -> URL? {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = lock.withLock { () -> URL? in
            guard let finishedFile = file else { return nil }
            finishedFile.close()
            let url = fileURL
            file = nil
            fileURL = nil
            converter = nil
            return url
        }

        // Restore session to playback mode
        try? AudioSessionManager.configureForPlayback()

        return url
    }

    // MARK: - Engine

    @MainActor
    private func attachTapAndStartEngine() throws {
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw RecorderError.noInputAvailable
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: DFNContract.sampleRate,
            channels: 1, interleaved: false
        ) else {
            throw RecorderError.unsupportedInputFormat("no 48 kHz mono format")
        }

        let needsConversion = hardwareFormat.sampleRate != targetFormat.sampleRate
            || hardwareFormat.channelCount != 1
            || hardwareFormat.commonFormat != .pcmFormatFloat32
        var newConverter: AVAudioConverter?
        if needsConversion {
            guard let created = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
                throw RecorderError.unsupportedInputFormat(
                    "\(Int(hardwareFormat.sampleRate)) Hz, \(hardwareFormat.channelCount) ch")
            }
            newConverter = created
        }
        lock.withLock { converter = newConverter }

        // ~2400 frames ≈ 50 ms at 48 kHz → ~20 level updates per second.
        input.installTap(onBus: 0, bufferSize: 2400, format: nil) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// Tap thread: convert if needed, append to the file, report levels.
    private func consume(_ buffer: AVAudioPCMBuffer) {
        var failureDetail: String?
        var levels: (rms: Float, peak: Float, elapsed: TimeInterval)?

        lock.withLock {
            guard let file, !pendingWriteFailure else { return }
            let outputBuffer: AVAudioPCMBuffer
            if let converter {
                guard let converted = Self.convert(buffer, with: converter) else {
                    pendingWriteFailure = true
                    failureDetail = "could not convert the microphone audio"
                    return
                }
                outputBuffer = converted
            } else {
                outputBuffer = buffer
            }
            do {
                try file.write(from: outputBuffer)
                framesWritten += AVAudioFramePosition(outputBuffer.frameLength)
                let (rms, peak) = Self.levels(of: outputBuffer)
                levels = (rms, peak, Double(framesWritten) / DFNContract.sampleRate)
            } catch {
                pendingWriteFailure = true
                failureDetail = error.localizedDescription
            }
        }

        if let levels {
            Task { @MainActor [onLevels] in
                onLevels?(levels.rms, levels.peak, levels.elapsed)
            }
        }
        if let failureDetail {
            Task { @MainActor in
                self.autoStop(.writeFailed(failureDetail))
            }
        }
    }

    // MARK: - Session events

    @MainActor
    private func observeWhileRecording() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
            let selfForTask = self
            Task { @MainActor in
                selfForTask?.autoStop(.interrupted)
            }
        })
        // Posted when a route change forces the engine to reconfigure
        // (for example, headphones plugged in or unplugged).
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            let selfForTask = self
            Task { @MainActor in
                selfForTask?.handleConfigurationChange()
            }
        })
    }

    /// Keep recording into the same file with a rebuilt tap/converter for
    /// the new input format; stop gracefully if the engine won't restart.
    @MainActor
    private func handleConfigurationChange() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try attachTapAndStartEngine()
        } catch {
            autoStop(.routeChangeFailed(error.localizedDescription))
        }
    }

    @MainActor
    private func autoStop(_ reason: RecorderStopReason) {
        guard isRecording else { return }
        if let url = stop() {
            onAutoStop?(reason, url)
        }
    }

    // MARK: - Helpers

    private static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter
    ) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat, frameCapacity: capacity
        ) else { return nil }

        var inputConsumed = false
        var conversionError: NSError?
        // .noDataNow (not .endOfStream) keeps the converter's resampler
        // state alive for the next tap buffer.
        converter.convert(to: output, error: &conversionError) { _, status in
            if inputConsumed {
                status.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            status.pointee = .haveData
            return buffer
        }
        return conversionError == nil ? output : nil
    }

    private static func levels(of buffer: AVAudioPCMBuffer) -> (rms: Float, peak: Float) {
        guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else {
            return (0, 0)
        }
        let samples = UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength))
        return (vDSP.rootMeanSquare(samples), vDSP.maximumMagnitude(samples))
    }

}
