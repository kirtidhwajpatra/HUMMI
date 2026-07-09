//
//  WaveformView.swift
//  HUMMI
//
//  Canvas waveform in two styles:
//   • .bars — accent/tertiary bars split at the playhead (live meters,
//     thumbnails)
//   • .line — a single smoothed oscillating stroke in one colour with a
//     playhead dot (the Result hero, matching the brand)
//  Playing mode samples the playhead per display frame via
//  TimelineView(.animation) for smooth motion.
//

import SwiftUI

enum WaveformStyle {
    case bars
    case line
}

struct WaveformView: View {
    let peaks: [Float]
    /// Bar/line colour. In `.bars` this tints the static bars; in `.line`
    /// it is the stroke colour.
    var tint: Color = Color(.tertiaryLabel)
    /// A fixed playhead position (0…1), or nil for a static waveform.
    var progress: Double?
    /// Per-frame playhead provider; when set, the view redraws each frame.
    var live: (() -> Double)?
    var style: WaveformStyle = .bars
    /// When true (default) the line auto-scales to its loudest sample.
    /// Set false for a live meter, where sample values map directly to
    /// height so quiet stays small and loud grows tall.
    var normalize: Bool = true
    /// Colour of the played (left-of-playhead) bars in `.bars`.
    var playedTint: Color = .accentColor
    /// Magnification center position (0…1) during scrubbing.
    var focusFraction: Double? = nil

    var body: some View {
        Group {
            if let live {
                TimelineView(.animation) { _ in
                    canvas(at: clamped(live()))
                }
            } else {
                canvas(at: progress.map(clamped))
            }
        }
        .accessibilityHidden(true)
    }

    private func clamped(_ value: Double) -> Double { min(max(value, 0), 1) }

    private func canvas(at playhead: Double?) -> some View {
        Canvas { context, size in
            switch style {
            case .bars: drawBars(context, size, playhead, focusFraction)
            case .line: drawLine(context, size, playhead)
            }
        }
    }

    // MARK: - Bars

    private func drawBars(_ context: GraphicsContext, _ size: CGSize, _ playhead: Double?, _ focus: Double?) {
        let barWidth: CGFloat = 3
        let spacing: CGFloat = 2
        let slot = barWidth + spacing
        let count = max(Int(size.width / slot), 1)
        let bars = Self.downsample(peaks, to: count)
        guard !bars.isEmpty else { return }
        let scale = 1 / max(bars.max() ?? 1, 0.05)
        let played = playedTint
        let upcoming = Color(.quaternaryLabel)

        for (index, peak) in bars.enumerated() {
            let x = CGFloat(index) * slot
            let height = max(size.height * CGFloat(min(peak * scale, 1)), 3)
            
            let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
            
            let color: Color
            if let playhead {
                color = (x + barWidth / 2) <= CGFloat(playhead) * size.width ? played : upcoming
            } else {
                color = tint
            }
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
            context.fill(path, with: .color(color))
        }
    }

    // MARK: - Line

    private func drawLine(_ context: GraphicsContext, _ size: CGSize, _ playhead: Double?) {
        let points = Self.linePoints(peaks, in: size, normalize: normalize)
        guard points.count > 1 else { return }
        context.stroke(
            Self.smoothPath(points),
            with: .color(tint),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        if let playhead {
            let x = CGFloat(playhead) * size.width
            let y = Self.interpolatedY(points, atX: x)
            let dot = CGRect(x: x - 5, y: y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot), with: .color(tint))
            context.stroke(Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)),
                           with: .color(tint.opacity(0.25)), lineWidth: 3)
        }
    }

    /// Sample points that oscillate around the vertical center by the
    /// real per-bucket amplitude, so the smoothed stroke reads as an
    /// organic hand-drawn waveform.
    private static func linePoints(_ peaks: [Float], in size: CGSize, normalize: Bool = true) -> [CGPoint] {
        let count = min(max(peaks.count, 2), 32)
        let bars = downsample(peaks, to: count)
        guard !bars.isEmpty else { return [] }
        let scale: Float = normalize ? 1 / max(bars.max() ?? 1, 0.05) : 1
        let centerY = size.height / 2
        let halfAmp = size.height / 2 * 0.92
        return bars.enumerated().map { index, peak in
            let x = size.width * CGFloat(index) / CGFloat(max(bars.count - 1, 1))
            let sign: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            // Small floor keeps quiet takes visible; the real amplitude
            // does the shaping so loud/soft moments swing wide/narrow.
            let amplitude = 0.1 + 0.9 * CGFloat(min(peak * scale, 1))
            let y = centerY + sign * amplitude * halfAmp
            return CGPoint(x: x, y: y)
        }
    }

    /// A Catmull-Rom spline through the points (converted to cubic
    /// Béziers) for a continuous, flowing stroke.
    private static func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }

    private static func interpolatedY(_ points: [CGPoint], atX x: CGFloat) -> CGFloat {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        for i in 0..<(points.count - 1) where x >= points[i].x && x <= points[i + 1].x {
            let a = points[i], b = points[i + 1]
            let t = (x - a.x) / max(b.x - a.x, 0.0001)
            return a.y + (b.y - a.y) * t
        }
        return first.y
    }

    static func downsample(_ peaks: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard peaks.count > count else { return peaks }
        let stride = Double(peaks.count) / Double(count)
        return (0..<count).map { index in
            let start = Int(Double(index) * stride)
            let end = max(min(Int(Double(index + 1) * stride), peaks.count), start + 1)
            return peaks[start..<end].max() ?? 0
        }
    }
}

#if DEBUG
private struct WaveformGallery: View {
    private let peaks = (0..<160).map { abs(sin(Float($0) / 6)) * Float.random(in: 0.3...1) }
    var body: some View {
        VStack(spacing: Spacing.l) {
            WaveformView(peaks: peaks).frame(height: 40)
            WaveformView(peaks: peaks, tint: .accentColor, progress: 0.55, style: .line)
                .frame(height: 96)
            WaveformView(peaks: peaks, tint: .primary, style: .line)
                .frame(height: 96)
        }
        .padding(Spacing.m)
        .tint(.accentColor)
    }
}

#Preview("Light") { WaveformGallery().preferredColorScheme(.light) }
#Preview("Dark") { WaveformGallery().preferredColorScheme(.dark) }
#endif
