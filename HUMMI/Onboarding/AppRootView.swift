//
//  AppRootView.swift
//  HUMMI
//
//  The app's root. On launch the animated splash plays, then the tree
//  swaps to onboarding (first run) or the main app. Onboarding is gated by
//  @AppStorage and never re-shown once done. A conditional full-screen swap
//  (rather than `.fullScreenCover`) is used so dismissals can spring and so
//  the main app's audio session isn't activated beneath the onboarding demo.
//

import SwiftUI

struct AppRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashScreen(reduceMotion: reduceMotion) {
                    withAnimation(reduceMotion
                        ? Motion.reducedCrossfade
                        : .spring(response: 0.5, dampingFraction: 0.9)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(2)
            } else if hasCompletedOnboarding {
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

    /// Headless/debug launches that drive the main app skip onboarding and
    /// the splash so automation isn't blocked by the intro animation.
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
        if args.contains("--skip-splash") || bypass.contains(where: args.contains) {
            showSplash = false
        }
        #endif
    }
}
