//
//  GlowPillButton.swift
//  HUMMI
//
//  The app's signature action button: a "gel" capsule — soft radial
//  colour, gooey glossy rim, and a coloured glow beneath — modelled on
//  the reference gradient-blend pills. Every press has a physical feel
//  (role-specific haptic + click), pressing squishes the gel, and a
//  button that runs a process narrates it itself: spinner + label swap +
//  pulsing rim, then a success thump when the work lands.
//

import AudioToolbox
import SwiftUI
import UIKit

/// How a button should feel: a paired haptic + sound, so different kinds
/// of action are physically distinguishable without looking.
enum ButtonFeel {
    /// Light tap + soft tock — everyday actions.
    case standard
    /// Medium thump + brighter click — the screen's main action.
    case prominent
    /// Warning buzz + low click — discard / cancel / delete.
    case destructive
    /// Selection tick only, no sound — small utility taps.
    case quiet

    func play() {
        switch self {
        case .standard:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AudioServicesPlaySystemSound(1104)
        case .prominent:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            AudioServicesPlaySystemSound(1103)
        case .destructive:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            AudioServicesPlaySystemSound(1102)
        case .quiet:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// The "your process finished" thump, played when a busy button settles.
    static func playSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct GlowPillButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Brand.forest
    /// Label colour — deep forest on lime surfaces, white on dark ones.
    var foreground: Color = Brand.lime
    var feel: ButtonFeel = .standard
    /// Toolbar-sized variant: hugs its text instead of filling the row.
    var compact = false
    /// While true the button narrates the work: spinner, `busyTitle`,
    /// pulsing rim; taps are ignored. Flipping back to false plays the
    /// success haptic.
    var isBusy = false
    var busyTitle: String? = nil
    /// Optional 0…1 progress — fills the capsule from the leading edge
    /// and appends a percentage while busy.
    var progress: Double? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var rimPulse = false

    var body: some View {
        Button {
            guard !isBusy else { return }
            feel.play()
            action()
        } label: {
            HStack(spacing: Spacing.xs) {
                if isBusy {
                    ProgressView().tint(foreground).controlSize(compact ? .mini : .small)
                } else if let icon {
                    Image(systemName: icon)
                        .font(compact ? .footnote.weight(.semibold) : .body.weight(.semibold))
                }
                Text(label)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .monospacedDigit()
                    .fixedSize()  // toolbars try to crush pills to one glyph
                    .contentTransition(.opacity)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? Spacing.m : Spacing.l)
            .padding(.vertical, compact ? Spacing.xs : Spacing.m)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(GelBackground(tint: tint, shape: Capsule(), progress: isBusy ? progress : nil))
            .overlay {
                if isBusy {
                    Capsule()
                        .stroke(.white.opacity(0.55), lineWidth: 1.5)
                        .blur(radius: 2)
                        .opacity(rimPulse ? 0.9 : 0.25)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                rimPulse = true
                            }
                        }
                        .onDisappear { rimPulse = false }
                }
            }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .saturation(isEnabled ? 1 : 0.25)
        .opacity(isEnabled ? 1 : 0.55)
        .onChange(of: isBusy) { was, now in
            if was, !now { ButtonFeel.playSuccess() }
        }
        .animation(Motion.micro, value: isBusy)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isBusy ? .updatesFrequently : [])
    }

    private var label: String {
        guard isBusy else { return title }
        let base = busyTitle ?? title
        if let progress { return "\(base) \(Int(progress * 100))%" }
        return base
    }
}

/// Icon-only sibling of GlowPillButton: a NATIVE Liquid Glass capsule —
/// system glass, system press response. A two-tier hierarchy so the eye
/// finds the important control instantly: `.primary` is lime with a
/// forest glyph; `.secondary` is its exact inverse — forest with a lime
/// glyph; `.quiet` is plain ink chrome for anything that should recede.
/// A toggled-ON button always goes full lime.
struct GlowIconButton: View {
    enum Style { case primary, secondary, quiet }

    let icon: String
    let label: String
    var tint: AnyShapeStyle? = nil
    var foreground: Color? = nil
    var style: Style = .secondary
    var feel: ButtonFeel = .standard
    /// Toggles (like the script button) go full lime while on.
    var isActive = false
    var size = CGSize(width: 80, height: 54)
    var isBusy = false
    var weight: Font.Weight = .semibold
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            guard !isBusy else { return }
            feel.play()
            action()
        } label: {
            Group {
                if isBusy {
                    ProgressView().tint(Brand.ink)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: size.height * 0.4, weight: weight))
                        .foregroundStyle(glyphStyle)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: size.width, height: size.height)
            .background {
                if let tint {
                    Rectangle().fill(tint)
                } else if isActive || style == .primary {
                    Brand.forest
                } else if style == .secondary {
                    Brand.limeGradient
                } else {
                    Brand.ink.opacity(0.07)
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .saturation(isEnabled ? 1 : 0.25)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(Motion.micro, value: isActive)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var glyphStyle: AnyShapeStyle {
        if let foreground { return AnyShapeStyle(foreground) }
        if isActive || style == .primary { return AnyShapeStyle(Brand.limeGradient) }
        if style == .secondary { return AnyShapeStyle(Brand.forest) }
        return AnyShapeStyle(Brand.ink)
    }
}

/// The gel material itself: tint gradient body, gooey blurred white rim,
/// top sheen, and (optionally) a leading progress fill.
private struct GelBackground<S: InsettableShape>: View {
    let tint: Color
    let shape: S
    let progress: Double?

    var body: some View {
        ZStack(alignment: .leading) {
            shape.fill(tint)
            if let progress {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                        .animation(Motion.progress, value: progress)
                }
            }
        }
        .clipShape(shape)
    }
}

/// Squish + glow-tighten on press, with a soft haptic on finger-down so
/// the gel responds before the action even fires.
private struct GelPressStyle: ButtonStyle {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.95 : 1))
            .brightness(configuration.isPressed ? -0.05 : 0)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.32 : 0.48),
                    radius: configuration.isPressed ? 8 : 16,
                    y: configuration.isPressed ? 4 : 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
                }
            }
    }
}
