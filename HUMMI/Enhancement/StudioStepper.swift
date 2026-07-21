//
//  StudioStepper.swift
//  HUMMI
//
//  A minimal −/＋ stepper for precise, discrete nudges (Speed, Tempo,
//  Pitch). Each step ticks a light haptic; the range bounds tick firmer.
//  Shows a reset affordance when the value is off its filter preset.
//

import SwiftUI

struct StudioStepper: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let preset: Double
    let format: (Double) -> String
    var onChange: () -> Void = {}

    private var isOffPreset: Bool { abs(value - preset) > 0.0001 }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(label).font(.subheadline)
            if isOffPreset { resetButton }
            Spacer(minLength: Spacing.s)

            HStack(spacing: 0) {
                stepButton("minus", enabled: value > range.lowerBound + 0.0001) { adjust(-step) }
                Text(format(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Brand.forest)
                    .frame(minWidth: 66)
                    .contentTransition(.numericText())
                stepButton("plus", enabled: value < range.upperBound - 0.0001) { adjust(step) }
            }
            .background(Brand.ink.opacity(0.06), in: Capsule())
        }
        .animation(Motion.micro, value: value)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(enabled ? Brand.forest : Brand.ink.opacity(0.25))
                .frame(width: 42, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var resetButton: some View {
        Button {
            value = preset
            Haptics.shared.play(.light)
            onChange()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset \(label)")
    }

    private func adjust(_ delta: Double) {
        let raw = value + delta
        let snapped = (raw / step).rounded() * step
        let clamped = min(max(snapped, range.lowerBound), range.upperBound)
        guard abs(clamped - value) > 0.0001 else { Haptics.shared.play(.rigid); return }
        value = clamped
        let atBound = clamped <= range.lowerBound + 0.0001 || clamped >= range.upperBound - 0.0001
        Haptics.shared.play(atBound ? .medium : .light)
        onChange()
    }
}
