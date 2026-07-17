//
//  DecorOrb.swift
//  HUMMI
//
//  A soft 3D sphere: base color with a specular highlight up-left and a
//  shaded lower rim, floating on a tinted shadow. Purely decorative —
//  sprinkled behind hero cards for depth.
//

import SwiftUI

struct DecorOrb: View {
    var color: Color
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            // Lower-rim shading gives the sphere its volume.
            Circle().fill(
                RadialGradient(
                    colors: [.clear, .black.opacity(0.18)],
                    center: UnitPoint(x: 0.38, y: 0.3),
                    startRadius: size * 0.2, endRadius: size * 0.62))
            // Specular highlight.
            Ellipse()
                .fill(.white.opacity(0.65))
                .frame(width: size * 0.3, height: size * 0.18)
                .blur(radius: size * 0.05)
                .offset(x: -size * 0.18, y: -size * 0.24)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.4), radius: size * 0.2, y: size * 0.1)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: Spacing.l) {
        DecorOrb(color: .pink, size: 40)
        DecorOrb(color: .indigo, size: 64)
        DecorOrb(color: .mint, size: 28)
    }
    .padding(Spacing.xl)
}
#endif
