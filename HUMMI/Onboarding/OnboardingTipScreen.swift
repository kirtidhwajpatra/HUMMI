//
//  OnboardingTipScreen.swift
//  HUMMI
//
//  Screen 2 — three quiet cards that make the first take land: a quiet
//  room, the right distance, earphones for the reveal.
//

import SwiftUI

struct OnboardingTipScreen: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false

    private let tips: [(symbol: String, title: String, caption: String)] = [
        ("speaker.wave.2",
         "Find somewhere quiet",
         "Every hum and echo in the room ends up in the take."),
        ("iphone",
         "Phone about 20 cm away",
         "Close enough to be intimate, far enough not to pop."),
        ("headphones",
         "Earphones for the reveal",
         "The before/after hits much harder in your ears."),
    ]

    var body: some View {
        OnboardingLayout {
            masthead
                .staggered(0, appeared: appeared)

            VStack(spacing: Spacing.s) {
                ForEach(Array(tips.enumerated()), id: \.element.symbol) { index, tip in
                    tipCard(tip)
                        .staggered(index + 1, appeared: appeared)
                }
            }
        } actions: {
            GlowPillButton(title: "Continue", icon: "arrow.right", feel: .prominent) {
                onContinue()
            }
            .accessibilityHint(Text("Shows the next onboarding step"))

            Button(action: onSkip) {
                Text("Skip")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Brand.ink.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .onAppear { appeared = true }
    }

    private var masthead: some View {
        VStack(spacing: Spacing.xs) {
            Text("BEFORE YOU SING")
                .font(.footnote.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Brand.ink.opacity(0.55))
            Text("SET THE SCENE.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Brand.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(.top, Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func tipCard(_ tip: (symbol: String, title: String, caption: String)) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: tip.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Brand.ink)
                .frame(width: 40, height: 40)
                .background(Brand.ink.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.ink)
                Text(tip.caption)
                    .font(.footnote)
                    .foregroundStyle(Brand.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(Brand.ink.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Brand.ink.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
