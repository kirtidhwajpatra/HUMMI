//
//  DFNModel.swift
//  HUMMI
//

import CoreML

/// Thin wrapper around the compiled DeepFilterNet3 Core ML model:
/// packed-float spectra and features in, packed-float enhanced spectrum out.
nonisolated struct DFNModel {
    private let model: MLModel

    init() throws {
        guard let url = Bundle.main.url(forResource: "DeepFilterNet3", withExtension: "mlmodelc") else {
            throw DFNError.modelMissing
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    /// Runs the whole clip in one prediction. Inputs are packed float
    /// arrays: `spec` [frames × 481 × 2], `erb` [frames × 32],
    /// `unitNorm` [frames × 96 × 2]. Returns the enhanced spectrum in the
    /// same packing as `spec`.
    func predict(spec: [Float], erb: [Float], unitNorm: [Float], frames: Int) throws -> [Float] {
        let inputs = try MLDictionaryFeatureProvider(dictionary: [
            "spec": Self.multiArray(spec, shape: [1, 1, frames, DFNContract.binCount, 2]),
            "feat_erb": Self.multiArray(erb, shape: [1, 1, frames, DFNContract.erbBandCount]),
            "feat_spec": Self.multiArray(unitNorm, shape: [1, 1, frames, DFNContract.dfBinCount, 2]),
        ])
        let outputs = try model.prediction(from: inputs)
        guard let enhanced = outputs.featureValue(for: "enhanced_spec")?.multiArrayValue else {
            throw DFNError.unexpectedModelOutput("missing enhanced_spec")
        }
        return try Self.floats(from: enhanced, expectedCount: frames * DFNContract.binCount * 2)
    }

    private static func multiArray(_ values: [Float], shape: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        guard array.count == values.count else {
            throw DFNError.unexpectedModelOutput("input shape \(shape) ≠ \(values.count) values")
        }
        array.withUnsafeMutableBytes { destination, _ in
            values.withUnsafeBytes { source in
                if let to = destination.baseAddress, let from = source.baseAddress {
                    to.copyMemory(from: from, byteCount: source.count)
                }
            }
        }
        return array
    }

    private static func floats(from array: MLMultiArray, expectedCount: Int) throws -> [Float] {
        guard array.count == expectedCount else {
            throw DFNError.unexpectedModelOutput("\(array.count) values, expected \(expectedCount)")
        }
        switch array.dataType {
        case .float32:
            return array.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
        case .float16:
            return array.withUnsafeBufferPointer(ofType: Float16.self) { $0.map(Float.init) }
        default:
            throw DFNError.unexpectedModelOutput("data type \(array.dataType.rawValue)")
        }
    }
}
