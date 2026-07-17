//
//  DynamicGradientBackground.swift
//  HUMMI
//

import SwiftUI

struct DynamicGradientBackground: View {
    var style: AppBackgroundStyle = .plain
    var intensity: Double = 0.5
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// In dark mode the pastels render as a restrained glow over the
    /// system background — dimming them heavily just turns them muddy.
    private var effectiveIntensity: Double {
        colorScheme == .dark ? intensity * 0.42 : intensity
    }

    var body: some View {
        Group {
            if style == .plain {
                colorScheme == .dark ? Color.black : Color.white
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                        let colors = style.colors
                        let opacity = 0.8 * effectiveIntensity

                        for (i, color) in colors.enumerated() {
                            let speed = Double(i + 1) * 0.1
                            let xOffset = sin(t * speed) * size.width * 0.4
                            let yOffset = cos(t * speed * 0.8) * size.height * 0.4

                            let centerX = size.width / 2 + xOffset
                            let centerY = size.height / 2 + yOffset

                            let rect = CGRect(
                                x: centerX - size.width * 0.8,
                                y: centerY - size.width * 0.8,
                                width: size.width * 1.6,
                                height: size.width * 1.6
                            )

                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(color.opacity(opacity))
                            )
                        }
                    }
                    .blur(radius: 80)
                }
            }
        }
        .ignoresSafeArea()
    }
}
