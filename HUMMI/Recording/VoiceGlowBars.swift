//
//  VoiceGlowBars.swift
//  HUMMI
//
//  The home screen's voice graph, in the app's default waveform style:
//  many thin bars. A perfectly flat zero line at rest — the wave only
//  exists while recording, drawn live from the voice.
//

import Combine
import SwiftUI

struct VoiceGlowBars: View {
    /// Current input level, 0…1 (RMS). Only used while recording.
    var level: CGFloat
    var isRecording: Bool
    var isIdle: Bool = false

    @State private var samples: [Float] = VoiceGlowBars.flat
    @State private var pulse = false
    
    // Reduced bar count to prevent edge-to-edge touching
    private static let barCount = 44
    /// One bar slot in WaveformView is 3pt bar + 2pt gap; sizing the
    /// canvas to exactly `barCount` slots keeps the graph centred.
    private static let graphWidth = CGFloat(barCount) * 5 - 2

    var body: some View {
        // Guideline: quiet ink at rest; the live voice uses deep dark green.
        ZStack(alignment: .top) {
            if isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? 1.0 : 0.2)
                    Text("REC")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospaced())
                        .foregroundStyle(Color.red)
                        .tracking(1)
                }
                .offset(y: -24)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
                .onDisappear { pulse = false }
            }

            WaveformView(peaks: samples,
                         tint: isRecording ? Brand.forest : Brand.ink.opacity(0.3),
                         style: .bars, normalize: false)
                .frame(width: Self.graphWidth, height: 110)
                .shadow(color: Brand.forest.opacity(isRecording ? 0.35 : 0), radius: 16)
        }
        .animation(.easeInOut(duration: 0.25), value: isRecording)
            .onChange(of: level) { _, newLevel in
                guard isRecording else { return }
                advance(with: newLevel)
            }
            .onChange(of: isRecording) { _, recording in
                // Start fresh only when a new recording begins.
                if recording {
                    samples = Self.flat
                }
            }
            .onChange(of: isIdle) { _, idle in
                // Clear the frozen graph when we cancel and return to idle.
                if idle {
                    samples = Self.flat
                }
            }
            .accessibilityHidden(true)
    }

    /// Voice-reactive scroll: sqrt emphasises quiet passages so soft
    /// singing still moves the graph. The gain is tuned so normal singing
    /// lands mid-frame, and the cap keeps headroom above every bar —
    /// the old ×1.8 curve clamped real vocals to 1.0 and the graph
    /// rendered as a flat-topped block touching the frame edges.
    private func advance(with currentLevel: CGFloat) {
        let emphasized = sqrt(max(currentLevel, 0)) * 1.05
        let next = Float(min(0.08 + emphasized, 0.82))
        var updated = samples
        if updated.count >= Self.barCount { updated.removeFirst() }
        updated.append(next)
        samples = updated
    }

    /// Silence: WaveformView draws zero peaks as a thin flat line of dots.
    private static let flat = [Float](repeating: 0, count: barCount)
}
