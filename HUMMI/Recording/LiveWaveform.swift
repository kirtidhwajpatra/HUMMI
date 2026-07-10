//
//  LiveWaveform.swift
//  HUMMI
//
//  The home screen's recording surface. At rest it shows a calm, organic
//  waveform that gently "breathes" (its amplitude swells and settles). While
//  recording it becomes a live meter that scrolls with the voice.
//

import Combine
import SwiftUI

struct LiveWaveform: View {
    /// Current input level, 0…1 (RMS). Only used while recording.
    var level: CGFloat
    var isRecording: Bool
    var tint: Color

    @State private var samples: [Float] = LiveWaveform.base
    /// Number of bars visible in the meter.
    private static let barCount = 48
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        WaveformView(peaks: samples, tint: tint, style: .bars, normalize: false)
            .onReceive(tick) { _ in if !reduceMotion { advance() } }
            .accessibilityHidden(true)
    }

    private func advance() {
        phase += 0.12
        if isRecording {
            // Voice-reactive: scale the linear RMS logarithmically/non-linearly
            // so small volume changes create visible, organic waveform peaks.
            let emphasized = sqrt(level) * 2.0
            let next = Float(min(0.14 + emphasized, 1.0))
            var updated = samples
            if updated.count >= Self.barCount { updated.removeFirst() }
            updated.append(next)
            samples = updated
        } else {
            // Breathing: hold the organic resting shape and let its overall
            // amplitude swell and settle slowly.
            let breath = 0.76 + 0.24 * (0.5 + 0.5 * sin(phase * 0.9))
            samples = Self.base.map { $0 * Float(breath) }
        }
    }

    /// A fixed, natural-looking resting shape — small ripples with a few
    /// taller peaks, like a real take at rest.
    private static let base: [Float] = [
        0.16, 0.26, 0.20, 0.40, 0.28, 0.18, 0.34, 0.56, 0.36, 0.24,
        0.44, 0.30, 0.22, 0.50, 0.34, 0.26, 0.42, 0.30, 0.20, 0.38,
        0.58, 0.34, 0.24, 0.46, 0.32, 0.22, 0.40, 0.28, 0.44, 0.30,
        0.22, 0.18, 0.30, 0.42, 0.26, 0.36, 0.20, 0.48, 0.32, 0.24,
        0.38, 0.28, 0.44, 0.34, 0.22, 0.40, 0.26, 0.16,
    ]
}
