//
//  Typography.swift
//  HUMMI
//
//  Design system — type tokens. All are SF Pro system fonts driven by
//  Dynamic Type; sizes are only ever set through Font.system text styles,
//  never hardcoded points. Weight rules:
//   • .regular  — body copy
//   • .semibold — section headers
//   • .bold     — reserved for the primary CTA and Before/After labels
//

import SwiftUI

extension Font {
    /// Screen / hero title.
    static var dsTitle: Font { .system(.title2, weight: .semibold) }
    /// Section header.
    static var dsSectionHeader: Font { .system(.headline, weight: .semibold) }
    /// Body copy.
    static var dsBody: Font { .system(.body) }
    /// Secondary / supporting copy.
    static var dsCallout: Font { .system(.callout) }
    /// Captions, metadata.
    static var dsCaption: Font { .system(.caption) }
    /// Primary CTA label — the one place `.bold` is the default.
    static var dsCTA: Font { .system(.headline, weight: .bold) }
    /// Before/After toggle labels — the other sanctioned `.bold`.
    static var dsToggleLabel: Font { .system(.body, weight: .bold) }

    /// Onboarding hero headline (Screen 1). Bold is sanctioned here: it is
    /// the single hero element of a first-run screen, per the onboarding
    /// spec — a deliberate, contained exception to "bold reserved".
    static var dsHeroTitle: Font { .system(.title, weight: .bold) }
    /// Onboarding headline for the tip / permission screens.
    static var dsHeroTitleCompact: Font { .system(.title2, weight: .bold) }
}
