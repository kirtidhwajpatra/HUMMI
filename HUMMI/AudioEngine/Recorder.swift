//
//  Recorder.swift
//  HUMMI
//

import AVFoundation

/// Uses Apple's high-level recording API and normal voice-recording session
/// path. HUMMI owns presentation and post-processing, while AVAudioRecorder
/// owns capture, route negotiation, and WAV writing — the closest supported
/// public equivalent to the Voice Memos capture experience.
@MainActor
final class Recorder: NSObject, AVAudioRecorderDelegate {
    var onLevels: (@MainActor @Sendable (_ rms: Float, _ peak: Float, _ elapsed: TimeInterval) -> Void)?
    var onAutoStop: (@MainActor @Sendable (RecorderStopReason, URL) -> Void)?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var stopWasRequested = false

    var isRecording: Bool { recorder?.isRecording == true }

    deinit {
        meterTimer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        recorder?.stop()
    }

    func start() throws -> URL {
        guard recorder == nil else { throw RecorderError.alreadyRecording }
        try AudioSessionManager.configureForRecording()

        let url = try RecordingLibrary.newRecordingURL()
        let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw RecorderError.recordingFailed("The microphone could not start recording.")
        }

        self.recorder = recorder
        recordingURL = url
        stopWasRequested = false
        observeSessionEvents()
        startMetering()
        return url
    }

    @discardableResult
    func stop() -> URL? {
        guard let recorder, let url = recordingURL else { return nil }
        stopWasRequested = true
        stopMetering()
        removeObservers()
        recorder.stop()
        self.recorder = nil
        recordingURL = nil
        try? AudioSessionManager.configureForPlayback()
        return url
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !stopWasRequested, let url = recordingURL else { return }
        stopMetering()
        removeObservers()
        self.recorder = nil
        recordingURL = nil
        try? AudioSessionManager.configureForPlayback()
        onAutoStop?(flag ? .interrupted : .writeFailed("The recording ended unexpectedly."), url)
    }

    // MARK: - Voice Memos-style audio settings

    /// Float32 linear PCM is lossless and preserves the existing 48 kHz mono
    /// pipeline. Capture gain is deliberately left to the system: iOS does
    /// not expose a reliable gain control for its built-in microphone.
    private static var settings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
        ]
    }

    // MARK: - Metering

    private func startMetering() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let rms = Self.linearAmplitude(from: recorder.averagePower(forChannel: 0))
            let peak = Self.linearAmplitude(from: recorder.peakPower(forChannel: 0))
            self.onLevels?(rms, peak, recorder.currentTime)
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private static func linearAmplitude(from decibels: Float) -> Float {
        guard decibels.isFinite, decibels > -160 else { return 0 }
        return min(max(Float(pow(10, Double(decibels) / 20)), 0), 1)
    }

    // MARK: - Session changes

    private func observeSessionEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.finishUnexpectedly(.interrupted) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) else { return }
            if reason == .oldDeviceUnavailable {
                Task { @MainActor in self?.finishUnexpectedly(.routeChangeFailed("The recording device changed.")) }
            }
        })
    }

    private func finishUnexpectedly(_ reason: RecorderStopReason) {
        guard let url = stop() else { return }
        onAutoStop?(reason, url)
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
