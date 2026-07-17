//
//  GlassCard.swift
//  HUMMI
//
//  The house card treatment: frosted glass over the animated gradient,
//  a light-catching top edge, and a soft drop shadow for depth.
//

import SwiftUI

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 18, y: 10)
    }
}

#if DEBUG
#Preview {
    VStack {
        Text("Frosted glass")
            .padding(Spacing.xl)
            .glassCard()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient(colors: [.pink.opacity(0.4), .indigo.opacity(0.4)],
                               startPoint: .top, endPoint: .bottom))
}
#endif
