//
//  ProgressPill.swift
//  HUMMI
//
//  A compact capsule status indicator on ultra-thin material with a
//  spinner and label. Scale-fades in and out.
//

import SwiftUI

struct ProgressPill: View {
    let label: String
    /// 0…1 when determinate; nil shows an indeterminate spinner.
    var value: Double?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let value {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
                    .frame(width: 60)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(label)
                .font(.dsCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

#if DEBUG
private struct PillGallery: View {
    var body: some View {
        VStack(spacing: Spacing.m) {
            ProgressPill(label: "Enhancing your vocals…")
            ProgressPill(label: "Rendering video 55%", value: 0.55)
        }
        .padding(Spacing.m)
        .tint(.accentColor)
    }
}

#Preview("Light") { PillGallery().preferredColorScheme(.light) }
#Preview("Dark") { PillGallery().preferredColorScheme(.dark) }
#Preview("A11y2 · RTL") {
    PillGallery().dynamicTypeSize(.accessibility2).environment(\.layoutDirection, .rightToLeft)
}
#endif
