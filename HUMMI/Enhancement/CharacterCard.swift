//
//  CharacterCard.swift
//  HUMMI
//
//  A character filter as a night orb: a deep sphere tinted with the
//  filter's palette, lit by a luminous rim that burns hottest along one
//  arc — like a planet catching its sun. No glyphs; the name floats in
//  the centre of the sphere. Every filter keeps its own hue and its own
//  light angle (seeded from its id), so the row reads as twelve small
//  worlds. Selection adds the brand's lime ring and turns the light up.
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

    private let diameter: CGFloat = 104

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s) {
                // The glass pill icon inspired by GlowIconButton
                ZStack {
                    Circle().fill(isActive ? Brand.lime.opacity(0.15) : Brand.ink.opacity(0.06))
                    
                    Image(systemName: filter.glyph)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Brand.ink.opacity(isActive ? 1.0 : 0.6))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 88, height: 88)
                .glassEffect(.regular.interactive(), in: .circle)
                .scaleEffect(isActive ? 1.05 : 1)


                Text(filter.name)
                    .font(.caption.weight(isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? Brand.ink : Brand.ink.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 96)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in onLongPress() })
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 8)
        .onAppear {
            guard !entered else { return }
            withAnimation(Motion.adaptive(
                Motion.standard.delay(Double(index) * 0.04), reduceMotion: reduceMotion)) {
                entered = true
            }
        }
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: isActive)
        .accessibilityLabel("\(filter.name). \(filter.tagline)")
        .accessibilityHint("Applies the \(filter.name) voice character filter.")
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Where this filter's sun sits, stable across launches.
    private var lightAngle: Double {
        let seed = filter.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double((seed * 37) % 360)
    }
}
