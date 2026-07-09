//
//  BeforeAfterDemoPlayer.swift
//  HUMMI
//
//  Plays the bundled before/after pair in lockstep on the `.ambient`
//  session (so it auto-mutes when the Ring/Silent switch is on), swapping
//  which one you hear every 3 seconds. The waveform and indicator read
//  `isPlayingAfter` / `currentFraction()`.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class BeforeAfterDemoPlayer {
    private(set) var isPlayingAfter = false
    private(set) var isReady = false
    private(set) var beforePeaks: [Float] = []
    private(set) var afterPeaks: [Float] = []

    var currentPeaks: [Float] { isPlayingAfter ? afterPeaks : beforePeaks }

    static let switchInterval: Duration = .seconds(3)

    private var before: AVAudioPlayer?
    private var after: AVAudioPlayer?
    private var toggleTask: Task<Void, Never>?

    /// Loads and starts the synced loop. Idempotent — a second call while
    /// loaded just resumes.
    func start() {
        guard before == nil else { resume(); return }
        guard
            let beforeURL = Bundle.main.url(forResource: "onboarding-before", withExtension: "m4a"),
            let afterURL = Bundle.main.url(forResource: "onboarding-after", withExtension: "m4a"),
            let beforePlayer = try? AVAudioPlayer(contentsOf: beforeURL),
            let afterPlayer = try? AVAudioPlayer(contentsOf: afterURL)
        else { return }

        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        for player in [beforePlayer, afterPlayer] {
            player.numberOfLoops = -1
            player.prepareToPlay()
        }
        beforePlayer.volume = 1
        afterPlayer.volume = 0
        beforePeaks = Self.peaks(from: beforeURL)
        afterPeaks = Self.peaks(from: afterURL)
        before = beforePlayer
        after = afterPlayer

        let startTime = beforePlayer.deviceCurrentTime + 0.15
        beforePlayer.play(atTime: startTime)
        afterPlayer.play(atTime: startTime)
        isReady = true
        startToggling()
    }

    /// Fraction (0…1) through the currently-audible track, for the
    /// waveform playhead.
    func currentFraction() -> Double {
        guard let player = isPlayingAfter ? after : before, player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }

    /// scenePhase → background.
    func pause() {
        toggleTask?.cancel()
        toggleTask = nil
        before?.pause()
        after?.pause()
    }

    /// scenePhase → foreground: resume muted, then fade the active track in.
    func resume() {
        guard let before, let after, !before.isPlaying else { return }
        before.volume = 0
        after.volume = 0
        before.play()
        after.play()
        (isPlayingAfter ? after : before).setVolume(1, fadeDuration: 0.4)
        startToggling()
    }

    func stop() {
        toggleTask?.cancel()
        toggleTask = nil
        before?.stop()
        after?.stop()
        before = nil
        after = nil
        isReady = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startToggling() {
        toggleTask?.cancel()
        toggleTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: Self.switchInterval)
                guard !Task.isCancelled, self.isReady else { break }
                self.isPlayingAfter.toggle()
                self.before?.setVolume(self.isPlayingAfter ? 0 : 1, fadeDuration: 0.15)
                self.after?.setVolume(self.isPlayingAfter ? 1 : 0, fadeDuration: 0.15)
            }
        }
    }

    private static func peaks(from url: URL, buckets: Int = 120) -> [Float] {
        guard let samples = try? AudioClipIO.loadMono48k(from: url), !samples.isEmpty else { return [] }
        let perBucket = max(samples.count / buckets, 1)
        var out: [Float] = []
        var index = 0
        while index < samples.count {
            let end = min(index + perBucket, samples.count)
            var peak: Float = 0
            for j in index..<end { peak = max(peak, abs(samples[j])) }
            out.append(peak)
            index = end
        }
        return out
    }
}
