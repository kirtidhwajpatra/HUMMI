//
//  StudioArtwork.swift
//  HUMMI
//

import SwiftUI

/// Shared editorial art treatment. The generated hero gives the app a
/// recognizable visual signature; the orbiting chips are native so they stay
/// responsive, accessible, and light to render.
struct StudioArtwork: View {
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        ZStack {
            Image("StudioHero")
                .resizable()
                .scaledToFill()
                .offset(y: compact ? 28 : 8)
                .scaleEffect(compact ? 1.22 : 1.04)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.10)],
                startPoint: .center, endPoint: .bottom)

            if !compact {
                floatingChip(symbol: "waveform", tint: .blue)
                    .offset(x: -112, y: -62)
                floatingChip(symbol: "sparkles", tint: .orange)
                    .offset(x: 112, y: 42)
            }
        }
        .frame(height: compact ? 150 : 290)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 24 : 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 24 : 32, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: Color.indigo.opacity(0.16), radius: 22, y: 12)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
        .accessibilityHidden(true)
    }

    private func floatingChip(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.title3.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .rotationEffect(.degrees(isFloating ? 8 : -5))
            .offset(y: isFloating ? -6 : 5)
    }
}

/// A code-native visual used where a full image would be too heavy: recording
/// and empty states still feel intentional rather than utilitarian.
struct VocalAura: View {
    var tint: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16)).frame(width: 142, height: 142)
                .scaleEffect(pulse ? 1.08 : 0.88)
            Circle().stroke(tint.opacity(0.35), lineWidth: 1).frame(width: 116, height: 116)
                .scaleEffect(pulse ? 0.9 : 1.04)
            Image(systemName: "mic.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(height: 150)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}
