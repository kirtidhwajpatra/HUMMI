//
//  AppBranding.swift
//  HUMMI
//

import SwiftUI

/// Single source of truth for the product name and accent used across the
/// app and in exported media.
nonisolated enum AppBranding {
    static let name = "Ollin"

    /// Accent RGB (Electric Indigo), for CoreGraphics export.
    static let accentRGBA: (r: Double, g: Double, b: Double, a: Double) =
        (0.360, 0.220, 0.990, 1.0)

    static var accentColor: Color {
        Color(red: accentRGBA.r, green: accentRGBA.g, blue: accentRGBA.b)
    }

    static let watermarkText = "Made with \(name)"
}
