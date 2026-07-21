//
//  StudioEQControl.swift
//  HUMMI
//
//  A three-band graphic EQ. Drag a band up to boost, down to cut; the
//  centre line is 0 dB with a firm haptic detent, and every dB ticks as it
//  passes. Double-tap a band to reset it to the filter preset. This is the
//  Tone section — deliberately not a row of sliders.
//

import SwiftUI

struct StudioEQControl: View {
    @Binding var low: Double
    @Binding var mid: Double
    @Binding var high: Double
    let presets: (low: Double, mid: Double, high: Double)
    let range: ClosedRange<Double>
    var onChange: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            EQBand(name: "LOW", hint: "100 Hz", value: $low,
                   preset: presets.low, range: range, onChange: onChange)
            EQBand(name: "MID", hint: "1 kHz", value: $mid,
                   preset: presets.mid, range: range, onChange: onChange)
            EQBand(name: "HIGH", hint: "8 kHz", value: $high,
                   preset: presets.high, range: range, onChange: onChange)
        }
    }
}

private struct EQBand: View {
    let name: String
    let hint: String
    @Binding var value: Double
    let preset: Double
    let range: ClosedRange<Double>
    var onChange: () -> Void

    private let trackHeight: CGFloat = 132
    private let knob: CGFloat = 26
    @State private var lastTick = 0

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(gainText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(abs(value) < 0.05 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Brand.forest))
                .contentTransition(.numericText())

            track

            VStack(spacing: 0) {
                Text(name).font(.caption2.weight(.bold)).foregroundStyle(Brand.forest)
                Text(hint).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var track: some View {
        GeometryReader { geo in
            let travel = trackHeight - knob
            let knobY = knob / 2 + (1 - fraction) * travel
            let centerY = trackHeight / 2

            ZStack {
                Capsule()
                    .fill(Brand.ink.opacity(0.08))
                    .frame(width: 6)

                Rectangle()
                    .fill(Brand.ink.opacity(0.18))
                    .frame(height: 1.5)
                    .offset(y: 0)

                // Boost/cut fill between the 0 dB line and the knob.
                Capsule()
                    .fill(Brand.limeGradient)
                    .frame(width: 6, height: abs(knobY - centerY))
                    .position(x: geo.size.width / 2, y: (knobY + centerY) / 2)

                Circle()
                    .fill(Brand.limeGradient)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: Brand.forest.opacity(0.25), radius: 4, y: 2)
                    .position(x: geo.size.width / 2, y: knobY)
            }
            .frame(maxWidth: .infinity)
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { setFrom($0.location.y) })
            .onTapGesture(count: 2) {
                value = preset; Haptics.shared.play(.medium); onChange()
            }
        }
        .frame(height: trackHeight)
    }

    private var gainText: String {
        abs(value) < 0.05 ? "0" : String(format: "%+.1f", value)
    }

    private func setFrom(_ y: CGFloat) {
        let travel = trackHeight - knob
        let f = min(max(1 - Double((y - knob / 2) / travel), 0), 1)
        var newValue = range.lowerBound + f * (range.upperBound - range.lowerBound)
        // Snap to 0 dB near the centre so it's easy to land flat.
        if abs(newValue) < 0.6 { newValue = 0 }
        newValue = (newValue / 0.5).rounded() * 0.5
        guard abs(newValue - value) > 0.0001 else { return }

        let crossedZero = (value < 0 && newValue >= 0) || (value > 0 && newValue <= 0)
        value = newValue
        if crossedZero || newValue == 0 {
            Haptics.shared.play(.medium)   // firm detent at flat
        } else if Int(newValue) != lastTick {
            Haptics.shared.play(.rigid)    // per-dB tick
        }
        lastTick = Int(newValue)
        onChange()
    }
}
