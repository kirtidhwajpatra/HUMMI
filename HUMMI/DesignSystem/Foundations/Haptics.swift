//
//  Haptics.swift
//  HUMMI
//
//  Design system — haptic vocabulary, mapped to SwiftUI SensoryFeedback.
//  One event = one feedback; never chain. Apply with
//  `.sensoryFeedback(Haptic.x, trigger: value)`.
//

import SwiftUI

nonisolated enum Haptic {
    /// Recording began.
    static let recordStart = SensoryFeedback.impact(weight: .light)
    /// Recording stopped.
    static let recordStop = SensoryFeedback.impact(weight: .medium)
    /// Enhancement finished — the celebratory moment.
    static let enhancementComplete = SensoryFeedback.success
    /// A/B (Before/After) switch.
    static let toggle = SensoryFeedback.selection
    /// Preset changed.
    static let presetChange = SensoryFeedback.selection
    /// Primary CTA tapped.
    static let ctaTap = SensoryFeedback.impact(weight: .medium)
}
