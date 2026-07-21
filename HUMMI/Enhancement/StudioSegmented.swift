//
//  StudioSegmented.swift
//  HUMMI
//
//  A minimal segmented picker for choices that are really presets, not
//  continua — room size, autotune strength, cleanup level. Lime fill marks
//  the selection; changing it ticks a light haptic.
//

import SwiftUI

struct StudioSegmented: View {
    let label: String
    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(.subheadline)

            HStack(spacing: 4) {
                ForEach(options.indices, id: \.self) { i in
                    segment(i)
                }
            }
            .padding(4)
            .background(Brand.ink.opacity(0.06), in: Capsule())
            .animation(Motion.standard, value: selectedIndex)
        }
    }

    private func segment(_ i: Int) -> some View {
        let isSelected = i == selectedIndex
        return Text(options[i])
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(isSelected ? Brand.forest : Brand.ink.opacity(0.55))
            .background {
                if isSelected {
                    Capsule().fill(Brand.limeGradient)
                        .shadow(color: Brand.limeDeep.opacity(0.3), radius: 5, y: 2)
                }
            }
            .contentShape(Capsule())
            .onTapGesture {
                guard i != selectedIndex else { return }
                Haptics.shared.play(.light)
                onSelect(i)
            }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
