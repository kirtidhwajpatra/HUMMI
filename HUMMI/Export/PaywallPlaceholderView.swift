//
//  PaywallPlaceholderView.swift
//  HUMMI
//

import SwiftUI

/// Placeholder paywall shown when a free-tier gate is hit (exports over
/// 60 s, or removing the watermark). No StoreKit yet — the "Continue"
/// button is inert; a DEBUG unlock flips the Pro flag for testing.
struct PaywallPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    let reason: Reason

    enum Reason: Identifiable {
        case longExport
        case removeWatermark

        var id: String { headline }

        var headline: String {
            switch self {
            case .longExport: return "Export longer takes"
            case .removeWatermark: return "Remove the watermark"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(AppBranding.accentColor)

            Text("\(AppBranding.name) Pro")
                .font(.largeTitle.bold())

            Text(reason.headline)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                feature("Export takes of any length")
                feature("Remove the watermark from videos")
                feature("Everything in the free tier")
            }
            .padding(.top, 8)

            Spacer()

            Button {
                // No StoreKit yet.
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(true)

            Text("Purchasing isn't available yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            #if DEBUG
            Button("Unlock Pro (debug)") {
                ProStore.shared.isPro = true
                dismiss()
            }
            .font(.footnote)
            #endif

            Button("Not now") { dismiss() }
                .padding(.top, 4)
        }
        .padding(28)
        .presentationDetents([.medium, .large])
    }

    private func feature(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppBranding.accentColor)
            Text(text)
            Spacer()
        }
    }
}
