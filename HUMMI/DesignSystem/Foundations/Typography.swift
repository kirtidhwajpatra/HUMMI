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
    static var dsTitle: Font { .system(.title2, design: .rounded).weight(.black) }
    /// Section header.
    static var dsSectionHeader: Font { .system(.headline, design: .rounded).weight(.black) }
    /// Body copy.
    static var dsBody: Font { .system(.body, design: .rounded) }
    /// Secondary / supporting copy.
    static var dsCallout: Font { .system(.callout, design: .rounded) }
    /// Captions, metadata.
    static var dsCaption: Font { .system(.caption, design: .rounded) }
    /// Primary CTA label — the one place `.bold` is the default.
    static var dsCTA: Font { .system(.headline, design: .rounded).weight(.bold) }
    /// Before/After toggle labels — the other sanctioned `.bold`.
    static var dsToggleLabel: Font { .system(.body, design: .rounded).weight(.bold) }

    /// Onboarding hero headline (Screen 1).
    /// Using `.black` weight to match the ultra-heavy display typography guidelines.
    static var dsHeroTitle: Font { .system(.title, design: .rounded).weight(.black) }
    /// Onboarding headline for the tip / permission screens.
    static var dsHeroTitleCompact: Font { .system(.title2, design: .rounded).weight(.black) }
}
