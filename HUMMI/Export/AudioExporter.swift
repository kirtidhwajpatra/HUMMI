//
//  AudioExporter.swift
//  HUMMI
//

import AVFoundation

/// Transcodes an app-internal WAV (48 kHz mono Float32) to an M4A file
/// with AAC at 256 kbps, suitable for sharing.
nonisolated enum AudioExporter {
    static let bitRate = 256_000

    static func exportM4A(from wavURL: URL, to outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVURLAsset(url: wavURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw DFNError.audioFile("the take has no audio to export")
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ])
        guard reader.canAdd(readerOutput) else {
            throw DFNError.audioFile("could not read the take for export")
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(url: outputURL, fileType: .m4a)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: DFNContract.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: bitRate,
            ])
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw DFNError.audioFile("could not prepare the M4A writer")
        }
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            throw DFNError.audioFile("could not start the export")
        }
        writer.startSession(atSourceTime: .zero)

        while true {
            if writerInput.isReadyForMoreMediaData {
                if let sample = readerOutput.copyNextSampleBuffer() {
                    writerInput.append(sample)
                } else {
                    break
                }
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        writerInput.markAsFinished()

        if reader.status == .failed {
            throw reader.error ?? DFNError.audioFile("reading the take failed")
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? DFNError.audioFile("writing the M4A failed")
        }
    }
}
