//
//  PlaylistIcon.swift
//  HUMMI
//
//  The custom playlist/menu glyph: a short lighter bar above a longer
//  darker bar, left-aligned. Built as shapes (not an SF Symbol) to match
//  the brand mark exactly.
//

import SwiftUI

struct PlaylistIcon: View {
    /// Overall glyph width; bars scale to it.
    var width: CGFloat = 22

    private var barHeight: CGFloat { width * 0.22 }

    var body: some View {
        VStack(alignment: .leading, spacing: width * 0.24) {
            Capsule(style: .continuous)
                .fill(Color(.systemGray))
                .frame(width: width * 0.62, height: barHeight)
            Capsule(style: .continuous)
                .fill(Color(.secondaryLabel))
                .frame(width: width, height: barHeight)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Light") {
    PlaylistIcon()
        .frame(width: 44, height: 44)
        .background(Color(.secondarySystemBackground), in: Circle())
        .padding()
}
#Preview("Dark") {
    PlaylistIcon()
        .frame(width: 44, height: 44)
        .background(Color(.secondarySystemBackground), in: Circle())
        .padding()
        .preferredColorScheme(.dark)
}
#endif
