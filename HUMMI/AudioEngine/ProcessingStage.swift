//
//  ProcessingStage.swift
//  HUMMI
//

import Foundation

/// One toggleable step of the enhancement chain, transforming raw
/// 48 kHz mono Float32 samples. Every stage must be individually
/// switchable for A/B testing.
nonisolated protocol ProcessingStage: AnyObject {
    /// Short human-readable name for debug UIs ("High-pass 80 Hz").
    var name: String { get }
    var isEnabled: Bool { get set }
    func process(_ samples: [Float]) throws -> [Float]
}

/// Alias kept while every stage runs directly on sample buffers; the
/// pipeline once also supported AVAudioEngine node stages.
nonisolated protocol BufferStage: ProcessingStage {}
