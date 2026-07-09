//
//  MP3Badge.swift
//  HUMMI
//
//  A small "audio captured" gauge: a semicircle of ticks fading from the
//  accent to a pale tint, with a checkmark disc at its base and a format
//  label beneath. Purely decorative reassurance for the overview screen.
//

import SwiftUI

struct MP3Badge: View {
    var label: String = "MP3"

    private let tickCount = 22
    private let radius: CGFloat = 34

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                ForEach(0..<tickCount, id: \.self) { index in
                    let t = Double(index) / Double(tickCount - 1)
                    Capsule()
                        .fill(Color.accentColor.opacity(1.0 - 0.72 * t))
                        .frame(width: 3.5, height: 11)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(-90 + 180 * t))
                }

                ZStack {
                    Circle().fill(Color.accentColor).frame(width: 30, height: 30)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(y: 4)
            }
            .frame(height: radius + 24, alignment: .bottom)

            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement()
        .accessibilityLabel("Audio captured")
    }
}

#if DEBUG
#Preview("Light") { MP3Badge().tint(.accentColor).padding() }
#Preview("Dark") { MP3Badge().tint(.accentColor).padding().preferredColorScheme(.dark) }
#endif
