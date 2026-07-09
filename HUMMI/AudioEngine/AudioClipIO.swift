//
//  AudioClipIO.swift
//  HUMMI
//

import AVFoundation

/// Reads audio files as 48 kHz mono Float32 sample arrays and writes them
/// back out as Float32 WAV — the app-internal audio format.
nonisolated enum AudioClipIO {
    static func loadMono48k(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard file.length > 0 else {
            throw DFNError.audioFile("\(url.lastPathComponent) is empty")
        }
        let inputBuffer = try readAll(file)

        if inputFormat.sampleRate == DFNContract.sampleRate, inputFormat.channelCount == 1 {
            return samples(of: inputBuffer)
        }
        return try convertToMono48k(inputBuffer)
    }

    /// Reads the whole file. One AVAudioFile.read(into:) call may return
    /// fewer frames than requested, so accumulate in chunks until the
    /// file is drained.
    private static func readAll(_ file: AVAudioFile) throws -> AVAudioPCMBuffer {
        let format = file.processingFormat  // always Float32 deinterleaved
        let channels = Int(format.channelCount)
        guard
            let full = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
            let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16),
            let fullChannels = full.floatChannelData
        else {
            throw DFNError.audioFile("could not allocate a read buffer")
        }
        while file.framePosition < file.length {
            try file.read(into: chunk)
            guard chunk.frameLength > 0, let chunkChannels = chunk.floatChannelData else {
                break
            }
            let offset = Int(full.frameLength)
            for ch in 0..<channels {
                fullChannels[ch].advanced(by: offset)
                    .update(from: chunkChannels[ch], count: Int(chunk.frameLength))
            }
            full.frameLength += chunk.frameLength
        }
        return full
    }

    /// AVAudioFile settings for the app-internal WAV format:
    /// 48 kHz mono Float32 linear PCM.
    static func wavSettings48kMono() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: DFNContract.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    static func writeWAV(_ samples: [Float], to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url, settings: wavSettings48kMono(),
            commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData else {
            throw DFNError.audioFile("could not allocate a write buffer")
        }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel[0].update(from: base, count: samples.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buffer)
    }

    private static func convertToMono48k(_ inputBuffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: DFNContract.sampleRate,
            channels: 1, interleaved: false
        ), let converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
            throw DFNError.audioFile("cannot convert to 48 kHz mono")
        }
        let ratio = DFNContract.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw DFNError.audioFile("could not allocate a conversion buffer")
        }

        var inputConsumed = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if inputConsumed {
                status.pointee = .endOfStream
                return nil
            }
            inputConsumed = true
            status.pointee = .haveData
            return inputBuffer
        }
        if let conversionError {
            throw DFNError.audioFile("conversion failed: \(conversionError.localizedDescription)")
        }
        return samples(of: outputBuffer)
    }

    private static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }
}
