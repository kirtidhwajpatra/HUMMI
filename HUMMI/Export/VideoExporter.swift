//
//  VideoExporter.swift
//  HUMMI
//

import AVFoundation
import CoreText
import UIKit

/// Renders a vertical (1080×1920) MP4 of an enhanced take: a branded
/// background, a waveform that fills with the accent colour as the audio
/// plays, and an optional watermark. The static background and accent
/// waveform are drawn once; each frame just composites the played
/// portion and the playhead, so rendering stays fast.
nonisolated enum VideoExporter {
    static let width = 1080
    static let height = 1920
    static let fps: Int32 = 30

    // Layout (top-left coordinates).
    private static let waveLeft: CGFloat = 100
    private static let waveWidth: CGFloat = 880
    private static let waveCenterY: CGFloat = 1020
    private static let waveHalfHeight: CGFloat = 300

    static func exportMP4(
        audioURL: URL, peaks: [Float], duration: TimeInterval,
        watermark: Bool, to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        guard duration > 0 else { throw DFNError.audioFile("nothing to export") }

        let size = CGSize(width: width, height: height)
        guard let background = makeBackground(size: size, peaks: peaks, watermark: watermark),
              let accent = makeAccentWaveform(size: size, peaks: peaks)
        else { throw DFNError.audioFile("could not draw the video frames") }

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
            background: background, accent: accent, totalFrames: totalFrames,
            progress: progress)
        try await pumpVideo(context)

        // Audio track from the WAV.
        try await appendAudio(from: audioURL, to: audioInput)
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
        let accent: CGImage
        let totalFrames: Int
        let progress: @Sendable (Double) -> Void
        var frame = 0
        var finished = false

        init(input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor,
             pool: CVPixelBufferPool, writer: AVAssetWriter, background: CGImage,
             accent: CGImage, totalFrames: Int,
             progress: @escaping @Sendable (Double) -> Void) {
            self.input = input; self.adaptor = adaptor; self.pool = pool
            self.writer = writer; self.background = background; self.accent = accent
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
                        pool: ctx.pool, background: ctx.background,
                        accent: ctx.accent, progress: fraction)
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
        pool: CVPixelBufferPool, background: CGImage, accent: CGImage, progress: Double
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

        // Flip to a top-left, y-down space matching the static images.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let full = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        ctx.draw(background, in: full)

        let playheadX = waveLeft + waveWidth * CGFloat(min(max(progress, 0), 1))
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: playheadX, height: CGFloat(height)))
        ctx.draw(accent, in: full)
        ctx.restoreGState()

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(
            x: playheadX - 2, y: waveCenterY - waveHalfHeight,
            width: 4, height: waveHalfHeight * 2))
        return buffer
    }

    // MARK: - Static images

    private static func makeBackground(
        size: CGSize, peaks: [Float], watermark: Bool
    ) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let ctx = rendererContext.cgContext

            // Branded gradient background.
            let colors = [
                UIColor(red: 0.05, green: 0.07, blue: 0.15, alpha: 1).cgColor,
                UIColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                locations: [0, 1]) {
                ctx.drawLinearGradient(
                    gradient, start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height), options: [])
            }

            // Title.
            draw(text: AppBranding.name, font: .systemFont(ofSize: 64, weight: .bold),
                 color: .white, alpha: 1, centeredAt: CGPoint(x: size.width / 2, y: 250))
            draw(text: "✨ Enhanced", font: .systemFont(ofSize: 34, weight: .semibold),
                 color: UIColor(red: AppBranding.accentRGBA.r, green: AppBranding.accentRGBA.g,
                                blue: AppBranding.accentRGBA.b, alpha: 1),
                 alpha: 1, centeredAt: CGPoint(x: size.width / 2, y: 320))

            // Dim (unplayed) waveform.
            drawWaveform(in: ctx, peaks: peaks, color: UIColor(white: 1, alpha: 0.22))

            // Watermark, bottom corner.
            if watermark {
                draw(text: AppBranding.watermarkText,
                     font: .systemFont(ofSize: 32, weight: .medium),
                     color: .white, alpha: 0.5,
                     leftAt: CGPoint(x: 70, y: size.height - 90))
            }
        }
        return image.cgImage
    }

    private static func makeAccentWaveform(size: CGSize, peaks: [Float]) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            drawWaveform(
                in: rendererContext.cgContext, peaks: peaks,
                color: UIColor(red: AppBranding.accentRGBA.r, green: AppBranding.accentRGBA.g,
                               blue: AppBranding.accentRGBA.b, alpha: 1))
        }
        return image.cgImage
    }

    private static func drawWaveform(in ctx: CGContext, peaks: [Float], color: UIColor) {
        let bars = downsample(peaks, to: 110)
        guard !bars.isEmpty else { return }
        let scale = 1 / max(bars.max() ?? 1, 0.05)
        let barSlot = waveWidth / CGFloat(bars.count)
        ctx.setFillColor(color.cgColor)
        for (index, peak) in bars.enumerated() {
            let h = max(waveHalfHeight * 2 * CGFloat(min(peak * scale, 1)), 4)
            let rect = CGRect(
                x: waveLeft + CGFloat(index) * barSlot + barSlot * 0.2,
                y: waveCenterY - h / 2,
                width: barSlot * 0.6, height: h)
            ctx.addPath(CGPath(
                roundedRect: rect, cornerWidth: barSlot * 0.2,
                cornerHeight: barSlot * 0.2, transform: nil))
            ctx.fillPath()
        }
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
