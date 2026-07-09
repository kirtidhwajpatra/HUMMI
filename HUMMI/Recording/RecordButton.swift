//
//  RecordButton.swift
//  HUMMI
//
//  The record control, styled after the Camera shutter: a red disc inside
//  a thin neutral ring with a comfortable gap. It gently expands on touch
//  and morphs the disc into a rounded square while recording.
//

import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    var rms: Float = 0
    let action: () -> Void

    private let ringSize: CGFloat = 72
    private var innerSize: CGFloat { isRecording ? 32 : 60 }
    private var innerRadius: CGFloat { isRecording ? 6 : 30 }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 4)
                    .frame(width: ringSize, height: ringSize)

                // Inner morphing button
                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                    .fill(Color.red)
                    .frame(width: innerSize, height: innerSize)
            }
            .frame(width: ringSize, height: ringSize)
            .contentShape(Circle())
            // Use native snappy animation for state change
            .animation(reduceMotion ? nil : .snappy(duration: 0.25, extraBounce: 0.1), value: isRecording)
        }
        .buttonStyle(ShutterPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
        .accessibilityHint(isRecording ? "Stops and opens your take" : "Starts recording immediately")
        .accessibilityAddTraits(.startsMediaSession)
    }

    /// Gently expands on touch, echoing the inviting feel of a shutter.
    private struct ShutterPressStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 1.05 : 1))
                .animation(.spring(response: 0.3, dampingFraction: 0.6),
                           value: configuration.isPressed)
        }
    }
}

#if DEBUG
#Preview("Light") {
    VStack(spacing: Spacing.xxl) {
        RecordButton(isRecording: false) {}
        RecordButton(isRecording: true) {}
    }
    .tint(.accentColor)
}
#Preview("Dark") {
    RecordButton(isRecording: false) {}
        .tint(.accentColor)
        .preferredColorScheme(.dark)
}
#endif
