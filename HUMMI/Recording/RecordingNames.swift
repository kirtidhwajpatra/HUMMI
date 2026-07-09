//
//  RecordingNames.swift
//  HUMMI
//
//  Persists user-given take names (keyed by filename) and supplies a
//  stable default like "Recording 116" for takes that haven't been named.
//  Backed by UserDefaults so it's cheap and available off the main actor.
//

import Foundation

nonisolated enum RecordingNames {
    private static let key = "recordingDisplayNames"

    static func name(for url: URL) -> String {
        let file = url.lastPathComponent
        if let custom = stored[file], !custom.isEmpty { return custom }
        return defaultName(for: url)
    }

    /// Persists a rename; clearing it (empty or back to default) removes the
    /// override so the default reappears.
    static func setName(_ name: String, for url: URL) {
        let file = url.lastPathComponent
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var map = stored
        if trimmed.isEmpty || trimmed == defaultName(for: url) {
            map[file] = nil
        } else {
            map[file] = trimmed
        }
        UserDefaults.standard.set(map, forKey: key)
    }

    /// Our own takes collapse to "Recording <n>"; imports keep their name.
    static func defaultName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        guard base.hasPrefix("Recording") else { return base }
        return "Recording \(stableNumber(for: base))"
    }

    private static var stored: [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    /// A stable 3-digit number derived from the filename (so it survives
    /// relaunches, unlike Swift's per-process String hash).
    private static func stableNumber(for string: String) -> Int {
        let sum = string.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return 100 + (sum % 900)
    }
}
