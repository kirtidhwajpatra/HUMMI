//
//  RecordButton.swift
//  HUMMI
//
//  The hero record control. Styled as a glowing orb that pulses based on
//  audio input (rms) while recording.
//

import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    var rms: Float = 0
    let action: () -> Void

    private let baseSize: CGFloat = 88
    private var pulseScale: CGFloat {
        if !isRecording { return 1.0 }
        // Scale slightly based on volume (rms usually between 0.0 and 1.0)
        let boost = max(0, min(CGFloat(rms) * 1.5, 0.4))
        return 1.0 + boost
    }
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            Haptics.shared.play(.heavy)
            action()
        }) {
            ZStack {
                // Outer glow / pulse ring
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: baseSize, height: baseSize)
                        .scaleEffect(pulseScale * 1.4)
                        .blur(radius: 12)
                }
                
                // Outer border ring
                Circle()
                    .strokeBorder(
                        isRecording ? Color.red.opacity(0.8) : Color.white.opacity(0.6),
                        lineWidth: isRecording ? 4 : 2
                    )
                    .frame(width: baseSize, height: baseSize)
                    .shadow(color: isRecording ? Color.red.opacity(0.5) : Color.black.opacity(0.1), radius: 8)

                // Inner morphing shape
                RoundedRectangle(cornerRadius: isRecording ? 12 : baseSize / 2, style: .continuous)
                    .fill(isRecording ? Color.red : Color.white)
                    .frame(width: isRecording ? 36 : baseSize - 16, height: isRecording ? 36 : baseSize - 16)
                    .shadow(color: isRecording ? .clear : Color.black.opacity(0.2), radius: 4, y: 2)
            }
            .frame(width: baseSize * 1.5, height: baseSize * 1.5) // give room for the pulse
            .contentShape(Circle())
            // Smoothly animate the morph and color changes
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: isRecording)
            // Animate the pulse strictly based on rms changes
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.1, dampingFraction: 0.8), value: pulseScale)
        }
        .buttonStyle(OrbPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
        .accessibilityHint(isRecording ? "Stops and opens your take" : "Starts recording immediately")
        .accessibilityAddTraits(.startsMediaSession)
    }

    /// Gently expands/contracts on touch
    private struct OrbPressStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.9 : 1))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
    }
}

