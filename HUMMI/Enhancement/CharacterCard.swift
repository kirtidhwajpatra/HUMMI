//
//  CharacterCard.swift
//  HUMMI
//
//  A character filter as a compact card: the filter's colour identity
//  lives in a small gradient swatch disc, the card chrome stays quiet —
//  and selection is unmistakable: the card flips to deep forest with a
//  lime ring, lime name, and a lime check badge. One glance answers
//  "which voice am I wearing?".
//

import SwiftUI

struct CharacterCard: View {
    let filter: CharacterFilter
    let isActive: Bool
    /// Position in the row — staggers the entrance.
    let index: Int
    let action: () -> Void
    var onLongPress: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s) {
                ZStack {
                    Circle()  // minimal: plain white disc, the icon is the colour
                        .fill(.white)
                        .frame(width: 54, height: 54)
                    Image(systemName: filter.glyph)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(filter.dominant)
                }
                Text(filter.name)
                    .font(.subheadline.weight(isActive ? .bold : .medium))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 104, height: 116)
            .background {  // selection is a whisper: tinted fill + slim stroke
                if isActive {
                    Brand.limeGradient.opacity(0.15)
                } else {
                    Brand.ink.opacity(0.05)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isActive ? Brand.limeDeep : Brand.ink.opacity(0.1),
                                  lineWidth: isActive ? 1.5 : 1))
            .scaleEffect(isActive ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in onLongPress() })
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 8)
        .onAppear {
            guard !entered else { return }
            withAnimation(Motion.adaptive(
                Motion.standard.delay(Double(index) * 0.05), reduceMotion: reduceMotion)) {
                entered = true
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: isActive)
        .accessibilityLabel("\(filter.name). \(filter.tagline)")
        .accessibilityHint("Applies the \(filter.name) voice character filter.")
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
