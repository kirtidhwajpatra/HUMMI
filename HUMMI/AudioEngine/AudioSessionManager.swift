//
//  AudioSessionManager.swift
//  HUMMI
//

import AVFoundation
import Observation

/// Owns the shared AVAudioSession: permission, configuration, activation,
/// and reacting to route changes and interruptions.
@MainActor
@Observable
final class AudioSessionManager {
    private(set) var state: AudioSessionState = .idle

    private let session = AVAudioSession.sharedInstance()
    // nonisolated(unsafe) so deinit can remove the observers; only ever
    // written from the main actor in init.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    init() {
        observeSessionNotifications()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Configures the session for high-quality playback (48kHz, .playback category, .default mode).
    static func configureForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)
    }

    /// Configures the session for recording (.playAndRecord category, .measurement mode to get raw microphone signals).
    static func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)
    }

    /// Asks for microphone permission, then configures and activates the
    /// session for 48kHz playback. Returns true when the session is ready.
    func requestPermissionAndActivate() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            state = .permissionDenied
            return false
        }

        do {
            try Self.configureForPlayback()
            state = .ready
            return true
        } catch {
            state = .failed("Could not start audio: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Notifications

    private func observeSessionNotifications() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            Task { @MainActor in
                self?.handleInterruption(type)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor in
                self?.handleRouteChange(reason)
            }
        })
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?) {
        switch type {
        case .began:
            state = .interrupted
        case .ended:
            do {
                try session.setActive(true)
                state = .ready
            } catch {
                state = .failed("Could not resume audio after the interruption: \(error.localizedDescription)")
            }
        default:
            break
        }
    }

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        // Only meaningful once the session is up and usable.
        guard state == .ready || state == .routeChanged else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            state = .routeChanged
        default:
            break
        }
    }
}
