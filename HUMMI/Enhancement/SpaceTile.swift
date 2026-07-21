//
//  SpaceTile.swift
//  HUMMI
//
//  A space filter as the same capsule chip as CharacterCard, but its
//  leading mark is the room itself: a dark-green dot with reverberation
//  rings that grow with the decay time. One colour, one geometry —
//  bigger room, more rings. Selection flips the chip to forest and the
//  emblem to lime, matching the app's secondary buttons.
//

import SwiftUI

struct SpaceTile: View {
    let filter: SpaceFilter
    let isActive: Bool
    /// Position in the row — staggers the entrance.
    let index: Int
    let action: () -> Void
    var onLongPress: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    var body: some View {
        Button(action: action) {

            
            VStack(spacing: Spacing.m) {
                Image(systemName: filter.glyph)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Brand.ink.opacity(isActive ? 1.0 : 0.6))
                    .contentTransition(.symbolEffect(.replace))

                
                Text(filter.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? Brand.ink : Brand.ink.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, Spacing.s)
            }
            .frame(width: 116, height: 112)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(isActive ? Brand.lime.opacity(0.15) : Brand.ink.opacity(0.06))
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26, style: .continuous))
            .scaleEffect(isActive ? 1.03 : 1)
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
        .accessibilityHint("Applies the \(filter.name) space filter.")
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
