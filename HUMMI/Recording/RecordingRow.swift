//
//  RecordingRow.swift
//  HUMMI
//
//  One library entry: a play affordance, the take name (with a small note
//  badge when enhanced), its date, and duration.
//

import SwiftUI

struct RecordingRow: View {
    let item: RecordingItem
    var isPlaying: Bool = false
    var playbackProgress: Double? = nil
    var onPlayTapped: () -> Void = {}
    var onRowTapped: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.m) {
            Button(action: onPlayTapped) {
                playAffordance
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button(action: onRowTapped) {
                HStack(spacing: Spacing.m) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: Spacing.xs) {
                            Text(item.name)
                                .font(.headline)
                                .foregroundStyle(Brand.ink)
                                .lineLimit(1)
                            if item.isEnhanced { enhancedBadge }
                        }
                Text(item.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.subheadline)
                    .foregroundStyle(Brand.ink.opacity(0.5))
            }

            Spacer(minLength: Spacing.s)

                    WaveformView(
                        peaks: item.peaks,
                        tint: Brand.ink.opacity(0.22),
                        progress: playbackProgress,
                        style: .bars,
                        normalize: true,
                        playedTint: Brand.limeDeep)
                        .frame(width: 64, height: 24)

                    Text(durationText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Brand.ink.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Double tap to open Studio")
        }
    }

    private var playAffordance: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Brand.forest)
            .frame(width: 36, height: 36)
            .background(Brand.limeGradient, in: Circle())
            .shadow(color: Brand.limeDeep.opacity(0.25), radius: 8, y: 3)
            .accessibilityHidden(true)
    }

    private var enhancedBadge: some View {
        Image(systemName: "music.note")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Brand.forest)
            .frame(width: 18, height: 18)
            .background(Brand.lime, in: Circle())
            .accessibilityHidden(true)
    }

    private var durationText: String {
        let total = Int(item.duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var accessibilityText: String {
        let date = item.date.formatted(.dateTime.month(.abbreviated).day().year())
        let base = "\(item.name), \(date), \(durationText)"
        return item.isEnhanced ? "\(base), enhanced" : base
    }
}
