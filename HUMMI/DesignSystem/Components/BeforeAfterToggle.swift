//
//  BeforeAfterToggle.swift
//  HUMMI
//
//  The emotional core: a native segmented Picker styled taller with bold
//  labels and an accent-driven selection. Switching is instant (the audio
//  A/B swap is wired by the caller); this adds a selection haptic, a short
//  crossfade, and a one-time intro on first appearance. Announces
//  "Before" / "After" to VoiceOver.
//

import SwiftUI
import UIKit

struct BeforeAfterToggle: View {
    /// false = Before (original), true = After (enhanced).
    @Binding var isAfter: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        Picker("Compare original and enhanced", selection: $isAfter) {
            Text("Before").font(.dsToggleLabel).tag(false)
            Text("After").font(.dsToggleLabel).tag(true)
        }
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .frame(width: 230)
        .animation(Motion.micro, value: isAfter)
        .sensoryFeedback(Haptic.toggle, trigger: isAfter)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
        .opacity(appeared || reduceMotion ? 1 : 0.6)
        .onAppear {
            Self.configureAppearance()
            withAnimation(reduceMotion ? Motion.reducedCrossfade
                          : .spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Compare")
        .accessibilityValue(isAfter ? "After, enhanced" : "Before, original")
        .accessibilityHint("Switches audio between the original and enhanced take")
        .accessibilityAddTraits(.isButton)
    }

    /// Bold labels and an accent selection on the shared segmented control
    /// (the app has exactly one, so the global proxy is safe).
    private static func configureAppearance() {
        let proxy = UISegmentedControl.appearance()
        proxy.selectedSegmentTintColor = UIColor(named: "AccentColor")
        let bold = UIFont.preferredFont(forTextStyle: .body).withBoldTraits()
        proxy.setTitleTextAttributes(
            [.font: bold, .foregroundColor: UIColor.white], for: .selected)
        proxy.setTitleTextAttributes(
            [.font: bold, .foregroundColor: UIColor.label], for: .normal)
    }
}

private extension UIFont {
    func withBoldTraits() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

#if DEBUG
private struct TogglePreview: View {
    @State private var isAfter = true
    var body: some View {
        BeforeAfterToggle(isAfter: $isAfter)
            .padding(Spacing.m)
            .tint(.accentColor)
    }
}

#Preview("Light") { TogglePreview().preferredColorScheme(.light) }
#Preview("Dark") { TogglePreview().preferredColorScheme(.dark) }
#Preview("A11y2 · RTL") {
    TogglePreview().dynamicTypeSize(.accessibility2).environment(\.layoutDirection, .rightToLeft)
}
#endif
