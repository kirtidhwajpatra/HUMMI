//
//  RecorderStopReason.swift
//  HUMMI
//

import Foundation

/// Why the recorder stopped on its own. In every case the partial file is
/// finalized and playable.
nonisolated enum RecorderStopReason: Equatable {
    /// A phone call or another app took the audio session.
    case interrupted
    /// The audio route changed and the engine could not be restarted.
    case routeChangeFailed(String)
    /// Writing to the recording file failed (for example, disk full).
    case writeFailed(String)

    var message: String {
        switch self {
        case .interrupted:
            return "Recording stopped because a call or another app took over audio. Your take so far is saved."
        case .routeChangeFailed(let detail):
            return "Recording stopped after the audio route changed (\(detail)). Your take so far is saved."
        case .writeFailed(let detail):
            return "Recording stopped early: \(detail). Your take so far is saved."
        }
    }
}
