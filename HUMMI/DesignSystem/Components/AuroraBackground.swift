//
//  AuroraBackground.swift
//  HUMMI
//
//  The home screen's canvas: plain white (black in dark mode). While the
//  singer's voice is in the room a faint lime glow breathes behind the
//  centre — the one whisper of life it keeps.
//

import SwiftUI

struct AuroraBackground: View {
    /// 0…1 — feed the recording RMS here; silence keeps the canvas still.
    var energy: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(uiColor: UIColor { traits in 
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.04, alpha: 1.0) : UIColor(white: 0.96, alpha: 1.0) 
        })
            .overlay(
                RadialGradient(
                    colors: [Brand.lime.opacity(0.10 + 0.20 * Double(min(energy * 2.5, 1))), .clear],
                    center: .center, startRadius: 0, endRadius: 420)
                    .opacity(energy > 0.001 ? 1 : 0)
            )
            .animation(.easeOut(duration: 0.35), value: energy)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
