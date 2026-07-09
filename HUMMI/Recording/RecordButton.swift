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
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private let ringSize: CGFloat = 98
    private var innerSize: CGFloat { isRecording ? 42 : 82 }
    private var innerRadius: CGFloat { isRecording ? 10 : 41 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(
                        isRecording ? Color.accentColor.opacity(0.5) : Color(.systemGray4),
                        lineWidth: 4)
                    .frame(width: ringSize, height: ringSize)
                    .animation(reduceMotion ? nil : Motion.standard, value: isRecording)

                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: innerSize, height: innerSize)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 3)
                    .animation(reduceMotion ? nil : Motion.standard, value: isRecording)
            }
            .frame(width: ringSize, height: ringSize)
            .scaleEffect((!isRecording && breathe && !reduceMotion) ? 1.03 : 1.0)
            .contentShape(Circle())
        }
        .buttonStyle(ShutterPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
        .accessibilityHint(isRecording ? "Stops and opens your take" : "Starts recording immediately")
        .accessibilityAddTraits(.startsMediaSession)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
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
