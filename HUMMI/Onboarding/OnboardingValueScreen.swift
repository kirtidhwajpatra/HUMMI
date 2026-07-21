//
//  OnboardingValueScreen.swift
//  HUMMI
//
//  Screen 1 — the promise, heard not read: a big brand masthead over a
//  self-playing before/after demo. The waveform swaps every three
//  seconds; the chips tell you which voice you're hearing.
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
            masthead
                .staggered(0, appeared: appeared)

            demoHero
                .staggered(1, appeared: appeared)

            Text("Record one honest take. One tap later it sounds like you rented the room, the mic and the engineer.")
                .font(.callout)
                .foregroundStyle(Brand.ink.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.s)
                .staggered(2, appeared: appeared)
        } actions: {
            GlowPillButton(title: "Continue", icon: "arrow.right", feel: .prominent) {
                onContinue()
            }
            .accessibilityHint(Text("Shows the next onboarding step"))
        }
        .overlay(alignment: .topTrailing) { skipButton }
        .onAppear { appeared = true; updatePlayback() }
        .onDisappear { demo.stop() }
        .onChange(of: isActive) { _, _ in updatePlayback() }
        .onChange(of: scenePhase) { _, _ in updatePlayback() }
        .onChange(of: demo.isPlayingAfter) { _, isAfter in announce(isAfter) }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(spacing: Spacing.s) {
            VoiceLogo(variant: .wordmark, tint: Brand.ink.opacity(0.9), height: 30)
            VStack(spacing: 0) {
                Text("SING IT ROUGH.")
                    .foregroundStyle(Brand.ink)
                Text("HEAR IT STUDIO.")
                    .foregroundStyle(Brand.limeDeep)
            }
            .font(.system(size: 34, weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        }
        .padding(.top, Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var waveLive: (() -> Double)? {
        reduceMotion ? nil : { demo.currentFraction() }
    }
    private var waveProgress: Double? {
        reduceMotion ? demo.currentFraction() : nil
    }

    // MARK: - Demo hero

    private var demoHero: some View {
        VStack(spacing: Spacing.m) {
            WaveformView(
                peaks: demo.currentPeaks,
                tint: Brand.ink.opacity(0.15),
                progress: waveProgress,
                live: waveLive,
                playedTint: demo.isPlayingAfter ? Brand.limeDeep : Brand.ink.opacity(0.45))
                .frame(height: 110)
                .animation(Motion.standard, value: demo.isPlayingAfter)

            HStack(spacing: Spacing.xs) {
                indicatorChip("Before", active: !demo.isPlayingAfter)
                indicatorChip("After", active: demo.isPlayingAfter)
            }
        }
        .padding(Spacing.m)
        .background(Brand.ink.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Brand.ink.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Before and after demo"))
        .accessibilityValue(Text(demo.isPlayingAfter
            ? "Playing the studio version" : "Playing the raw recording"))
    }

    /// The brand selection inversion: the active side is forest + lime.
    private func indicatorChip(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                if active {
                    Capsule().fill(Brand.forest)
                } else {
                    Capsule().fill(Brand.ink.opacity(0.06))
                }
            }
            .foregroundStyle(active ? Brand.lime : Brand.ink.opacity(0.6))
            .animation(Motion.micro, value: active)
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip")
                .font(.callout.weight(.medium))
                .foregroundStyle(Brand.ink.opacity(0.5))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.trailing, Spacing.s)
        .accessibilityHint(Text("Skips onboarding"))
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
        AccessibilityNotification.Announcement(
            isAfter ? "Playing the studio version" : "Playing the raw recording").post()
    }
}
