//
//  VoiceLogo.swift
//  HUMMI
//
//  The brand mark: the "VOICE" wordmark whose "O" is a musical note. Two
//  variants — the wordmark alone, or the wordmark stacked over "STUDIO".
//  Both ship as template vectors so a single `tint` recolours them; they
//  scale crisply to any size. This is the one place the logo art is wired
//  up, so every screen that shows the brand pulls from here.
//

import SwiftUI

struct VoiceLogo: View {
    enum Variant {
        case wordmark   // "VOICE" only
        case full       // "VOICE" over "STUDIO"

        var assetName: String {
            switch self {
            case .wordmark: return "VoiceLogo"
            case .full: return "VoiceLogoFull"
            }
        }

        /// Native artwork aspect ratio (width / height), for stable layout.
        var aspectRatio: CGFloat {
            switch self {
            case .wordmark: return 767.0 / 537.0
            case .full: return 768.0 / 654.0
            }
        }
    }

    var variant: Variant = .wordmark
    var tint: Color = Brand.ink
    /// Target height; width follows the artwork aspect ratio.
    var height: CGFloat = 40

    var body: some View {
        Image(variant.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(tint)
            .frame(height: height)
            .frame(width: height * variant.aspectRatio)
            .accessibilityLabel(Text("VOICE Studio"))
    }
}

#Preview {
    VStack(spacing: 32) {
        VoiceLogo(variant: .wordmark, tint: Brand.forest, height: 60)
        VoiceLogo(variant: .full, tint: Brand.limeDeep, height: 120)
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Brand.canvas)
}
