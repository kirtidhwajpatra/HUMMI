#if DEBUG
//
//  SpikeTestResult.swift
//  HUMMI
//

#if DEBUG
import Foundation

/// Outcome of one Spike Test run: where the enhanced WAV landed and how
/// fast the pipeline was.
nonisolated struct SpikeTestResult: Sendable {
    let clipSeconds: Double
    let modelLoadSeconds: Double
    let processSeconds: Double
    let outputURL: URL

    /// Audio seconds processed per wall-clock second.
    var realtimeFactor: Double {
        processSeconds > 0 ? clipSeconds / processSeconds : 0
    }
}
#endif
#endif
