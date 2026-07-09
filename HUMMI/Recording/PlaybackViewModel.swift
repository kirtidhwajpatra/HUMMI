//
//  PlaybackViewModel.swift
//  HUMMI
//

import AVFoundation
import Observation

/// Plays back a finished recording with play/pause and scrubbing.
/// Owns the AVPlayer so views never touch playback machinery directly.
@MainActor
@Observable
final class PlaybackViewModel {
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    /// Settable so a Slider can bind to it while scrubbing; the actual
    /// seek happens when scrubbing ends.
    var currentTime: TimeInterval = 0

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var isScrubbing = false

    func load(_ url: URL) async {
        unload()
        let asset = AVURLAsset(url: url)
        let assetDuration = (try? await asset.load(.duration).seconds) ?? 0
        duration = assetDuration.isFinite ? assetDuration : 0

        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player
        isLoaded = true

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playbackEnded()
            }
        }
    }

    func unload() {
        if let player, let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        player?.pause()
        player = nil
        timeObserverToken = nil
        endObserver = nil
        isLoaded = false
        isPlaying = false
        duration = 0
        currentTime = 0
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // Ensure audio session is configured for playback
            try? AudioSessionManager.configureForPlayback()
            
            if duration > 0, currentTime >= duration - 0.05 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    /// Slider editing state: while true, the periodic observer leaves
    /// `currentTime` alone; on release we seek to the scrubbed position.
    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if !scrubbing {
            seek(to: currentTime)
        }
    }

    private func seek(to time: TimeInterval) {
        currentTime = time
        player?.seek(
            to: CMTime(seconds: time, preferredTimescale: 48_000),
            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func playbackEnded() {
        isPlaying = false
        currentTime = duration
    }
}
