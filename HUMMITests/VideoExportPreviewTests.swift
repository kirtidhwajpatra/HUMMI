//
//  VideoExportPreviewTests.swift
//  HUMMITests
//
//  Renders a short share video with synthetic audio and dumps frames as
//  PNGs so the clip's look can be reviewed without driving the full app.
//

import AVFoundation
import XCTest
@testable import HUMMI

final class VideoExportPreviewTests: XCTestCase {
    func testRenderPreviewFrames() async throws {
        // 3 s of a warbling sine so the waveform has organic peaks.
        let sampleRate = 48_000.0
        let samples = (0..<Int(sampleRate * 3)).map { i -> Float in
            let t = Double(i) / sampleRate
            let envelope = 0.35 + 0.3 * sin(t * 2.1) + 0.2 * sin(t * 7.3)
            return Float(sin(t * 2 * .pi * 220) * max(envelope, 0.05) * 0.5)
        }
        let dir = FileManager.default.temporaryDirectory
        let wav = dir.appendingPathComponent("preview.wav")
        try AudioClipIO.writeWAV(samples, to: wav)

        let peaks: [Float] = (0..<120).map { i in
            0.15 + 0.8 * abs(Float(sin(Double(i) * 0.4))) * Float.random(in: 0.5...1)
        }
        let mp4 = dir.appendingPathComponent("preview.mp4")
        try await VideoExporter.exportMP4(
            audioURL: wav, peaks: peaks, duration: 3,
            watermark: true, to: mp4) { _ in }

        let asset = AVURLAsset(url: mp4)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let trackSize = try await track?.load(.naturalSize) ?? .zero
        print("VIDEO TRACK SIZE: \(trackSize)")
        let generator = AVAssetImageGenerator(asset: asset)
        generator.apertureMode = .cleanAperture
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // Simulator tests share the host filesystem; write snapshots
        // somewhere the session can read them (overridable via env).
        let outDir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? "/tmp"

        // Pre-encoder isolations: the raw scene and one raw composited frame.
        if let bg = VideoExporter.debugBackgroundPNG() {
            try bg.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("hummi-raw-bg.png"))
        }
        if let raw = VideoExporter.debugFramePNG(peaks: peaks, progress: 0.5) {
            try raw.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("hummi-raw-frame.png"))
        }
        for (label, seconds) in [("start", 0.2), ("mid", 1.6)] {
            let cg = try await generator.image(
                at: CMTime(seconds: seconds, preferredTimescale: 600)).image
            let png = URL(fileURLWithPath: outDir).appendingPathComponent("hummi-frame-\(label).png")
            let data = try XCTUnwrap(UIImage(cgImage: cg).pngData())
            try data.write(to: png)
            print("SNAPSHOT[\(label)]: \(png.path)")
        }
    }
}
