//
//  SpaceTile.swift
//  HUMMI
//
//  A space filter as a luminous gradient tile: soft-focused gradient
//  with a slow internal drift, film-grain wash, and the name set inside
//  (tiles carry names inside; orbs carry them below). Active tiles get a
//  hairline stroke, a small scale, and a halo of their dominant colour.
//

import SwiftUI

struct SpaceTile: View {
    static let size = CGSize(width: 140, height: 100)
    private static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    let filter: SpaceFilter
    let isActive: Bool
    /// Position in the row — staggers the entrance.
    let index: Int
    let action: () -> Void
    var onLongPress: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var drifting = false
    @State private var bloomScale = 1.0
    @State private var bloomOpacity = 0.0

    var body: some View {
        Button {
            tapEffects()
            action()
        } label: {
            ZStack {
                gradient
                StudioNoise()
                Text(filter.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 8)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xs)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(Self.shape)
            .overlay {
                Self.shape
                    .inset(by: 1)
                    .stroke(.white.opacity(isActive ? 0.6 : 0.12), lineWidth: 1)
            }
            .overlay(bloom)
            .shadow(color: filter.tile.glow.opacity(isActive ? 0.35 : 0), radius: 20)
            .scaleEffect(isActive ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in onLongPress() })
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 10)
        .onAppear(perform: enter)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: isActive)
        .accessibilityLabel("\(filter.name). \(filter.tagline)")
        .accessibilityHint("Applies the \(filter.name) space filter.")
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// An oversized gradient layer, slowly rotated inside the clipped
    /// tile, so the fill drifts without the shape moving.
    private var gradient: some View {
        LinearGradient(colors: filter.tile.stops,
                       startPoint: filter.tile.angled ? .topLeading : .top,
                       endPoint: filter.tile.angled ? .bottomTrailing : .bottom)
            .frame(width: Self.size.width * 1.7, height: Self.size.height * 2.4)
            .rotationEffect(.degrees(drifting ? 8 : -8))
            .overlay {  // soft inner glow toward the tile's centre
                RadialGradient(colors: [.white.opacity(0.18), .clear],
                               center: UnitPoint(x: 0.5, y: 0.35),
                               startRadius: 0, endRadius: Self.size.width)
            }
    }

    /// The tap bloom — a brief glow swelling out from the tile edges.
    private var bloom: some View {
        Self.shape
            .stroke(filter.tile.glow, lineWidth: 3)
            .blur(radius: 6)
            .scaleEffect(bloomScale)
            .opacity(bloomOpacity)
            .allowsHitTesting(false)
    }

    private func enter() {
        guard !entered else { return }
        withAnimation(Motion.adaptive(
            Motion.standard.delay(Double(index) * 0.05), reduceMotion: reduceMotion)) {
            entered = true
        }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
            drifting = true
        }
    }

    private func tapEffects() {
        bloomScale = 1
        bloomOpacity = 0.7
        if reduceMotion {  // static flash only
            withAnimation(.easeOut(duration: 0.4)) { bloomOpacity = 0 }
            return
        }
        withAnimation(.easeOut(duration: 0.5)) {
            bloomScale = 1.18
            bloomOpacity = 0
        }
    }
}
