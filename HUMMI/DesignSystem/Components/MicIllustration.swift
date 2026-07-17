//
//  MicIllustration.swift
//  HUMMI
//
//  Minimalist line-art microphone with sound arcs and accent sparkles,
//  drawn in code so it scales and tints with the theme. Used for empty
//  states.
//

import SwiftUI

struct MicIllustration: View {
    var lineWidth: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            let ink = GraphicsContext.Shading.color(.secondary.opacity(0.75))

            // Mic body — a capsule.
            let bodyRect = CGRect(x: w * 0.42, y: h * 0.12, width: w * 0.16, height: h * 0.38)
            context.stroke(
                Path(roundedRect: bodyRect, cornerRadius: bodyRect.width / 2),
                with: ink, style: stroke)

            // Grill lines.
            for fraction in [0.32, 0.44] {
                var line = Path()
                line.move(to: CGPoint(x: w * 0.455, y: h * fraction))
                line.addLine(to: CGPoint(x: w * 0.545, y: h * fraction))
                context.stroke(line, with: ink, style: stroke)
            }

            // Cradle arc around the body's lower half.
            var cradle = Path()
            cradle.addArc(
                center: CGPoint(x: w * 0.5, y: h * 0.42),
                radius: w * 0.15,
                startAngle: .degrees(200), endAngle: .degrees(-20), clockwise: true)
            context.stroke(cradle, with: ink, style: stroke)

            // Stem and base.
            var stem = Path()
            stem.move(to: CGPoint(x: w * 0.5, y: h * 0.57))
            stem.addLine(to: CGPoint(x: w * 0.5, y: h * 0.68))
            stem.move(to: CGPoint(x: w * 0.40, y: h * 0.68))
            stem.addLine(to: CGPoint(x: w * 0.60, y: h * 0.68))
            context.stroke(stem, with: ink, style: stroke)

            // Sound arcs left and right.
            let accent = GraphicsContext.Shading.color(Color.accentColor)
            for (direction, x) in [(false, 0.26), (true, 0.74)] {
                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: w * x, y: h * 0.3),
                    radius: w * 0.07,
                    startAngle: .degrees(direction ? -60 : 240),
                    endAngle: .degrees(direction ? 60 : 120),
                    clockwise: !direction)
                context.stroke(arc, with: accent, style: stroke)
            }

            // Accent sparkles.
            for (x, y, r) in [(0.68, 0.1, 0.016), (0.3, 0.52, 0.012), (0.78, 0.5, 0.011)] {
                let dot = CGRect(
                    x: w * x - w * r, y: h * y - w * r,
                    width: w * r * 2, height: w * r * 2)
                context.fill(Path(ellipseIn: dot), with: accent)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    MicIllustration()
        .frame(width: 180, height: 160)
        .padding()
}
#endif
