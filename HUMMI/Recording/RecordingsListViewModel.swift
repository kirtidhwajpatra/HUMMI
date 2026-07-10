//
//  RecordingsListViewModel.swift
//  HUMMI
//

import Foundation
import Observation
import AVFoundation

/// Drives the Recordings list: loads library items (with cached waveform
/// metadata) off the main actor, deletes takes, and imports external audio.
@MainActor
@Observable
final class RecordingsListViewModel: NSObject, AVAudioPlayerDelegate {
    private(set) var items: [RecordingItem] = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    /// User-readable; the view presents and clears it.
    var errorMessage: String?
    
    private var audioPlayer: AVAudioPlayer?
    private(set) var currentlyPlayingID: RecordingItem.ID?

    override init() {
        super.init()
    }

    func togglePlayback(for item: RecordingItem) {
        if currentlyPlayingID == item.id {
            if let player = audioPlayer, player.isPlaying {
                player.pause()
                currentlyPlayingID = nil
            } else {
                audioPlayer?.play()
                currentlyPlayingID = item.id
            }
        } else {
            audioPlayer?.stop()
            do {
                let urlToPlay: URL
                if item.isEnhanced, let enhancedURL = try? EnhancementStore.url(for: item.url, preset: .studio), FileManager.default.fileExists(atPath: enhancedURL.path) {
                    urlToPlay = enhancedURL
                } else {
                    urlToPlay = item.url
                }
                
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .default)
                try? session.setActive(true)
                
                audioPlayer = try AVAudioPlayer(contentsOf: urlToPlay)
                audioPlayer?.delegate = self
                audioPlayer?.play()
                currentlyPlayingID = item.id
            } catch {
                errorMessage = "Playback failed: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.audioPlayer == player {
                self.currentlyPlayingID = nil
            }
        }
    }

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
