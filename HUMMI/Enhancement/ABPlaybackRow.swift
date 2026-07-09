//
//  ABPlaybackRow.swift
//  HUMMI
//
//  Playback transport for the A/B player: skip-back-15, a prominent
//  circular accent play/pause, and skip-forward-30.
//

import SwiftUI

struct ABPlaybackRow: View {
    @Bindable var player: ABPlayer

    var body: some View {
        HStack(spacing: Spacing.xxl) {
            skip(system: "gobackward.15", label: "Back 15 seconds") {
                player.seek(to: max(0, player.currentTime - 15))
            }

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(Color.accentColor)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.weight(.medium))
                        .foregroundStyle(.white)
                        .offset(x: player.isPlaying ? 0 : 3)  // optical centering
                }
                .frame(width: 72, height: 72)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            skip(system: "goforward.30", label: "Forward 30 seconds") {
                player.seek(to: min(player.duration, player.currentTime + 30))
            }
        }
    }

    private func skip(system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(Motion.micro, value: configuration.isPressed)
        }
    }
}
