//
//  StudioTheme.swift
//  HUMMI
//
//  Canvas tokens for the Studio screen. The screen follows the device
//  appearance: a soft light canvas by default, and the near-black
//  "Aurora" canvas only in dark mode, where the orbs and tiles glow.
//  Either way the filters are the colour — nothing else competes.
//

import SwiftUI
import UIKit

enum StudioTheme {
    /// Light: the brand's off-white canvas. Dark: near-black with a hint
    /// of warmth — never pure black.
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 10 / 255, green: 12 / 255, blue: 8 / 255, alpha: 1)
            : UIColor(red: 244 / 255, green: 247 / 255, blue: 240 / 255, alpha: 1)
    })
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(.tertiaryLabel)

    /// Barely-there depth: a soft centre lift, only visible on the dark
    /// canvas (a white wash disappears on the light one).
    static var vignette: some View {
        RadialGradient(colors: [.white.opacity(0.05), .clear],
                       center: .center, startRadius: 0, endRadius: 420)
            .allowsHitTesting(false)
    }
}

/// A static film-grain wash — tiny seeded dots, drawn once. Used inside
/// space tiles (4%) and the vintage orb (8%) for a filmic quality.
struct StudioNoise: View {
    var opacity: Double = 0.04

    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: 0x5EED)
            for _ in 0..<Int(size.width * size.height / 55) {
                let rect = CGRect(x: .random(in: 0..<size.width, using: &rng),
                                  y: .random(in: 0..<size.height, using: &rng),
                                  width: 1, height: 1)
                let shade = Double.random(in: 0...1, using: &rng)
                context.fill(Path(rect), with: .color(.white.opacity(shade)))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    /// Deterministic so the grain never shimmers between renders.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
}
