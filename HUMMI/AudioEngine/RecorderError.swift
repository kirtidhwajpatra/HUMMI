//
//  RecorderError.swift
//  HUMMI
//

import Foundation

/// Errors starting or running a recording, phrased for the UI.
nonisolated enum RecorderError: LocalizedError {
    case alreadyRecording
    case noInputAvailable
    case unsupportedInputFormat(String)
    case documentsUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .noInputAvailable:
            return "No microphone input is available right now."
        case .unsupportedInputFormat(let detail):
            return "The microphone's audio format is not supported: \(detail)."
        case .documentsUnavailable:
            return "Could not open the folder where recordings are saved."
        }
    }
}
