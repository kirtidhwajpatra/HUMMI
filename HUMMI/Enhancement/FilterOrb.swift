//
//  FilterOrb.swift
//  HUMMI
//
//  A character filter as a floating 3D orb: offset radial gradient for
//  the sphere illusion, upper-left highlight, rim glow, and the dominant
//  colour as a halo when active. Tap pulses the orb and emits a ring
//  bloom; idle orbs drift on a phase-offset sine so the row feels alive.
//  Reduce Motion drops the float, pulse, and bloom — colour carries it.
//

import SwiftUI

struct FilterOrb: View {
    static let diameter: CGFloat = 100

    let filter: CharacterFilter
    let isActive: Bool
    /// Position in the row — staggers the entrance and the idle-float phase.
    let index: Int
    let action: () -> Void
    var onLongPress: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    @State private var floating = false
    @State private var pulsing = false
    @State private var ringScale = 1.0
    @State private var ringOpacity = 0.0

    var body: some View {
        Button {
            tapEffects()
            action()
        } label: {
            VStack(spacing: Spacing.xs) {
                sphere
                    .frame(width: Self.diameter, height: Self.diameter)
                    .overlay(ring)
                    .shadow(color: filter.orb.glow.opacity(isActive ? 0.4 : 0), radius: 24)
                    .scaleEffect(orbScale)
                    .offset(y: floating ? -2 : 2)
                Text(filter.name)
                    .font(.subheadline.weight(isActive ? .semibold : .medium))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.diameter + Spacing.m)
            }
            .opacity(isActive ? 1 : 0.85)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in onLongPress() })
        .opacity(entered ? 1 : 0)
        .scaleEffect(entered ? 1 : 0.8)
        .offset(y: entered ? 0 : 5)
        .onAppear(perform: enter)
        .animation(Motion.adaptive(Motion.standard, reduceMotion: reduceMotion), value: isActive)
        .accessibilityLabel("\(filter.name). \(filter.tagline)")
        .accessibilityHint("Applies the \(filter.name) voice character filter.")
        .accessibilityValue(isActive ? "Selected" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var orbScale: CGFloat {
        if pulsing { return 1.15 }
        return isActive ? 1.08 : 1
    }

    /// Offset three-stop radial reads as a lit sphere; the highlight and
    /// rim stroke finish the material. Never a flat fill.
    private var sphere: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [filter.orb.core, filter.orb.mid, filter.orb.rim],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 2, endRadius: Self.diameter * 0.85))
            Circle()  // lower-right body shadow
                .fill(RadialGradient(
                    colors: [.clear, .clear, .black.opacity(0.28)],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0, endRadius: Self.diameter))
            highlight
            if filter.orb.grain {
                StudioNoise(opacity: 0.08).clipShape(Circle())
            }
            Circle()  // rim glow
                .stroke(filter.orb.glow.opacity(0.55), lineWidth: 1)
                .blur(radius: 1.5)
        }
        .clipShape(Circle())
        .drawingGroup()
    }

    @ViewBuilder private var highlight: some View {
        switch filter.orb.highlight {
        case .soft:
            highlightEllipse(width: 52, height: 34, blur: 7, brightness: 0.55)
        case .gloss:
            highlightEllipse(width: 44, height: 26, blur: 2.5, brightness: 0.85)
        case .metallic:  // elongated, angled — brushed-steel sheen
            highlightEllipse(width: 68, height: 16, blur: 4, brightness: 0.7)
                .rotationEffect(.degrees(-28))
        }
    }

    private func highlightEllipse(width: CGFloat, height: CGFloat, blur: CGFloat, brightness: Double) -> some View {
        Ellipse()
            .fill(LinearGradient(colors: [.white.opacity(brightness), .white.opacity(0)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
            .blur(radius: blur)
            .offset(x: -16, y: -26)
    }

    /// The ink-drop ring emitted on tap.
    private var ring: some View {
        Circle()
            .stroke(filter.orb.glow, lineWidth: 2)
            .scaleEffect(ringScale)
            .opacity(ringOpacity)
            .allowsHitTesting(false)
    }

    private func enter() {
        guard !entered else { return }
        withAnimation(Motion.adaptive(
            Motion.standard.delay(Double(index) * 0.06), reduceMotion: reduceMotion)) {
            entered = true
        }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.6)) {
            floating = true
        }
    }

    private func tapEffects() {
        if reduceMotion {  // static flash instead of pulse + bloom
            ringScale = 1
            ringOpacity = 0.5
            withAnimation(.easeOut(duration: 0.4)) { ringOpacity = 0 }
            return
        }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) { pulsing = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { pulsing = false }
        }
        ringScale = 1
        ringOpacity = 0.7
        withAnimation(.easeOut(duration: 0.5)) {
            ringScale = 1.55
            ringOpacity = 0
        }
    }
}
