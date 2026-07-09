//
//  RecordingMetadata.swift
//  HUMMI
//

import AVFoundation
import Accelerate

/// Duration and waveform thumbnail (~200 peak buckets) of a recording,
/// cached as JSON next to the WAV so it is computed once per file.
nonisolated struct RecordingMetadata: Codable, Sendable {
    static let bucketCount = 200
    static let currentVersion = 1

    var version: Int
    var duration: TimeInterval
    /// Peak |sample| per bucket, linear 0…1, in time order.
    var peaks: [Float]

    static func empty() -> RecordingMetadata {
        RecordingMetadata(version: currentVersion, duration: 0, peaks: [])
    }

    static func cacheURL(for audioURL: URL) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension("waveform.json")
    }

    /// Returns the cached metadata when present and current, computing and
    /// caching it otherwise.
    static func loadOrCompute(for audioURL: URL) throws -> RecordingMetadata {
        let cache = cacheURL(for: audioURL)
        if let data = try? Data(contentsOf: cache),
           let cached = try? JSONDecoder().decode(RecordingMetadata.self, from: data),
           cached.version == currentVersion, !cached.peaks.isEmpty {
            return cached
        }
        let computed = try compute(for: audioURL)
        if let data = try? JSONEncoder().encode(computed) {
            // Best effort — recomputing next time beats failing the list.
            try? data.write(to: cache, options: .atomic)
        }
        return computed
    }

    static func compute(for audioURL: URL) throws -> RecordingMetadata {
        let file = try AVAudioFile(forReading: audioURL)
        let sampleRate = file.processingFormat.sampleRate
        guard file.length > 0, sampleRate > 0 else { return .empty() }
        let duration = Double(file.length) / sampleRate

        let framesPerBucket = AVAudioFrameCount(max(file.length / Int64(bucketCount), 1))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: framesPerBucket
        ) else {
            throw DFNError.audioFile("could not allocate a waveform buffer")
        }

        var peaks: [Float] = []
        peaks.reserveCapacity(bucketCount)
        while file.framePosition < file.length, peaks.count < bucketCount {
            try file.read(into: buffer, frameCount: framesPerBucket)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData else { break }
            let samples = UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength))
            peaks.append(vDSP.maximumMagnitude(samples))
        }
        return RecordingMetadata(version: currentVersion, duration: duration, peaks: peaks)
    }
}
