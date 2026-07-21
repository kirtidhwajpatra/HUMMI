//
//  StudioLevelMeter.swift
//  HUMMI
//
//  A tap/drag level meter of discrete blocks — no thumb, it reads like a
//  VU meter, not a slider. Used for "amount" values (Reverb, Saturation).
//  Each block that flips ticks a crisp haptic.
//

import SwiftUI

struct StudioLevelMeter: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let preset: Double
    let format: (Double) -> String
    var onChange: () -> Void = {}

    private let blocks = 14

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? (value - range.lowerBound) / span : 0
    }
    private var filled: Int { Int((fraction * Double(blocks)).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text(label).font(.subheadline)
                if abs(value - preset) > 0.0001 { resetButton }
                Spacer()
                Text(format(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Brand.forest)
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(0..<blocks, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(i < filled
                                  ? AnyShapeStyle(Brand.limeGradient)
                                  : AnyShapeStyle(Brand.ink.opacity(0.1)))
                    }
                }
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { setFrom($0.location.x, width: geo.size.width) })
            }
            .frame(height: 28)
        }
        .animation(Motion.micro, value: filled)
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

    private func setFrom(_ x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let f = min(max(Double(x / width), 0), 1)
        let newFilled = Int((f * Double(blocks)).rounded())
        guard newFilled != filled else { return }
        Haptics.shared.play(.rigid)
        let newFraction = Double(newFilled) / Double(blocks)
        value = range.lowerBound + newFraction * (range.upperBound - range.lowerBound)
        onChange()
    }
}
