#if DEBUG
//
//  SpikeTestViewModel.swift
//  HUMMI
//

#if DEBUG
import Foundation
import Observation

/// Drives the temporary Spike Test screen: runs the bundled clip through
/// the on-device DeepFilterNet3 pipeline off the main actor and reports
/// timing and the output WAV location.
@MainActor
@Observable
final class SpikeTestViewModel {
    enum Phase: Equatable {
        case idle
        case running
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var result: SpikeTestResult?

    func run() async {
        guard phase != .running else { return }
        phase = .running
        result = nil
        do {
            let result = try await Self.process()
            self.result = result
            phase = .done
            print("SpikeTest: wrote \(result.outputURL.path) "
                  + String(format: "(%.2fs, %.2fx realtime)",
                           result.processSeconds, result.realtimeFactor))
        } catch {
            phase = .failed(error.localizedDescription)
            print("SpikeTest: FAILED — \(error.localizedDescription)")
        }
    }

    @concurrent
    private static func process() async throws -> SpikeTestResult {
        guard let clipURL = Bundle.main.url(forResource: "SpikeTestClip", withExtension: "m4a") else {
            throw DFNError.audioFile("SpikeTestClip.m4a is missing from the app bundle")
        }
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            throw DFNError.audioFile("the Documents folder is unavailable")
        }
        let outputURL = documents.appendingPathComponent("SpikeTestClip-enhanced.wav")

        let clock = ContinuousClock()
        let loadStart = clock.now
        let enhancer = try DFNEnhancer()
        let modelLoadSeconds = seconds(loadStart.duration(to: clock.now))

        let samples = try AudioClipIO.loadMono48k(from: clipURL)
        let processStart = clock.now
        let enhanced = try enhancer.enhance(samples)
        let processSeconds = seconds(processStart.duration(to: clock.now))
        try AudioClipIO.writeWAV(enhanced, to: outputURL)

        return SpikeTestResult(
            clipSeconds: Double(samples.count) / DFNContract.sampleRate,
            modelLoadSeconds: modelLoadSeconds,
            processSeconds: processSeconds,
            outputURL: outputURL)
    }

    private nonisolated static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}
#endif
#endif
