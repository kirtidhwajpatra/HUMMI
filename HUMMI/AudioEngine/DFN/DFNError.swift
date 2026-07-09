//
//  DFNError.swift
//  HUMMI
//

import Foundation

/// Errors from the DeepFilterNet3 enhancement pipeline, phrased for the UI.
nonisolated enum DFNError: LocalizedError {
    case modelMissing
    case dspUnavailable
    case unexpectedModelOutput(String)
    case audioFile(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "The enhancement model is missing from the app bundle."
        case .dspUnavailable:
            return "This device does not support the required audio transforms."
        case .unexpectedModelOutput(let detail):
            return "The enhancement model returned unexpected output: \(detail)."
        case .audioFile(let detail):
            return "Audio file problem: \(detail)."
        }
    }
}
