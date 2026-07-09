//
//  LevelMeter.swift
//  HUMMI
//
//  Horizontal input level bar on a dB scale (−60…0 dBFS). Fills with a
//  gradient that warms toward the accent's hot end as it peaks, with a
//  thin peak marker. Level eases out over ~150 ms on release.
//

import SwiftUI

struct LevelMeter: View {
    let rms: Float
    let peak: Float

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color.accentColor, Color(.systemOrange)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: width)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(width * normalized(rms), 0))
                    }
                    .animation(.easeOut(duration: 0.15), value: rms)
                Capsule()
                    .fill(Color(.label))
                    .frame(width: 2)
                    .offset(x: width * normalized(peak))
                    .opacity(peak > 0.02 ? 1 : 0)   // no marker at rest
            }
        }
        .accessibilityHidden(true)
    }

    private func normalized(_ level: Float) -> CGFloat {
        guard level > 0 else { return 0 }
        let decibels = 20 * log10(level)
        return CGFloat(min(max((decibels + 60) / 60, 0), 1))
    }
}

#if DEBUG
private struct MeterGallery: View {
    var body: some View {
        VStack(spacing: Spacing.l) {
            LevelMeter(rms: 0.08, peak: 0.3).frame(height: 10)
            LevelMeter(rms: 0.5, peak: 0.85).frame(height: 10)
            LevelMeter(rms: 0.9, peak: 1.0).frame(height: 10)
        }
        .padding(Spacing.m)
        .tint(.accentColor)
    }
}

#Preview("Light") { MeterGallery().preferredColorScheme(.light) }
#Preview("Dark") { MeterGallery().preferredColorScheme(.dark) }
#endif
