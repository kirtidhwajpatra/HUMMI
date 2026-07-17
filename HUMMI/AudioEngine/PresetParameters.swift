//
//  PresetParameters.swift
//  HUMMI
//

import Foundation

/// Every tunable number in the DSP polish chain, in one place, so presets
/// are a single value and A/B variants are cheap to construct. Defaults
/// are the spike's approved "standard" preset (tools/spike/polish.py).
nonisolated struct PresetParameters: Sendable {
    // ML enhance stage (Stage A, chunked DFN3 + dry/wet)
    var mlEnhanceDryWet: Double = 0.9   // 1 = fully enhanced, 0 = original

    // DFN3 restoration stage (adaptive-floor alternate to ML enhance)
    var dfnTargetFloorDB: Double = 45
    var dfnVoicedCapDB: Double = 12

    // High-pass stage: 12 dB/oct total below the vocal range.
    var highPassFrequency: Double = 80

    // Surgical EQ stage — a little low-shelf body plus mud/box cuts.
    var warmthFrequency: Double = 200   // low-shelf "warmth" corner
    var warmthGainDB: Double = 1.5      // 0 disables the shelf
    var mudFrequency: Double = 300
    var mudGainDB: Double = -3
    var mudQ: Double = 1.2
    var boxFrequency: Double = 500
    var boxGainDB: Double = -2
    var boxQ: Double = 2.0

    // De-esser stage — firmer, to keep the brighter top smooth.
    var deEsserRatio: Double = 5.0

    // Multiband compressor stage — denser, more "produced" dynamics.
    var multibandRatio: Double = 3.5

    // Parallel saturation stage (0 disables) — more harmonic richness.
    var saturationBlend: Double = 0.22
    // Saturation drive: 5 dB is warmth; 12+ dB is megaphone grit.
    var saturationDriveDB: Double = 5.0

    // Echo stage (feedback delay; 0 ms disables). Dry signal is kept at
    // full level; the echo tail is mixed on top at `echoWet`.
    var echoDelayMS: Double = 0
    var echoFeedback: Double = 0.35
    var echoWet: Double = 0.3

    // Voice shape (all neutral by default; user-set, not preset-set).
    // Speed is varispeed: duration and pitch change together, like tape.
    var voiceSpeed: Double = 1.0
    // Tempo is a time-stretch: duration changes, pitch is preserved.
    var voiceTempo: Double = 1.0
    // Deeper (−12) ↔ lighter (+12), in semitones; duration preserved.
    var voicePitchSemitones: Double = 0

    // Presence / air EQ stage — more vocal forwardness and studio sheen.
    var presenceFrequency: Double = 3_000
    var presenceGainDB: Double = 3.0
    var presenceQ: Double = 1.0
    var airFrequency: Double = 10_000
    var airGainDB: Double = 4.5

    // Convolution reverb stage
    var reverbWet: Double = 0.20

    // Glue compressor stage — a touch more glue.
    var glueThresholdDB: Double = -15
    var glueRatio: Double = 2.0
    var glueAttackMS: Double = 30
    var glueReleaseMS: Double = 200

    // Apple dynamics-processor compressor stage (A/B alternate)
    var compressorThresholdDB: Double = -18
    var compressorRatio: Double = 3.0
    var compressorAttackMS: Double = 5
    var compressorReleaseMS: Double = 100

    // Apple reverb stage (A/B alternate)
    var roomReverbWetDryPercent: Double = 12

    // Loudness normalize stage
    var normalizeTargetDB: Double = -14   // integrated LUFS, RMS-approximated
    var normalizePeakCeilingDB: Double = -1

    // Pitch correction stage
    var pitchCorrectionStrength: Double = 0.55  // 0 disables
    var keyOverride: MusicalKey?                // nil = auto-detect

    static let `default` = PresetParameters()

    /// Pitch-correction strength presets.
    static let natural = strength(0.4)
    static let tuned = strength(0.7)
    static let hard = strength(1.0)

    private static func strength(_ value: Double) -> PresetParameters {
        var p = PresetParameters()
        p.pitchCorrectionStrength = value
        return p
    }

    /// The spike's "Strong" preset: more reverb, saturation, and air.
    static let strong: PresetParameters = {
        var p = PresetParameters()
        p.reverbWet = 0.25
        p.saturationBlend = 0.25
        p.airGainDB = 5.0
        return p
    }()
}
