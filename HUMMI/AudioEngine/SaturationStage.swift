//
//  SaturationStage.swift
//  HUMMI
//

import Accelerate

/// Low-drive tanh saturation mixed in parallel — warmth, not fuzz.
/// Port of tools/spike/polish.py saturate(): pedalboard Distortion is
/// exactly y = tanh(10^(drive_db/20) · x) (verified empirically).
nonisolated final class SaturationStage: BufferStage {
    let name = "Saturation (parallel)"
    var isEnabled = true

    static let driveDB = 5.0

    private let blend: Float
    private let driveDB: Double

    init(parameters: PresetParameters) {
        self.blend = Float(parameters.saturationBlend)
        self.driveDB = parameters.saturationDriveDB
    }

    func process(_ samples: [Float]) throws -> [Float] {
        guard blend > 0 else { return samples }
        let drive = Float(pow(10.0, driveDB / 20.0))
        var driven = vDSP.multiply(drive, samples)
        vForce.tanh(driven, result: &driven)
        return vDSP.add(
            vDSP.multiply(1 - blend, samples), vDSP.multiply(blend, driven))
    }
}
