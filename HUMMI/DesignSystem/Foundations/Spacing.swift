//
//  Spacing.swift
//  HUMMI
//
//  Design system — spacing scale. The ONLY spacing values allowed in
//  refactored screens. 4 · 8 · 12 · 16 · 24 · 32 · 48.
//

import CoreGraphics

nonisolated enum Spacing {
    /// 4 — hairline gaps, icon-to-label.
    static let xxs: CGFloat = 4
    /// 8 — tight stacks, chip padding.
    static let xs: CGFloat = 8
    /// 12 — row internals, card padding.
    static let s: CGFloat = 12
    /// 16 — default screen gutters, between related controls.
    static let m: CGFloat = 16
    /// 24 — between sections.
    static let l: CGFloat = 24
    /// 32 — major section breaks.
    static let xl: CGFloat = 32
    /// 48 — hero spacing.
    static let xxl: CGFloat = 48

    /// Max width for primary content columns on iPad / large phones.
    static let contentMaxWidth: CGFloat = 640
}
