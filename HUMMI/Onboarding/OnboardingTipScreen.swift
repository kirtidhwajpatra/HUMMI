//
//  OnboardingTipScreen.swift
//  HUMMI
//
//  Screen 2 — one expectation to make the first result hit the wow bar:
//  quiet room, phone ~20 cm away, earphones on.
//

import SwiftUI

struct OnboardingTipScreen: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = false

    private let tips: [(symbol: String, textKey: LocalizedStringKey)] = [
        ("speaker.wave.2", "onboarding.screen2.tip.quiet"),
        ("iphone", "onboarding.screen2.tip.distance"),
        ("headphones", "onboarding.screen2.tip.earphones"),
    ]

    var body: some View {
        OnboardingLayout {
            if typeSize < .accessibility3 {
                illustration.staggered(0, appeared: appeared)
            }

            Text("onboarding.screen2.headline")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .staggered(1, appeared: appeared)

            VStack(alignment: .leading, spacing: Spacing.m) {
                ForEach(tips, id: \.symbol) { tip in
                    bullet(symbol: tip.symbol, textKey: tip.textKey)
                }
            }
            .staggered(2, appeared: appeared)
        } actions: {
            Button {
                onContinue()
            } label: {
                Label(NSLocalizedString("onboarding.continue", comment: ""), systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(Text("onboarding.continue.hint"))

            Button(action: onBack) {
                Text("onboarding.back")
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .onAppear { appeared = true }
    }

    /// SF Symbols composition: a person singing into a phone at ~20 cm.
    private var illustration: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "person.wave.2")
                .symbolRenderingMode(.hierarchical)
            Image(systemName: "arrow.left.and.right")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
            Image(systemName: "iphone")
                .symbolRenderingMode(.hierarchical)
        }
        .font(.system(size: 56))  // iconographic illustration, not body text
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("onboarding.screen2.illustration"))
    }

    private func bullet(symbol: String, textKey: LocalizedStringKey) -> some View {
        Label {
            Text(textKey).font(.body)
        } icon: {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
