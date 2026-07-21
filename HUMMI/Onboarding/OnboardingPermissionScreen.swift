//
//  OnboardingPermissionScreen.swift
//  HUMMI
//
//  Screen 3 — a custom explainer immediately before the system mic
//  prompt, leading with the on-device privacy promise. The app is never
//  held hostage: after a denial the user can open Settings or continue.
//

import AVFoundation
import SwiftUI
import UIKit

struct OnboardingPermissionScreen: View {
    /// Called once the screen is done (granted, or the user chose to
    /// continue), so onboarding can complete regardless of the outcome.
    let onComplete: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared = false
    @State private var isDenied = false
    @State private var isRequesting = false
    @State private var grantTick = 0

    private let badges: [(symbol: String, label: String)] = [
        ("lock.shield", "Private"),
        ("iphone.gen3", "On-device"),
        ("wifi.slash", "No uploads"),
    ]

    var body: some View {
        OnboardingLayout {
            masthead
                .staggered(0, appeared: appeared)

            Text("HUMMI listens only while you record, and everything is processed right here on this iPhone. No cloud, no uploads, no exceptions.")
                .font(.callout)
                .foregroundStyle(Brand.ink.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.s)
                .staggered(1, appeared: appeared)

            badgeRow
                .staggered(2, appeared: appeared)

            if isDenied {
                deniedHint
                    .transition(.opacity)
            }
        } actions: {
            if isDenied {
                GlowPillButton(title: "Open Settings", icon: "gear",
                               tint: Brand.forest, foreground: Brand.lime, feel: .standard) {
                    openSettings()
                }

                Button(action: onComplete) {
                    Text("Continue anyway")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Brand.ink.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                GlowPillButton(title: "Enable Microphone", icon: "mic.fill",
                               feel: .prominent, isBusy: isRequesting) {
                    Task { await requestPermission() }
                }
                .accessibilityHint(Text("Shows the system microphone permission prompt"))
            }
        }
        .animation(Motion.standard, value: isDenied)
        .sensoryFeedback(.success, trigger: grantTick)
        .onAppear { appeared = true }
        .onChange(of: scenePhase) { _, phase in
            // Returning from Settings having granted → complete.
            if phase == .active, isDenied, isGranted { onComplete() }
        }
    }

    private var masthead: some View {
        VStack(spacing: Spacing.xs) {
            Text("ONE LAST THING")
                .font(.footnote.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Brand.ink.opacity(0.55))
            VStack(spacing: 0) {
                Text("YOUR VOICE")
                    .foregroundStyle(Brand.ink)
                Text("STAYS HERE.")
                    .foregroundStyle(Brand.ink)
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

    private var badgeRow: some View {
        HStack(spacing: Spacing.s) {
            ForEach(badges, id: \.symbol) { badge in
                VStack(spacing: Spacing.xs) {
                    Image(systemName: badge.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Brand.ink)
                        .frame(width: 40, height: 40)
                        .background(Brand.ink.opacity(0.06), in: Circle())
                    Text(badge.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Brand.ink.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.m)
                .background(Brand.ink.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.ink.opacity(0.1), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var deniedHint: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
            Text("Microphone access is off. You can record after enabling it in Settings.")
                .font(.footnote)
        }
        .foregroundStyle(Brand.ink.opacity(0.7))
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(Brand.ink.opacity(0.05), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var isGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    private func requestPermission() async {
        isRequesting = true
        let granted = await AVAudioApplication.requestRecordPermission()
        isRequesting = false
        if granted {
            grantTick += 1   // .success haptic
            onComplete()
        } else {
            isDenied = true
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
