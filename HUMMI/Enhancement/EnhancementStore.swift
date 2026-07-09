//
//  EnhancementStore.swift
//  HUMMI
//

import Foundation

/// On-disk cache of enhanced renders, kept alongside the originals in
/// `Recordings/Enhanced/`. Files are named `<originalStem>__<preset>.wav`.
/// The subfolder keeps them out of `RecordingLibrary.listRecordings`
/// (which scans `Recordings/` non-recursively for `.wav` files).
nonisolated enum EnhancementStore {
    static func directory() throws -> URL {
        let directory = try RecordingLibrary.directory()
            .appendingPathComponent("Enhanced", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Persistent file URL for a base-preset render of `original`.
    static func url(for original: URL, preset: StudioPreset) throws -> URL {
        let stem = original.deletingPathExtension().lastPathComponent
        return try directory().appendingPathComponent("\(stem)__\(preset.rawValue).wav")
    }

    /// Which base presets already have a saved render for this take.
    static func existingPresets(for original: URL) -> [StudioPreset] {
        StudioPreset.allCases.filter { preset in
            guard let url = try? url(for: original, preset: preset) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    static func hasAnyEnhancement(for original: URL) -> Bool {
        !existingPresets(for: original).isEmpty
    }

    /// Removes every enhanced render for a take (called when the original
    /// is deleted).
    static func deleteAll(for original: URL) {
        for preset in StudioPreset.allCases {
            if let url = try? url(for: original, preset: preset) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
