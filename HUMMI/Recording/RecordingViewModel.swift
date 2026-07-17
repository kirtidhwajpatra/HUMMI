//
//  RecordingViewModel.swift
//  HUMMI
//

import Foundation
import Observation

/// Drives the Record screen: owns the Recorder, publishes elapsed time and
/// input levels while recording, and hands finished takes to playback.
@MainActor
@Observable
final class RecordingViewModel {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Linear levels (0…1) of the audio actually written to disk.
    private(set) var rms: Float = 0
    private(set) var peak: Float = 0
    private(set) var lastRecording: URL?
    /// User-readable status: why a recording stopped early, or why it
    /// could not start.
    private(set) var notice: String?

    let playback = PlaybackViewModel()
    private let recorder = Recorder()

    init() {
        recorder.onLevels = { [weak self] rms, peak, elapsed in
            self?.rms = rms
            self?.peak = peak
            self?.elapsed = elapsed
        }
        recorder.onAutoStop = { [weak self] reason, url in
            self?.finish(url: url, notice: reason.message)
        }
    }

    func toggleRecording() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isRecording else { return }
        notice = nil
        playback.unload()
        elapsed = 0
        rms = 0
        peak = 0
        do {
            _ = try recorder.start()
            isRecording = true
        } catch {
            notice = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording else { return }
        if let url = recorder.stop() {
            finish(url: url, notice: nil)
        } else {
            isRecording = false
        }
    }

    /// Stops and throws the take away — nothing lands in the library and
    /// `lastRecording` stays untouched.
    func cancel() {
        guard isRecording else { return }
        if let url = recorder.stop() {
            try? FileManager.default.removeItem(at: url)
        }
        isRecording = false
        elapsed = 0
        rms = 0
        peak = 0
    }

    private func finish(url: URL, notice: String?) {
        isRecording = false
        self.notice = notice
        lastRecording = url
        rms = 0
        peak = 0
        Task {
            await playback.load(url)
        }
    }
}
