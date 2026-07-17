//
//  VoiceShapePanel.swift
//  HUMMI
//
//  The "Voice" controls under the Tone Filters carousel: Speed (pitch
//  follows, like tape), Tempo (pitch preserved) and Pitch (deeper ↔
//  lighter). Values live on ResultViewModel and survive filter switches;
//  Apply re-renders the take with the new shape.
//

import SwiftUI

struct VoiceShapePanel: View {
    @Bindable var viewModel: ResultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Voice")
                    .font(.title3.weight(.bold))

                Spacer()

                if viewModel.isVoiceShaped {
                    Button {
                        viewModel.resetVoiceShape()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    }
                    .disabled(viewModel.isRendering)
                    .accessibilityLabel("Reset voice shape")
                }

                if viewModel.isDirty {
                    Button("Apply") {
                        Task { await viewModel.applyAdjustments() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .disabled(viewModel.isRendering)
                }
            }
            .animation(Motion.micro, value: viewModel.isDirty)
            .animation(Motion.micro, value: viewModel.isVoiceShaped)

            row("Speed", value: $viewModel.voiceSpeed,
                range: VoiceShapeStage.rateRange,
                text: String(format: "×%.2f", viewModel.voiceSpeed))
            row("Tempo", value: $viewModel.voiceTempo,
                range: VoiceShapeStage.rateRange,
                text: String(format: "×%.2f", viewModel.voiceTempo))
            row("Pitch", value: $viewModel.voicePitch,
                range: VoiceShapeStage.pitchRange, step: 1,
                text: String(format: "%+.0f st", viewModel.voicePitch))

            Text("Speed changes pitch too, like tape. Tempo keeps pitch. Pitch makes the voice deeper or lighter.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(
        _ label: String, value: Binding<Double>,
        range: ClosedRange<Double>, step: Double? = nil, text: String
    ) -> some View {
        HStack(spacing: Spacing.s) {
            Text(label)
                .font(.subheadline)
                .frame(width: 56, alignment: .leading)
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .disabled(viewModel.isRendering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(text)")
    }
}
