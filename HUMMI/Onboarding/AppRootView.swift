//
//  AppRootView.swift
//  HUMMI
//
//  The app's root: shows onboarding until it completes, then the main
//  app. Gated by @AppStorage — onboarding is never re-shown once done.
//  A conditional full-screen swap (rather than `.fullScreenCover`) is
//  used so the dismiss can spring and so the main app's audio session
//  isn't activated beneath the onboarding demo.
//

import SwiftUI

struct AppRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if hasCompletedOnboarding {
                ContentView()
                    .transition(.opacity)
            } else {
                RootOnboardingView { hasCompletedOnboarding = true }
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion ? Motion.reducedCrossfade : .spring(response: 0.4, dampingFraction: 0.85),
            value: hasCompletedOnboarding)
        .onAppear(perform: applyDebugBypass)
    }

    /// Headless/debug launches that drive the main app skip onboarding.
    private func applyDebugBypass() {
        #if DEBUG
        let bypass = ["--skip-onboarding", "--record-autorun", "--result-autorun",
                      "--open-recordings", "--pipeline-autorun", "--profile-autorun",
                      "--spike-autorun", "--export-autorun"]
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reset-onboarding") {
            hasCompletedOnboarding = false
        } else if bypass.contains(where: args.contains) {
            hasCompletedOnboarding = true
        }
        #endif
    }
}
