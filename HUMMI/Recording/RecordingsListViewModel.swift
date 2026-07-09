//
//  RecordingsListViewModel.swift
//  HUMMI
//

import Foundation
import Observation

/// Drives the Recordings list: loads library items (with cached waveform
/// metadata) off the main actor, deletes takes, and imports external audio.
@MainActor
@Observable
final class RecordingsListViewModel {
    private(set) var items: [RecordingItem] = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    /// User-readable; the view presents and clears it.
    var errorMessage: String?

    func load() async {
        isLoading = items.isEmpty
        defer { isLoading = false }
        do {
            items = try await Self.loadItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: RecordingItem) async {
        do {
            try await Self.performDelete(item.url)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importAudio(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            _ = try await Self.performImport(url)
            items = try await Self.loadItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @concurrent
    private static func loadItems() async throws -> [RecordingItem] {
        try RecordingLibrary.listRecordings().map { entry in
            // A single unreadable file should not sink the whole list.
            let metadata = (try? RecordingMetadata.loadOrCompute(for: entry.url))
                ?? .empty()
            return RecordingItem(
                url: entry.url, date: entry.date,
                duration: metadata.duration, peaks: metadata.peaks,
                name: RecordingNames.name(for: entry.url),
                isEnhanced: EnhancementStore.hasAnyEnhancement(for: entry.url))
        }
    }

    @concurrent
    private static func performDelete(_ url: URL) async throws {
        try RecordingLibrary.delete(url)
    }

    @concurrent
    private static func performImport(_ url: URL) async throws -> URL {
        try RecordingLibrary.importAudio(from: url)
    }
}
