//
//  RecordButton.swift
//  HUMMI
//
//  The record control — the app's one red thing, per the brand
//  guideline. Kept simple: a flat two-stop gradient disc (the same
//  "slight gradient" treatment as the lime buttons), a hairline
//  highlight, and a white record dot that morphs into a stop square.
//  No gloss, no halos, no glow. Press physics and haptics match the
//  rest of the button system.
//

import SwiftUI
import UIKit

struct RecordButton: View {
    let isRecording: Bool
    /// Kept for call-site compatibility; the simple button doesn't
    /// visualise level — the waveform above it does.
    var rms: Float = 0
    let action: () -> Void

    private static let redTop = Color(red: 1.0, green: 0.42, blue: 0.36)
    private static let redDeep = Color(red: 0.82, green: 0.09, blue: 0.15)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Self.redTop, Self.redDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 92, height: 92)
                // A clean solid disc at rest; the white stop square only
                // exists while recording.
                if isRecording {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white)
                        .frame(width: 32, height: 32)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
            }
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .snappy(duration: 0.25, extraBounce: 0.1),
                       value: isRecording)
        }
        .buttonStyle(SimplePressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
        .accessibilityHint(isRecording ? "Stops and opens your take" : "Starts recording immediately")
        .accessibilityAddTraits(.startsMediaSession)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    /// Squish + soft haptic on finger-down; a modest neutral shadow, not
    /// a coloured glow.
    private struct SimplePressStyle: ButtonStyle {
        let reduceMotion: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
                .brightness(configuration.isPressed ? -0.05 : 0)
                .shadow(color: .black.opacity(configuration.isPressed ? 0.1 : 0.18),
                        radius: configuration.isPressed ? 5 : 10,
                        y: configuration.isPressed ? 2 : 5)
                .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
                    }
                }
        }
    }
}

#if DEBUG
#Preview("Light") {
    VStack(spacing: Spacing.xxl) {
        RecordButton(isRecording: false) {}
        RecordButton(isRecording: true) {}
    }
    .padding()
}

#Preview("Dark") {
    RecordButton(isRecording: false) {}
        .padding()
        .preferredColorScheme(.dark)
}
#endif
