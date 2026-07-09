//
//  OnboardingValueScreen.swift
//  HUMMI
//
//  Screen 1 — the value promise, shown in five seconds: a self-playing
//  before/after demo you can hear, not read about.
//

import SwiftUI

struct OnboardingValueScreen: View {
    /// True when this is the visible page (drives demo playback).
    let isActive: Bool
    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var demo = BeforeAfterDemoPlayer()
    @State private var appeared = false

    var body: some View {
        OnboardingLayout {
            demoHero
                .staggered(0, appeared: appeared)

            VStack(spacing: Spacing.s) {
                Text("onboarding.screen1.headline")
                    .font(.dsHeroTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityHeadingIfPossible()
                Text("onboarding.screen1.subhead")
                    .font(.dsBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .staggered(1, appeared: appeared)
            .accessibilityElement(children: .combine)
        } actions: {
            PrimaryCTA(title: continueTitle, systemImage: "arrow.right") {
                onContinue()
            }
            .accessibilityHint(Text("onboarding.continue.hint"))
        }
        .overlay(alignment: .topTrailing) { skipButton }
        .onAppear { appeared = true; updatePlayback() }
        .onDisappear { demo.stop() }
        .onChange(of: isActive) { _, _ in updatePlayback() }
        .onChange(of: scenePhase) { _, _ in updatePlayback() }
        .onChange(of: demo.isPlayingAfter) { _, isAfter in announce(isAfter) }
    }

    private var continueTitle: String { NSLocalizedString("onboarding.continue", comment: "") }

    private var waveLive: (() -> Double)? {
        reduceMotion ? nil : { demo.currentFraction() }
    }
    private var waveProgress: Double? {
        reduceMotion ? demo.currentFraction() : nil
    }

    // MARK: - Demo hero

    private var demoHero: some View {
        VStack(spacing: Spacing.m) {
            WaveformView(peaks: demo.currentPeaks, progress: waveProgress, live: waveLive)
                .frame(height: 120)
                .animation(Motion.standard, value: demo.isPlayingAfter)

            HStack(spacing: Spacing.xs) {
                indicatorChip("onboarding.screen1.before", active: !demo.isPlayingAfter)
                indicatorChip("onboarding.screen1.after", active: demo.isPlayingAfter)
            }
        }
        .padding(Spacing.m)
        .background(.thickMaterial, in: Radius.rect(Radius.sheet))
        .overlay(Radius.rect(Radius.sheet).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("onboarding.demo.label"))
        .accessibilityValue(Text(demo.isPlayingAfter
            ? "onboarding.demo.playingAfter" : "onboarding.demo.playingBefore"))
    }

    private func indicatorChip(_ key: LocalizedStringKey, active: Bool) -> some View {
        Text(key)
            .font(.dsToggleLabel)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: Capsule())
            .foregroundStyle(active ? Color.white : Color.secondary)
            .animation(Motion.micro, value: active)
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("onboarding.skip")
                .font(.dsCallout)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.trailing, Spacing.s)
        .accessibilityHint(Text("onboarding.skip.hint"))
    }

    // MARK: - Playback + a11y

    private func updatePlayback() {
        if isActive && scenePhase == .active {
            demo.start()
        } else {
            demo.pause()
        }
    }

    private func announce(_ isAfter: Bool) {
        let key = isAfter ? "onboarding.demo.playingAfter" : "onboarding.demo.playingBefore"
        AccessibilityNotification.Announcement(NSLocalizedString(key, comment: "")).post()
    }
}

private extension View {
    /// `.isHeader` for VoiceOver ordering (headline announced first).
    func accessibilityHeadingIfPossible() -> some View { accessibilityAddTraits(.isHeader) }
}
