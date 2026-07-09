//
//  AudioSessionState.swift
//  HUMMI
//

import Foundation

/// The audio session's current condition, as the UI should present it.
enum AudioSessionState: Equatable {
    /// Not yet configured.
    case idle
    /// Permission granted and the session is active.
    case ready
    /// The user declined microphone access; recording is impossible until
    /// they enable it in Settings.
    case permissionDenied
    /// Another app or a phone call took the audio session.
    case interrupted
    /// Headphones (or another device) were plugged in or unplugged.
    /// The session is still active.
    case routeChanged
    /// Configuration or activation failed. The message is user-readable.
    case failed(String)
}
