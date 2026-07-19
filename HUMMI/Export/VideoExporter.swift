//
//  VideoExporter.swift
//  HUMMI
//

import AVFoundation
import CoreText
import UIKit

/// Renders a vertical (1080×1920) MP4 of an enhanced take, styled as a
/// share-ready "voice note" clip: a blurred indigo-violet gradient, a
/// frosted glass capsule holding a play button, thin voice-note bars and
/// a counting timer. The play button "presses" as the clip starts, the
/// bars brighten as the audio plays — the video looks like someone just
/// tapped play on a voice message. The gradient/pill chrome is drawn
/// once; each frame adds only the bars, button, and timer.
nonisolated enum VideoExporter {
    static let width = 1080
    static let height = 1920
    static let fps: Int32 = 30

    // MARK: Layout (top-left coordinates)

    private static let pillRect = CGRect(x: 70, y: 830, width: 940, height: 260)
    private static var pillCenterY: CGFloat { pillRect.midY }
    private static let playCenter = CGPoint(x: 190, y: 960)
    private static let playDiameter: CGFloat = 120
    private static let shareCenter = CGPoint(x: 920, y: 960)
    private static let shareDiameter: CGFloat = 110
    private static let waveLeft: CGFloat = 290
    private static let waveWidth: CGFloat = 400
    private static let waveHalfHeight: CGFloat = 55
    private static let barCount = 44
    private static let timerCenterX: CGFloat = 785

    // Palette — the app's brand (Brand.swift), mirrored in UIKit colours.
    private static let limeTop = UIColor(red: 163 / 255, green: 240 / 255, blue: 99 / 255, alpha: 1)
    private static let limeDeep = UIColor(red: 106 / 255, green: 214 / 255, blue: 52 / 255, alpha: 1)
    private static let forest = UIColor(red: 23 / 255, green: 51 / 255, blue: 0, alpha: 1)

    static func exportMP4(
        audioURL: URL, peaks: [Float], duration: TimeInterval,
        watermark: Bool, to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        guard duration > 0 else { throw DFNError.audioFile("nothing to export") }

        let size = CGSize(width: width, height: height)
        guard let background = makeBackground(size: size, watermark: watermark)
        else { throw DFNError.audioFile("could not draw the video frames") }
        let bars = downsample(peaks, to: barCount)

        // Writer with a video and an audio input.
        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000],
            ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: DFNContract.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: AudioExporter.bitRate,
            ])
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw DFNError.audioFile("could not prepare the video writer")
        }
        writer.add(videoInput)
        writer.add(audioInput)

        guard writer.startWriting() else {
            throw writer.error ?? DFNError.audioFile("could not start the video export")
        }
        writer.startSession(atSourceTime: .zero)

        // Video frames — driven by requestMediaDataWhenReady so the writer
        // paces the encoder (a busy-poll append loop stalls the encoder,
        // especially in the simulator).
        let totalFrames = max(1, Int((duration * Double(fps)).rounded(.up)))
        guard let pool = adaptor.pixelBufferPool else {
            throw DFNError.audioFile("no pixel buffer pool")
        }
        let context = VideoPumpContext(
            input: videoInput, adaptor: adaptor, pool: pool, writer: writer,
            background: background, bars: bars, duration: duration,
            totalFrames: totalFrames, progress: progress)
        async let videoPump: Void = pumpVideo(context)
        async let audioPump: Void = appendAudio(from: audioURL, to: audioInput)
        try await videoPump
        try await audioPump
        progress(0.97)

        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? DFNError.audioFile("writing the video failed")
        }
        progress(1.0)
    }

    // MARK: - Video pump

    /// All state the requestMediaDataWhenReady block touches, boxed so the
    /// `@Sendable` block captures one reference (the block runs serially on
    /// the pump queue, so unsynchronized mutation is safe).
    private final class VideoPumpContext: @unchecked Sendable {
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let pool: CVPixelBufferPool
        let writer: AVAssetWriter
        let background: CGImage
        let bars: [Float]
        let duration: TimeInterval
        let totalFrames: Int
        let progress: @Sendable (Double) -> Void
        var frame = 0
        var finished = false

        init(input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor,
             pool: CVPixelBufferPool, writer: AVAssetWriter, background: CGImage,
             bars: [Float], duration: TimeInterval, totalFrames: Int,
             progress: @escaping @Sendable (Double) -> Void) {
            self.input = input; self.adaptor = adaptor; self.pool = pool
            self.writer = writer; self.background = background; self.bars = bars
            self.duration = duration
            self.totalFrames = totalFrames; self.progress = progress
        }
    }

    private static func pumpVideo(_ ctx: VideoPumpContext) async throws {
        let queue = DispatchQueue(label: "com.hummi.video-export")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ctx.input.requestMediaDataWhenReady(on: queue) {
                if ctx.finished { return }
                while ctx.input.isReadyForMoreMediaData {
                    if ctx.writer.status == .failed {
                        ctx.finished = true
                        continuation.resume(throwing: ctx.writer.error
                            ?? DFNError.audioFile("video writer failed"))
                        return
                    }
                    if ctx.frame >= ctx.totalFrames {
                        ctx.finished = true
                        ctx.input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    let fraction = Double(ctx.frame) / Double(ctx.totalFrames)
                    guard let buffer = makeFrame(
                        pool: ctx.pool, background: ctx.background, bars: ctx.bars,
                        duration: ctx.duration, progress: fraction)
                    else {
                        ctx.finished = true
                        continuation.resume(throwing: DFNError.audioFile("could not build a video frame"))
                        return
                    }
                    let time = CMTime(value: Int64(ctx.frame), timescale: fps)
                    if !ctx.adaptor.append(buffer, withPresentationTime: time) {
                        ctx.finished = true
                        continuation.resume(throwing: ctx.writer.error
                            ?? DFNError.audioFile("could not append a video frame"))
                        return
                    }
                    ctx.frame += 1
                    ctx.progress(0.9 * fraction)
                }
            }
        }
    }

    // MARK: - Audio

    private static func appendAudio(from wavURL: URL, to input: AVAssetWriterInput) async throws {
        let asset = AVURLAsset(url: wavURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
            ])
        reader.add(output)
        reader.startReading()
        while true {
            if input.isReadyForMoreMediaData {
                if let sample = output.copyNextSampleBuffer() {
                    input.append(sample)
                } else {
                    break
                }
            } else {
                try await Task.sleep(for: .milliseconds(4))
            }
        }
        input.markAsFinished()
    }

    // MARK: - Frame compositing

    private static func makeFrame(
        pool: CVPixelBufferPool, background: CGImage, bars: [Float],
        duration: TimeInterval, progress: Double
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let ctx = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        // Pool buffers arrive with uninitialized memory; without this the
        // rows the encoder pads show up as a black sliver at one edge.
        memset(base, 0,
               CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))

        // Draw the image in IDENTITY space — CGContext.draw inside a
        // flipped transform renders images upside-down.
        let full = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        ctx.draw(background, in: full)

        // Then flip to a top-left, y-down space for the vector/text layer.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let time = progress * duration
        drawPlayButton(in: ctx, time: time)
        drawBars(in: ctx, bars: bars, progress: progress, time: time)
        drawTimer(in: ctx, time: time)
        return buffer
    }

    /// The brand button, styled exactly like the app's lime gel buttons:
    /// lime gradient disc, deep-forest glyph. In the first half second it
    /// "presses" — dips and springs back — and at the bottom of the press
    /// the play triangle becomes a pause glyph, because playback started.
    private static func drawPlayButton(in ctx: CGContext, time: TimeInterval) {
        let scale = pressScale(at: time)
        let diameter = playDiameter * scale
        let circle = CGRect(
            x: playCenter.x - diameter / 2, y: playCenter.y - diameter / 2,
            width: diameter, height: diameter)

        // Lime gradient fill, top → bottom, like Brand.limeGradient.
        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        let colors = [limeTop.cgColor, limeDeep.cgColor] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient, start: CGPoint(x: circle.midX, y: circle.minY),
                end: CGPoint(x: circle.midX, y: circle.maxY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()

        ctx.setFillColor(forest.cgColor)
        if time >= 0.30 {  // pause — playback is running
            let barWidth = 13 * scale
            let barHeight = 42 * scale
            let gap = 13 * scale
            for x in [playCenter.x - gap / 2 - barWidth, playCenter.x + gap / 2] {
                let rect = CGRect(
                    x: x, y: playCenter.y - barHeight / 2,
                    width: barWidth, height: barHeight)
                ctx.addPath(CGPath(
                    roundedRect: rect, cornerWidth: barWidth / 2.5,
                    cornerHeight: barWidth / 2.5, transform: nil))
                ctx.fillPath()
            }
        } else {  // play triangle, slightly right of centre
            let side = 44 * scale
            let originX = playCenter.x - side * 0.32
            ctx.beginPath()
            ctx.move(to: CGPoint(x: originX, y: playCenter.y - side / 2))
            ctx.addLine(to: CGPoint(x: originX + side * 0.9, y: playCenter.y))
            ctx.addLine(to: CGPoint(x: originX, y: playCenter.y + side / 2))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    private static func pressScale(at time: TimeInterval) -> CGFloat {
        switch time {
        case ..<0.12: return 1
        case ..<0.30: return 1 - 0.10 * CGFloat((time - 0.12) / 0.18)      // press down
        case ..<0.55: return 0.90 + 0.10 * CGFloat((time - 0.30) / 0.25)   // spring back
        default: return 1
        }
    }

    /// Voice-note bars: unplayed soft white, played full white, with a
    /// gentle pulse on the bar under the playhead so playback feels live.
    private static func drawBars(
        in ctx: CGContext, bars: [Float], progress: Double, time: TimeInterval
    ) {
        guard !bars.isEmpty else { return }
        let scale = 1 / max(bars.max() ?? 1, 0.05)
        let slot = waveWidth / CGFloat(bars.count)
        let playhead = Double(bars.count) * min(max(progress, 0), 1)
        for (index, peak) in bars.enumerated() {
            var h = max(waveHalfHeight * 2 * CGFloat(min(peak * scale, 1)), 10)
            let distance = abs(Double(index) - playhead)
            if distance < 1.5 {  // live pulse around the playhead
                h *= 1 + 0.12 * CGFloat(1 - distance / 1.5) * CGFloat(0.5 + 0.5 * sin(time * 12))
            }
            let played = Double(index) + 0.5 <= playhead
            // Played bars take the brand lime — the app's "live voice" colour.
            ctx.setFillColor(played ? limeTop.cgColor
                                    : UIColor(white: 1, alpha: 0.40).cgColor)
            let rect = CGRect(
                x: waveLeft + CGFloat(index) * slot + slot * 0.22,
                y: pillCenterY - h / 2,
                width: slot * 0.56, height: h)
            ctx.addPath(CGPath(
                roundedRect: rect, cornerWidth: rect.width / 2,
                cornerHeight: rect.width / 2, transform: nil))
            ctx.fillPath()
        }
    }

    private static func drawTimer(in ctx: CGContext, time: TimeInterval) {
        let total = max(Int(time.rounded(.down)), 0)
        let text = String(format: "%d:%02d", total / 60, total % 60)
        UIGraphicsPushContext(ctx)
        draw(text: text,
             font: .monospacedDigitSystemFont(ofSize: 62, weight: .medium),
             color: .white, alpha: 0.95,
             centeredAt: CGPoint(x: timerCenterX, y: pillCenterY))
        UIGraphicsPopContext()
    }

    // MARK: - Static scene

    /// Everything that never changes: the blurred indigo-violet gradient,
    /// the frosted glass capsule, the share circle, and the watermark.
    private static func makeBackground(size: CGSize, watermark: Bool) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let ctx = rendererContext.cgContext
            let space = CGColorSpace(name: CGColorSpace.sRGB)

            // Deep forest base — the brand canvas, brighter toward the top.
            let base = [
                UIColor(red: 0.13, green: 0.26, blue: 0.05, alpha: 1).cgColor,
                UIColor(red: 0.07, green: 0.16, blue: 0.02, alpha: 1).cgColor,
                UIColor(red: 0.10, green: 0.22, blue: 0.04, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: base, locations: [0, 0.55, 1]) {
                // The tilted axis leaves an unpainted wedge past its end
                // point unless the gradient extends beyond both ends.
                ctx.drawLinearGradient(
                    gradient, start: .zero,
                    end: CGPoint(x: size.width * 0.2, y: size.height),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }

            // Soft out-of-focus blooms — the "blurred backdrop" feel.
            drawBloom(in: ctx, space: space,
                      center: CGPoint(x: size.width * 0.80, y: size.height * 0.30),
                      radius: 720,
                      color: UIColor(red: 0.55, green: 0.85, blue: 0.32, alpha: 0.32))
            drawBloom(in: ctx, space: space,
                      center: CGPoint(x: size.width * 0.10, y: size.height * 0.78),
                      radius: 820,
                      color: UIColor(red: 0.03, green: 0.10, blue: 0.01, alpha: 0.60))

            // Frosted glass capsule with a soft drop shadow.
            let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 26), blur: 60,
                          color: UIColor.black.withAlphaComponent(0.28).cgColor)
            ctx.setFillColor(UIColor(white: 1, alpha: 0.16).cgColor)
            ctx.addPath(pill.cgPath)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.30).cgColor)
            ctx.setLineWidth(2)
            ctx.addPath(UIBezierPath(
                roundedRect: pillRect.insetBy(dx: 1, dy: 1),
                cornerRadius: pillRect.height / 2).cgPath)
            ctx.strokePath()

            // Share circle (static decoration, upper-right of the pill).
            let share = CGRect(
                x: shareCenter.x - shareDiameter / 2, y: shareCenter.y - shareDiameter / 2,
                width: shareDiameter, height: shareDiameter)
            ctx.setFillColor(UIColor(white: 1, alpha: 0.20).cgColor)
            ctx.fillEllipse(in: share)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(7)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.beginPath()  // upward arrow
            ctx.move(to: CGPoint(x: shareCenter.x, y: shareCenter.y + 22))
            ctx.addLine(to: CGPoint(x: shareCenter.x, y: shareCenter.y - 22))
            ctx.move(to: CGPoint(x: shareCenter.x - 16, y: shareCenter.y - 6))
            ctx.addLine(to: CGPoint(x: shareCenter.x, y: shareCenter.y - 22))
            ctx.addLine(to: CGPoint(x: shareCenter.x + 16, y: shareCenter.y - 6))
            ctx.strokePath()

            if watermark {
                draw(text: AppBranding.watermarkText,
                     font: .systemFont(ofSize: 40, weight: .semibold),
                     color: .white, alpha: 0.45,
                     centeredAt: CGPoint(x: size.width / 2, y: pillRect.maxY + 110))
            }
        }
        return image.cgImage
    }

    #if DEBUG
    /// Test hooks: render the static scene / one composited frame without
    /// the writer, to isolate drawing bugs from encoding bugs.
    static func debugBackgroundPNG() -> Data? {
        makeBackground(size: CGSize(width: width, height: height), watermark: true)
            .flatMap { UIImage(cgImage: $0).pngData() }
    }

    static func debugFramePNG(peaks: [Float], progress: Double) -> Data? {
        guard let background = makeBackground(
            size: CGSize(width: width, height: height), watermark: true) else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                            &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil,
                                [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                 kCVPixelBufferWidthKey: width,
                                 kCVPixelBufferHeightKey: height] as CFDictionary, &pool)
        guard let pool,
              let frame = makeFrame(pool: pool, background: background,
                                    bars: downsample(peaks, to: barCount),
                                    duration: 3, progress: progress) else { return nil }
        _ = buffer
        let image = CIImage(cvPixelBuffer: frame)
        let context = CIContext()
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }
    #endif

    private static func drawBloom(
        in ctx: CGContext, space: CGColorSpace?, center: CGPoint,
        radius: CGFloat, color: UIColor
    ) {
        let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])
        else { return }
        ctx.drawRadialGradient(
            gradient, startCenter: center, startRadius: 0,
            endCenter: center, endRadius: radius, options: [])
    }

    private static func downsample(_ peaks: [Float], to count: Int) -> [Float] {
        guard peaks.count > count else { return peaks }
        let stride = Double(peaks.count) / Double(count)
        return (0..<count).map { index in
            let start = Int(Double(index) * stride)
            let end = max(min(Int(Double(index + 1) * stride), peaks.count), start + 1)
            return peaks[start..<end].max() ?? 0
        }
    }

    // MARK: - Text helpers (drawn in the renderer's top-left space)

    private static func draw(
        text: String, font: UIFont, color: UIColor, alpha: CGFloat,
        centeredAt center: CGPoint
    ) {
        let attributed = attributedString(text, font: font, color: color.withAlphaComponent(alpha))
        let bounds = attributed.size()
        attributed.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    private static func draw(
        text: String, font: UIFont, color: UIColor, alpha: CGFloat, leftAt origin: CGPoint
    ) {
        let attributed = attributedString(text, font: font, color: color.withAlphaComponent(alpha))
        let bounds = attributed.size()
        attributed.draw(at: CGPoint(x: origin.x, y: origin.y - bounds.height / 2))
    }

    private static func attributedString(
        _ text: String, font: UIFont, color: UIColor
    ) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }
}
