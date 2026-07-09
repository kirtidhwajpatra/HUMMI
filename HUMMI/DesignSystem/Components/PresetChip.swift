//
//  PresetChip.swift
//  HUMMI
//
//  A horizontally scrollable row of tone-filter cards: each is a colourful
//  gradient tile with a faint themed glyph and its name, in the spirit of
//  Apple Podcasts' category cards. The selected card is ringed and lifted.
//

import SwiftUI

/// A lightweight description of one tone-filter card.
struct PresetChipModel: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    /// Two-stop gradient (top-leading → bottom-trailing).
    var colors: [Color] = [.gray, .gray]
}

struct PresetChipRow: View {
    let items: [PresetChipModel]
    let selectedID: String
    var isEnabled: Bool = true
    let onSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(items) { item in
                    card(item)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
        }
        .scrollClipDisabled()
        .sensoryFeedback(Haptic.presetChange, trigger: selectedID)
        .animation(
            reduceMotion ? Motion.reducedCrossfade : Motion.standard,
            value: selectedID)
    }

    private func card(_ item: PresetChipModel) -> some View {
        let selected = item.id == selectedID
        return Button {
            onSelect(item.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: item.colors,
                    startPoint: .topLeading, endPoint: .bottomTrailing)

                Image(systemName: item.systemImage)
                    .font(.system(size: 42))
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, Spacing.xs)
                    .padding(.trailing, -6)
                    .clipped()

                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(Spacing.s)
            }
            .frame(width: 138, height: 92)
            .clipShape(Radius.rect(Radius.card))
            .overlay {
                Radius.rect(Radius.card)
                    .stroke(.white, lineWidth: selected ? 3 : 0)
            }
            .overlay(alignment: .topLeading) {
                if selected { checkBadge.padding(Spacing.xs) }
            }
            .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
            .scaleEffect(selected ? 1 : 0.97)
            .opacity(selected ? 1 : 0.9)
        }
        .buttonStyle(ChipPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Applies the \(item.title) sound")
    }

    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Color.accentColor)
            .frame(width: 20, height: 20)
            .background(.white, in: Circle())
    }

    private struct ChipPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(Motion.micro, value: configuration.isPressed)
        }
    }
}

#if DEBUG
private struct ChipsPreview: View {
    @State private var selected = "studio"
    private let items = [
        PresetChipModel(id: "default", title: "Default", systemImage: "wand.and.rays", colors: [.teal, .green]),
        PresetChipModel(id: "studio", title: "Studio", systemImage: "sparkles", colors: [.red, .orange]),
        PresetChipModel(id: "warm", title: "Warm", systemImage: "flame", colors: [.orange, .pink]),
        PresetChipModel(id: "bright", title: "Bright", systemImage: "sun.max", colors: [.yellow, .orange]),
    ]
    var body: some View {
        PresetChipRow(items: items, selectedID: selected) { selected = $0 }
            .tint(.accentColor)
    }
}

#Preview("Light") { ChipsPreview().preferredColorScheme(.light) }
#Preview("Dark") { ChipsPreview().preferredColorScheme(.dark) }
#endif
