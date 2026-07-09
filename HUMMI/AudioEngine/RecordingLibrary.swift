//
//  RecordingLibrary.swift
//  HUMMI
//

import Foundation

/// The on-disk library of takes: Documents/Recordings/. Lists, deletes,
/// mints file URLs for new recordings, and imports external audio by
/// converting it to the app-internal 48 kHz mono Float32 WAV format.
nonisolated enum RecordingLibrary {
    static func directory() throws -> URL {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            throw RecorderError.documentsUnavailable
        }
        let directory = documents.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// All WAV files in the library with their creation dates, newest first.
    static func listRecordings() throws -> [(url: URL, date: Date)] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: try directory(),
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles)
        return contents
            .filter { $0.pathExtension.lowercased() == "wav" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?
                    .creationDate ?? .distantPast
                return (url, date)
            }
            .sorted { $0.date > $1.date }
    }

    /// Removes the audio file, its cached waveform metadata, and any
    /// enhanced renders derived from it.
    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: RecordingMetadata.cacheURL(for: url))
        EnhancementStore.deleteAll(for: url)
    }

    /// Mints a unique timestamped WAV URL in the library.
    static func newRecordingURL(prefix: String = "Recording") throws -> URL {
        let directory = try directory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stem = "\(prefix)-\(formatter.string(from: Date()))"
        var url = directory.appendingPathComponent("\(stem).wav")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(stem)-\(suffix).wav")
            suffix += 1
        }
        return url
    }

    /// Copies any audio file into the library as 48 kHz mono Float32 WAV.
    /// Returns the new file's URL.
    static func importAudio(from source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                source.stopAccessingSecurityScopedResource()
            }
        }
        let samples = try AudioClipIO.loadMono48k(from: source)
        guard !samples.isEmpty else {
            throw DFNError.audioFile("\(source.lastPathComponent) contains no audio")
        }
        let destination = try newRecordingURL(prefix: "Import")
        try AudioClipIO.writeWAV(samples, to: destination)
        return destination
    }
}
