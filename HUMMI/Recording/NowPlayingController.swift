//
//  NowPlayingController.swift
//  HUMMI
//
//  App-wide playback for library takes. Owning the player here (instead of
//  inside the list screen) means a take keeps playing — and stays
//  controllable — after the user navigates away. The floating MiniPlayerBar
//  and the Recordings list both read this one source of truth.
//

import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class NowPlayingController: NSObject, AVAudioPlayerDelegate {
    static let shared = NowPlayingController()

    /// The take currently loaded in the player (playing or paused).
    struct Track: Equatable {
        let id: URL
        let title: String
        let isEnhanced: Bool
    }

    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    /// Seconds played, for the orb's minute.second readout.
    private(set) var elapsed: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    private override init() { super.init() }

    /// Play the item, or toggle it if it's already the loaded track.
    func play(_ item: RecordingItem) {
        if track?.id == item.id { toggle(); return }

        teardownPlayer()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        // Prefer the enhanced render, but fall back to the original take if
        // that file is missing or unreadable so playback never silently dies.
        let candidates = [Self.playbackURL(for: item), item.url]
        for url in candidates {
            guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.delegate = self
            self.player = player
            player.play()
            isPlaying = true
            progress = 0
            elapsed = 0
            track = Track(id: item.id,
                          title: item.name.isEmpty ? "Recording" : item.name,
                          isEnhanced: item.isEnhanced)
            startTicker()
            Haptics.shared.play(.light)
            return
        }
        track = nil
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTicker()
        } else {
            if player.duration > 0, player.currentTime >= player.duration - 0.05 {
                player.currentTime = 0
            }
            player.play()
            isPlaying = true
            startTicker()
        }
        Haptics.shared.play(.light)
    }

    /// Cancel playback and dismiss the mini-player.
    func stop() {
        teardownPlayer()
        track = nil
        progress = 0
        elapsed = 0
        Haptics.shared.play(.soft)
    }

    // MARK: - Internals

    private func teardownPlayer() {
        stopTicker()
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func startTicker() {
        stopTicker()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                if let player, player.duration > 0 {
                    progress = player.currentTime / player.duration
                    elapsed = player.currentTime
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player == finished else { return }
            // Playback ran to the end — the orb has nothing left to do, so
            // dismiss it. Clearing `track` animates it away via ContentView.
            self.teardownPlayer()
            self.track = nil
            self.progress = 0
            self.elapsed = 0
        }
    }

    /// Prefer the enhanced render when one exists on disk.
    static func playbackURL(for item: RecordingItem) -> URL {
        if item.isEnhanced,
           let enhanced = try? EnhancementStore.url(for: item.url, preset: .studio),
           FileManager.default.fileExists(atPath: enhanced.path) {
            return enhanced
        }
        return item.url
    }
}
