//
//  RootOnboardingView.swift
//  HUMMI
//
//  The onboarding container: a horizontally paged TabView (custom step
//  indicator, default dots hidden). Screens 1↔2 swipe freely; the
//  permission screen is only reachable via the tip screen's Continue.
//

import SwiftUI

struct RootOnboardingView: View {
    /// Called when onboarding completes (grant, deny+continue, or skip).
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int
    @State private var canReachPermission: Bool
    @State private var continueTick = 0

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        var start = 0
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--onboarding-page"),
           i + 1 < args.count, let value = Int(args[i + 1]) {
            start = value
        }
        #endif
        _page = State(initialValue: start)
        _canReachPermission = State(initialValue: start >= 2)
    }

    var body: some View {
        ZStack {
            FluidBackground(colors: [.indigo, .blue, .cyan])
                .opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                StepIndicator(count: 3, activeIndex: page)
                    .padding(.top, Spacing.m)
                    .padding(.bottom, Spacing.xs)
    
                TabView(selection: $page) {
                    OnboardingValueScreen(
                        isActive: page == 0,
                        onContinue: { advance(to: 1) },
                        onSkip: onFinish)
                        .tag(0)
    
                    OnboardingTipScreen(
                        onContinue: {
                            canReachPermission = true
                            advance(to: 2)
                        },
                        onBack: { advance(to: 0) })
                        .tag(1)
    
                    OnboardingPermissionScreen(onComplete: onFinish)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background(Color(.systemBackground))
        .sensoryFeedback(Haptic.toggle, trigger: continueTick)
        .animation(pageAnimation, value: page)
        .onChange(of: page) { _, newValue in
            // Block swiping forward into the permission screen before the
            // tip screen's Continue has been used.
            if newValue == 2, !canReachPermission { page = 1 }
        }
    }

    private var pageAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)
    }

    private func advance(to newPage: Int) {
        continueTick += 1
        page = newPage
    }
}
