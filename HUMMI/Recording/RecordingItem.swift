//
//  RecordingItem.swift
//  HUMMI
//

import Foundation

/// One recording as shown in the library list: file, date, duration, and
/// waveform thumbnail peaks.
nonisolated struct RecordingItem: Identifiable, Hashable, Sendable {
    let url: URL
    let date: Date
    let duration: TimeInterval
    let peaks: [Float]
    /// The user-facing name (custom, or a stable default).
    var name: String = ""
    /// True when at least one enhanced render exists for this take.
    var isEnhanced: Bool = false

    var id: URL { url }
}
