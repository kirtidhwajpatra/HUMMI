//
//  IconTile.swift
//  HUMMI
//
//  A gradient squircle icon tile with a top light edge and a tinted
//  soft shadow — the "rich app" icon treatment, used in Settings rows,
//  Profile stats, and feature callouts.
//

import SwiftUI

struct IconTile: View {
    let systemImage: String
    var colors: [Color]
    var size: CGFloat = 32

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: colors,
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: shape)
            .overlay(
                // Light catching the top edge.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
            .shadow(color: (colors.first ?? .black).opacity(0.35),
                    radius: size * 0.16, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: Spacing.m) {
        IconTile(systemImage: "paintbrush.fill", colors: [.purple, .indigo])
        IconTile(systemImage: "sparkles", colors: [.pink, .orange])
        IconTile(systemImage: "waveform", colors: [.red, .pink], size: 44)
    }
    .padding()
}
#endif
