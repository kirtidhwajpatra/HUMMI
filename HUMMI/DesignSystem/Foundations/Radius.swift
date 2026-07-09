//
//  Radius.swift
//  HUMMI
//
//  Design system — corner radii. Always `.continuous`.
//

import SwiftUI

nonisolated enum Radius {
    /// 12 — cards and list rows.
    static let card: CGFloat = 12
    /// 16 — sheets and large containers.
    static let sheet: CGFloat = 16
    /// 22 — the primary CTA.
    static let cta: CGFloat = 22

    /// A continuous rounded rectangle at the given radius.
    static func rect(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension View {
    /// Clips to a continuous rounded rectangle — the house corner style.
    func dsCorner(_ radius: CGFloat) -> some View {
        clipShape(Radius.rect(radius))
    }
}
