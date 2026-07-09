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

    private let badges: [(symbol: String, textKey: LocalizedStringKey)] = [
        ("lock.shield", "onboarding.screen3.badge.private"),
        ("iphone.gen3", "onboarding.screen3.badge.ondevice"),
        ("wifi.slash", "onboarding.screen3.badge.noupload"),
    ]

    var body: some View {
        OnboardingLayout {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .staggered(0, appeared: appeared)

            VStack(spacing: Spacing.s) {
                Text("onboarding.screen3.headline")
                    .font(.dsHeroTitleCompact)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("onboarding.screen3.body")
                    .font(.dsBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .staggered(1, appeared: appeared)
            .accessibilityElement(children: .combine)

            badgeRow
                .staggered(2, appeared: appeared)

            if isDenied {
                InlineHint(
                    text: NSLocalizedString("onboarding.screen3.denied.body", comment: ""),
                    systemImage: "exclamationmark.triangle")
                    .transition(.opacity)
            }
        } actions: {
            if isDenied {
                Button {
                    openSettings()
                } label: {
                    Text("onboarding.screen3.openSettings")
                        .font(.dsCallout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button(action: onComplete) {
                    Text("onboarding.screen3.continueAnyway")
                        .font(.dsCallout)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            } else {
                PrimaryCTA(title: NSLocalizedString("onboarding.screen3.enable", comment: ""),
                           systemImage: "mic.fill", isLoading: isRequesting) {
                    Task { await requestPermission() }
                }
                .accessibilityHint(Text("onboarding.screen3.enable.hint"))
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

    private var badgeRow: some View {
        HStack(spacing: Spacing.l) {
            ForEach(badges, id: \.symbol) { badge in
                VStack(spacing: Spacing.xs) {
                    Image(systemName: badge.symbol)
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    Text(badge.textKey)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
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
