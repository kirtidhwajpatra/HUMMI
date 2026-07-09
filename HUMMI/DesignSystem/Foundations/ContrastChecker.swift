//
//  ContrastChecker.swift
//  HUMMI
//
//  Design system — WCAG contrast utilities plus a DEBUG overlay that
//  flags text/background pairs failing AA (4.5:1). SwiftUI can't scan
//  arbitrary rendered glyphs, so text drawn with the DS uses
//  `.dsContrastAudit(foreground:on:)` at its site to opt into the check.
//

import SwiftUI
import UIKit

nonisolated enum ContrastChecker {
    /// Minimum WCAG AA ratio for normal text.
    static let aaNormal = 4.5

    /// Contrast ratio (1…21) between two colours resolved for `scheme`.
    @MainActor
    static func ratio(_ a: Color, on b: Color, scheme: ColorScheme) -> Double {
        let la = luminance(of: a, scheme: scheme)
        let lb = luminance(of: b, scheme: scheme)
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    @MainActor
    private static func luminance(of color: Color, scheme: ColorScheme) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

extension View {
    /// DEBUG-only audit: overlays a small ⚠︎ badge when `foreground` on
    /// `background` fails WCAG AA in the current color scheme.
    func dsContrastAudit(foreground: Color, on background: Color) -> some View {
        modifier(ContrastAuditModifier(foreground: foreground, background: background))
    }
}

private struct ContrastAuditModifier: ViewModifier {
    let foreground: Color
    let background: Color
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        #if DEBUG
        content.overlay(alignment: .topTrailing) {
            let ratio = ContrastChecker.ratio(foreground, on: background, scheme: scheme)
            if ratio < ContrastChecker.aaNormal {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.black, .yellow)
                    .padding(1)
                    .background(.yellow, in: Circle())
                    .help(String(format: "Contrast %.1f:1 (needs 4.5:1)", ratio))
                    .offset(x: 6, y: -6)
                    .allowsHitTesting(false)
            }
        }
        #else
        content
        #endif
    }
}
