//
//  SpaceTile.swift
//  HUMMI
//
//  A space filter as a compact card, in the same system as
//  CharacterCard: the room's colour identity in a gradient swatch disc,
//  quiet card chrome, and an unmistakable selected state — deep forest
//  fill with a lime ring and lime name. Both filter rows speak one
//  selection language.
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
            VStack(spacing: Spacing.s) {
                customSpaceIcon
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
        .accessibilityHint("Applies the \(filter.name) space filter.")
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var customSpaceIcon: some View {
        let decay = filter.decay
        let ringCount = decay < 0.5 ? 0 : 
                        decay < 1.0 ? 1 :
                        decay < 1.5 ? 2 :
                        decay < 2.2 ? 3 :
                        decay < 3.0 ? 4 : 5
                        
        let coreSize: CGFloat = 12 + (CGFloat(decay) * 3)
        
        return ZStack {
            // The central sound source
            Circle()
                .fill(filter.dominant)
                .frame(width: coreSize, height: coreSize)
            
            // Expanding reverberation rings to represent room size
            if ringCount > 0 {
                ForEach(1...ringCount, id: \.self) { i in
                    Circle()
                        .stroke(filter.dominant.opacity(max(0.1, 0.7 - (Double(i) * 0.12))), lineWidth: 1.5)
                        .frame(width: coreSize + CGFloat(i * 10), height: coreSize + CGFloat(i * 10))
                }
            }
        }
        .frame(width: 54, height: 54)
    }
}
