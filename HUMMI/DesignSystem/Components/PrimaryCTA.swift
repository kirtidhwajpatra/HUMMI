//
//  PrimaryCTA.swift
//  HUMMI
//
//  The "Make it sound studio" button archetype: full-width, 60pt tall,
//  22pt continuous radius, accent fill, bold label. Idle breathes gently;
//  press springs; loading swaps the label for a spinner; disabled goes
//  quiet. One soft accent glow — the only shadow in the system.
//

import SwiftUI

struct PrimaryCTA: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isSecondary: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var tapTrigger = 0

    private var breathingActive: Bool { isEnabled && !isLoading && !reduceMotion }

    var body: some View {
        Button {
            tapTrigger += 1
            action()
        } label: {
            ZStack {
                label.opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(isSecondary ? Color(.systemBackground) : .white)
                }
            }
            .font(.dsCTA)
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(backgroundStyle, in: Radius.rect(Radius.cta))
        }
        .buttonStyle(PressStyle(reduceMotion: reduceMotion))
        .disabled(isLoading)
        .scaleEffect(breathe && breathingActive ? 1.02 : 1.0)
        .shadow(color: isEnabled ? (isSecondary ? Color.primary.opacity(0.1) : Color.accentColor.opacity(0.15)) : .clear, radius: 20, x: 0, y: 0)
        .sensoryFeedback(Haptic.ctaTap, trigger: tapTrigger)
        .onChange(of: breathingActive, initial: true) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            } else {
                withAnimation(Motion.reducedCrossfade) { breathe = false }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? Text("Working") : Text(""))
    }

    private var label: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)
            }
            Text(title)
        }
    }

    private var foregroundStyle: Color {
        if isEnabled {
            return isSecondary ? Color(.systemBackground) : .white
        } else {
            return Color(.tertiaryLabel)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        if isEnabled {
            return isSecondary ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color(.tertiarySystemFill))
        }
    }

    private struct PressStyle: ButtonStyle {
        let reduceMotion: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
                .opacity(reduceMotion && configuration.isPressed ? 0.85 : 1)
                .animation(Motion.standard, value: configuration.isPressed)
        }
    }
}

#if DEBUG
private struct CTAGallery: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            PrimaryCTA(title: "Make it sound studio", systemImage: "sparkles") {}
            PrimaryCTA(title: "Enhancing", systemImage: "sparkles", isLoading: true) {}
            PrimaryCTA(title: "Make it sound studio", systemImage: "sparkles") {}
                .disabled(true)
        }
        .padding(Spacing.m)
        .tint(.accentColor)
    }
}

#Preview("Light") { CTAGallery().preferredColorScheme(.light) }
#Preview("Dark") { CTAGallery().preferredColorScheme(.dark) }
#Preview("A11y2 · RTL") {
    CTAGallery()
        .dynamicTypeSize(.accessibility2)
        .environment(\.layoutDirection, .rightToLeft)
}
#endif
