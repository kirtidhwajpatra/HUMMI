//
//  OnboardingSupport.swift
//  HUMMI
//
//  Shared onboarding scaffolding: staggered appearance and a common
//  scrolling layout with a pinned action area (keeps CTAs reachable at
//  large Dynamic Type).
//

import SwiftUI

/// Fades and lifts an element in, delayed by its index (60 ms each, up to
/// 3). Reduce Motion drops the offset for a plain crossfade.
struct StaggeredAppear: ViewModifier {
    let index: Int
    let appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .animation(
                (reduceMotion ? Motion.reducedCrossfade : Motion.standard)
                    .delay(Double(min(index, 2)) * 0.06),
                value: appeared)
    }
}

extension View {
    func staggered(_ index: Int, appeared: Bool) -> some View {
        modifier(StaggeredAppear(index: index, appeared: appeared))
    }
}

/// Scrollable content column with a pinned bottom action area.
struct OnboardingLayout<Content: View, Actions: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.l) { content() }
                    .frame(maxWidth: Spacing.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.xl)
            }
            VStack(spacing: Spacing.s) { actions() }
                .frame(maxWidth: Spacing.contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.m)
        }
    }
}
