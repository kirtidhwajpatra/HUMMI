//
//  StudioPanelSheet.swift
//  HUMMI
//
//  Advanced controls over the selected Character/Space filters. Each
//  section uses the control that fits what it does — steppers for precise
//  voice nudges, a graphic EQ for tone, level meters for "amount" values,
//  and segmented pickers for the things that are really presets (room
//  size, autotune, cleanup). Every control is haptic and applies live.
//

import SwiftUI

struct StudioPanelSheet: View {
    @Bindable var viewModel: ResultViewModel
    @Environment(\.dismiss) private var dismiss

    private var character: RealtimePreviewSettings { viewModel.selectedCharacter.settings }

    // Preset lists for the segmented sections.
    private let decayValues: [Double] = [0.4, 0.8, 1.4, 2.3, 3.5]
    private let decayLabels = ["Small", "Medium", "Large", "Hall", "Cathedral"]
    private let autotuneValues: [Double] = [0, 0.34, 0.67, 1.0]
    private let autotuneLabels = ["Off", "Subtle", "Medium", "Hard"]

    var body: some View {
        NavigationStack {
            Form {
                contextHeader
                voiceSection
                toneSection
                spaceSection
                characterSection
                cleanupSection
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Studio Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset All") {
                        viewModel.resetToPreset(); viewModel.applyRealtimePreview()
                        Haptics.shared.notify(.success)
                    }
                    .disabled(!viewModel.isCustomized)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Header

    private var contextHeader: some View {
        Section {
            HStack(spacing: Spacing.m) {
                ZStack {
                    // Brand swatch — filters carry no colour of their own.
                    Circle()
                        .fill(Brand.limeGradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: viewModel.selectedCharacter.glyph)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Brand.forest)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.selectedCharacter.name) · \(viewModel.selectedSpace.name)")
                        .font(.headline)
                    Text("Controls start at this filter and apply live.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Voice (steppers)

    private var voiceSection: some View {
        Section {
            StudioStepper(label: "Speed", value: $viewModel.voiceSpeed,
                          range: 0.75...1.25, step: 0.05, preset: character.speed,
                          format: { "×\(String(format: "%.2f", $0))" }, onChange: apply)
            StudioStepper(label: "Tempo", value: $viewModel.voiceTempo,
                          range: 0.75...1.25, step: 0.05, preset: character.tempo,
                          format: { "×\(String(format: "%.2f", $0))" }, onChange: apply)
            StudioStepper(label: "Pitch", value: $viewModel.voicePitch,
                          range: -12...12, step: 1, preset: character.pitch,
                          format: { "\(String(format: "%+.0f", $0)) st" }, onChange: apply)
        } header: {
            Text("Voice")
        } footer: {
            Text("Speed changes pitch too, like tape. Tempo keeps pitch. Pitch shifts it in semitones.")
        }
    }

    // MARK: - Tone (graphic EQ)

    private var toneSection: some View {
        Section {
            StudioEQControl(
                low: $viewModel.eqLow, mid: $viewModel.eqMid, high: $viewModel.eqHigh,
                presets: (character.lowGain, character.midGain, character.highGain),
                range: -12...12, onChange: apply)
                .padding(.vertical, Spacing.xs)
        } header: {
            Text("Tone")
        } footer: {
            Text("Drag a band up to boost, down to cut. Double-tap a band to reset it.")
        }
    }

    // MARK: - Space (meter + rooms)

    private var spaceSection: some View {
        Section {
            StudioLevelMeter(label: "Amount", value: $viewModel.reverbAmount,
                             range: 0...100, preset: viewModel.selectedSpace.amount,
                             format: { "\(String(format: "%.0f", $0))%" }, onChange: apply)

            StudioSegmented(label: "Room", options: decayLabels,
                            selectedIndex: decayIndex) { i in
                viewModel.reverbDecay = decayValues[i]; apply()
            }
        } header: {
            Text("Space")
        } footer: {
            Text("Amount sets how much room you hear; Room resizes it, overriding the Space filter.")
        }
    }

    // MARK: - Character (meter + segmented)

    private var characterSection: some View {
        Section {
            StudioLevelMeter(label: "Saturation", value: $viewModel.saturation,
                             range: 0...100, preset: character.saturation,
                             format: { "\(String(format: "%.0f", $0))%" }, onChange: apply)

            StudioSegmented(label: "Autotune", options: autotuneLabels,
                            selectedIndex: autotuneIndex) { i in
                viewModel.autotuneStrength = autotuneValues[i]; apply()
            }
            if viewModel.isTuningPreview {
                progressRow("Tuning preview…")
            }
        } header: {
            Text("Character")
        } footer: {
            Text("Saturation adds tape warmth. Autotune snaps sung notes to key — it takes a moment to preview.")
        }
    }

    // MARK: - Cleanup (segmented)

    private var cleanupSection: some View {
        Section {
            StudioSegmented(label: "Noise Reduction",
                            options: NoiseReductionLevel.allCases.map(\.title),
                            selectedIndex: noiseIndex) { i in
                viewModel.noiseRemoval = NoiseReductionLevel.allCases[i].rawValue
                viewModel.scheduleNoiseReductionPreview()
            }
            if viewModel.isUpdatingNoiseReduction {
                progressRow("Applying cleanup…")
            }
        } header: {
            Text("Cleanup")
        } footer: {
            Text("Uses AI to remove background noise. Higher settings might affect vocal tone.")
        }
    }

    // MARK: - Helpers

    private func apply() { viewModel.applyRealtimePreview() }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            ProgressView().controlSize(.small)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// Nearest room bucket for the current decay time.
    private var decayIndex: Int {
        switch viewModel.reverbDecay {
        case ..<0.5: 0
        case ..<1.0: 1
        case ..<1.8: 2
        case ..<2.8: 3
        default: 4
        }
    }

    private var autotuneIndex: Int { nearestIndex(viewModel.autotuneStrength, in: autotuneValues) }

    private var noiseIndex: Int {
        nearestIndex(viewModel.noiseRemoval, in: NoiseReductionLevel.allCases.map(\.rawValue))
    }

    private func nearestIndex(_ value: Double, in options: [Double]) -> Int {
        options.enumerated().min(by: { abs($0.1 - value) < abs($1.1 - value) })?.offset ?? 0
    }
}
