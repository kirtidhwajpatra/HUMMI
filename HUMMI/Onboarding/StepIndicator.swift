//
//  StepIndicator.swift
//  HUMMI
//
//  Minimal three-dot page indicator: the active step is an accent pill,
//  the rest are quiet dots. Replaces the default TabView paging dots.
//

import SwiftUI

struct StepIndicator: View {
    let count: Int
    let activeIndex: Int

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == activeIndex ? Color.accentColor : Color(.tertiaryLabel))
                    .frame(width: index == activeIndex ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: activeIndex)
        .accessibilityElement()
        .accessibilityLabel(
            String(format: NSLocalizedString("onboarding.step", comment: ""),
                   activeIndex + 1, count))
    }
}

#if DEBUG
#Preview("Light") {
    VStack(spacing: Spacing.l) {
        StepIndicator(count: 3, activeIndex: 0)
        StepIndicator(count: 3, activeIndex: 1)
        StepIndicator(count: 3, activeIndex: 2)
    }
    .tint(.accentColor)
}
#Preview("Dark") {
    StepIndicator(count: 3, activeIndex: 1)
        .tint(.accentColor)
        .preferredColorScheme(.dark)
}
#endif
