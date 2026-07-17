//
//  SupportingViews.swift
//  HUMMI
//
//  Small shared building blocks: SectionHeader, InlineHint, EmptyStateView.
//

import SwiftUI

/// A quiet, semibold section label.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.dsSectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A coachmark-style inline hint on thin material.
struct InlineHint: View {
    let text: String
    var systemImage: String = "lightbulb"

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text(text)
                .font(.dsCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: Radius.rect(Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Native empty-state, wrapped so screens share one look.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var message: String?

    var body: some View {
        VStack(spacing: Spacing.s) {
            VocalAura(tint: .accentColor)
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }
        }
        .padding(Spacing.l)
    }
}

#if DEBUG
private struct SupportingGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionHeader(title: "Adjust")
            InlineHint(text: "Tap After to hear the studio version.")
            EmptyStateView(
                title: "No recordings yet",
                systemImage: "waveform",
                message: "Record a take or import an audio file.")
                .frame(height: 220)
        }
        .padding(Spacing.m)
        .tint(.accentColor)
    }
}

#Preview("Light") { SupportingGallery().preferredColorScheme(.light) }
#Preview("Dark") { SupportingGallery().preferredColorScheme(.dark) }
#Preview("A11y2 · RTL") {
    SupportingGallery().dynamicTypeSize(.accessibility2).environment(\.layoutDirection, .rightToLeft)
}
#endif
