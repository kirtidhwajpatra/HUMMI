//
//  AudioUnitRenderer.swift
//  HUMMI
//

import AVFoundation

/// Renders a sample buffer through a single AVAudioUnit effect using an
/// offline manual-rendering AVAudioEngine pass (faster than realtime).
/// Used by the stages that wrap Apple audio units instead of our own
/// DSP. Output is truncated to the input's length.
nonisolated enum AudioUnitRenderer {
    private static let chunkFrames: AVAudioFrameCount = 4_096

    /// `channels: 2` duplicates the mono input into a stereo graph and
    /// averages the output back to mono — required for units that
    /// reject mono buses (AVAudioUnitReverb).
    static func render(
        _ samples: [Float], through node: AVAudioUnit, channels: UInt32 = 1
    ) throws -> [Float] {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: DFNContract.sampleRate,
            channels: channels, interleaved: false
        ) else {
            throw DFNError.audioFile("no 48 kHz render format")
        }
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)
        ), let inputChannels = inputBuffer.floatChannelData else {
            throw DFNError.audioFile("could not allocate the render input buffer")
        }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                for ch in 0..<Int(channels) {
                    inputChannels[ch].update(from: base, count: samples.count)
                }
            }
        }
        inputBuffer.frameLength = AVAudioFrameCount(samples.count)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.attach(node)
        engine.connect(player, to: node, format: format)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(
            .offline, format: format, maximumFrameCount: chunkFrames)
        try engine.start()
        defer { engine.stop() }
        player.scheduleBuffer(inputBuffer, at: nil)
        player.play()

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat, frameCapacity: chunkFrames
        ) else {
            throw DFNError.audioFile("could not allocate the render output buffer")
        }

        var output: [Float] = []
        output.reserveCapacity(samples.count)
        while output.count < samples.count {
            let remaining = AVAudioFrameCount(samples.count - output.count)
            let status = try engine.renderOffline(
                min(chunkFrames, remaining), to: renderBuffer)
            switch status {
            case .success:
                guard let rendered = renderBuffer.floatChannelData else {
                    throw DFNError.audioFile("render produced no channel data")
                }
                let frames = Int(renderBuffer.frameLength)
                let outChannels = Int(engine.manualRenderingFormat.channelCount)
                if outChannels == 1 {
                    output.append(contentsOf: UnsafeBufferPointer(
                        start: rendered[0], count: frames))
                } else {
                    for i in 0..<frames {  // downmix back to mono
                        var sum: Float = 0
                        for ch in 0..<outChannels {
                            sum += rendered[ch][i]
                        }
                        output.append(sum / Float(outChannels))
                    }
                }
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw DFNError.audioFile("offline render failed")
            @unknown default:
                throw DFNError.audioFile("offline render failed")
            }
        }
        return output
    }
}
