//
//  StudioPanelSheet.swift
//  HUMMI
//
//  Advanced sliders over the selected Character/Space filters. Every
//  slider is absolute — selecting a filter seeds it with that filter's
//  value — and shows a per-row reset back to the filter's setting.
//

import SwiftUI

struct StudioPanelSheet: View {
    @Bindable var viewModel: ResultViewModel
    @Environment(\.dismiss) private var dismiss

    private var character: RealtimePreviewSettings { viewModel.selectedCharacter.settings }

    var body: some View {
        NavigationStack {
            Form {
                contextHeader
                voiceSection
                eqSection
                spaceSection
                characterSection
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Studio Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset All") { viewModel.resetToPreset(); viewModel.applyRealtimePreview() }
                        .disabled(!viewModel.isCustomized)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        // The sheet floats as glass over the studio canvas — the orbs show
        // through, so the panel feels like part of the same room. It
        // follows the device appearance like the rest of the screen.
        .presentationBackground(.ultraThinMaterial)
    }

    private var contextHeader: some View {
        Section {
            HStack(spacing: Spacing.m) {
                Image(systemName: viewModel.selectedCharacter.glyph)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(colors: viewModel.selectedCharacter.colors,
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.selectedCharacter.name) · \(viewModel.selectedSpace.name)")
                        .font(.headline)
                    Text("Sliders start at this filter's settings and apply live.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var voiceSection: some View {
        Section {
            slider("Speed", value: $viewModel.voiceSpeed, range: 0.75...1.25,
                   preset: character.speed, text: "×\(format(viewModel.voiceSpeed, "%.2f"))")
            slider("Tempo", value: $viewModel.voiceTempo, range: 0.75...1.25,
                   preset: character.tempo, text: "×\(format(viewModel.voiceTempo, "%.2f"))")
            slider("Pitch", value: $viewModel.voicePitch, range: -12...12, step: 1,
                   preset: character.pitch, text: "\(format(viewModel.voicePitch, "%+.0f")) st")
        } header: {
            Text("Voice")
        } footer: {
            Text("Speed changes pitch too, like tape. Tempo keeps pitch. Pitch makes the voice deeper or lighter.")
        }
    }

    private var eqSection: some View {
        Section {
            slider("Low · 100 Hz", value: $viewModel.eqLow, range: -12...12, step: 0.5,
                   preset: character.lowGain, text: "\(format(viewModel.eqLow, "%+.1f")) dB")
            slider("Mid · 1 kHz", value: $viewModel.eqMid, range: -12...12, step: 0.5,
                   preset: character.midGain, text: "\(format(viewModel.eqMid, "%+.1f")) dB")
            slider("High · 8 kHz", value: $viewModel.eqHigh, range: -12...12, step: 0.5,
                   preset: character.highGain, text: "\(format(viewModel.eqHigh, "%+.1f")) dB")
        } header: {
            Text("Tone")
        } footer: {
            Text("Low adds body, mid adds presence, high adds air.")
        }
    }

    private var spaceSection: some View {
        Section {
            slider("Amount", value: $viewModel.reverbAmount, range: 0...100,
                   preset: viewModel.selectedSpace.amount,
                   text: "\(format(viewModel.reverbAmount, "%.0f"))%")
            slider("Decay", value: $viewModel.reverbDecay, range: 0.2...4, step: 0.1,
                   preset: viewModel.selectedSpace.decay,
                   text: "\(format(viewModel.reverbDecay, "%.1f")) s")
        } header: {
            Text("Space")
        } footer: {
            Text("Amount sets how much of the room you hear; Decay resizes it, overriding the selected Space filter.")
        }
    }

    private var characterSection: some View {
        Section {
            slider("Saturation", value: $viewModel.saturation, range: 0...100,
                   preset: character.saturation,
                   text: "\(format(viewModel.saturation, "%.0f"))%")
            slider("Autotune", value: $viewModel.autotuneStrength, range: 0...1,
                   preset: character.autotune,
                   text: "\(format(viewModel.autotuneStrength * 100, "%.0f"))%")
            if viewModel.isTuningPreview {
                HStack(spacing: Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Tuning preview…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Character")
        } footer: {
            Text("Saturation adds tape-style warmth. Autotune snaps sung notes to key — it takes a moment to preview.")
        }
    }

    private func slider(
        _ label: String, value: Binding<Double>, range: ClosedRange<Double>,
        step: Double? = nil, preset: Double, text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Text(label)
                Spacer()
                if abs(value.wrappedValue - preset) > 0.001 {
                    Button {
                        value.wrappedValue = preset
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset \(label)")
                }
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Group {
                if let step {
                    Slider(value: value, in: range, step: step)
                } else {
                    Slider(value: value, in: range)
                }
            }
            .tint(viewModel.selectedCharacter.dominant)
            .onChange(of: value.wrappedValue) { _, _ in viewModel.applyRealtimePreview() }
        }
        .padding(.vertical, 2)
        .animation(Motion.micro, value: abs(value.wrappedValue - preset) > 0.001)
    }

    private func format(_ value: Double, _ format: String) -> String { String(format: format, value) }
}
