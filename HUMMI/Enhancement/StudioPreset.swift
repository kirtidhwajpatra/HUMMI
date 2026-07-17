//
//  StudioPreset.swift
//  HUMMI
//

import Foundation

/// The user-facing enhancement presets. Each maps to a full set of DSP
/// parameters; the Result screen's four sliders (autotune, reverb, noise
/// removal, warmth) then adjust on top of the chosen preset.
///
/// The lineup is deliberately dramatic — switching filters should feel
/// like changing rooms, not nudging an EQ. Character presets (Telephone,
/// Megaphone, AM Radio, Tape) reshape the spectrum hard; space presets
/// (Stadium, Canyon, Dream) lean on reverb and the echo stage; Hard Tune
/// is the full pop-vocal tuning effect.
nonisolated enum StudioPreset: String, CaseIterable, Identifiable, Sendable {
    case balanced   // "Default" — natural, lightly enhanced
    case studio
    case hardTune
    case warm
    case bright
    case airy       // "Dream"
    case concert    // "Stadium"
    case canyon
    case vintage    // "Tape"
    case radio      // "AM Radio"
    case telephone
    case megaphone
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Default"
        case .studio: return "Studio"
        case .hardTune: return "Hard Tune"
        case .warm: return "Warm"
        case .bright: return "Bright"
        case .airy: return "Dream"
        case .concert: return "Stadium"
        case .canyon: return "Canyon"
        case .vintage: return "Tape"
        case .radio: return "AM Radio"
        case .telephone: return "Telephone"
        case .megaphone: return "Megaphone"
        case .deep: return "Deep"
        }
    }

    /// One-line description shown under the filter carousel.
    var caption: String {
        switch self {
        case .balanced: return "Cleaned up, still you"
        case .studio: return "Polished, radio-ready vocal"
        case .hardTune: return "Full pop autotune effect"
        case .warm: return "Cozy, close and lush"
        case .bright: return "Crisp sparkle and air"
        case .airy: return "Ethereal, floating in space"
        case .concert: return "Big stage, huge room"
        case .canyon: return "Long echoes rolling back"
        case .vintage: return "Saturated old-tape character"
        case .radio: return "Gritty broadcast midrange"
        case .telephone: return "Down the line, lo-fi"
        case .megaphone: return "Loud, driven and defiant"
        case .deep: return "Late-night bass and body"
        }
    }

    var systemImage: String {
        switch self {
        case .balanced: return "wand.and.rays"
        case .studio: return "sparkles"
        case .hardTune: return "tuningfork"
        case .warm: return "flame"
        case .bright: return "sun.max"
        case .airy: return "moon.stars"
        case .concert: return "music.mic"
        case .canyon: return "mountain.2"
        case .vintage: return "recordingtape"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .telephone: return "phone"
        case .megaphone: return "megaphone"
        case .deep: return "speaker.wave.3.fill"
        }
    }

    /// The default DSP parameters for this preset. The four adjustable
    /// fields (pitchCorrectionStrength, reverbWet, mlEnhanceDryWet,
    /// warmthGainDB) are the ones the sliders expose.
    var parameters: PresetParameters {
        var p = PresetParameters()
        switch self {
        case .balanced:
            // The most natural rendition: gentle tuning, light room, a
            // touch of body and presence — "cleaned up" more than "produced".
            p.pitchCorrectionStrength = 0.35
            p.reverbWet = 0.14
            p.warmthGainDB = 2.0
            p.presenceGainDB = 1.5
            p.airGainDB = 2.0
            p.saturationBlend = 0.15

        case .studio:
            // The flagship: unmistakably produced — dense dynamics, sheen,
            // saturation, confident tuning.
            p.pitchCorrectionStrength = 0.65
            p.reverbWet = 0.24
            p.warmthGainDB = 2.5
            p.presenceGainDB = 4.5
            p.airGainDB = 6.0
            p.saturationBlend = 0.30
            p.multibandRatio = 4.0

        case .hardTune:
            // The full pop autotune effect: instant hard snapping, tight
            // and dry so every artifact of the tuning is audible.
            p.pitchCorrectionStrength = 1.0
            p.mlEnhanceDryWet = 1.0
            p.reverbWet = 0.08
            p.presenceGainDB = 5.0
            p.airGainDB = 5.0
            p.saturationBlend = 0.20
            p.multibandRatio = 4.5

        case .warm:
            // Cozy and lush: heavy low-shelf body, rolled-off top, big
            // soft room, thick harmonics.
            p.pitchCorrectionStrength = 0.4
            p.warmthFrequency = 220
            p.warmthGainDB = 9.0
            p.airGainDB = -4.0
            p.presenceGainDB = 0.0
            p.reverbWet = 0.38
            p.saturationBlend = 0.40
            p.saturationDriveDB = 6.0

        case .bright:
            // Crisp sparkle: trimmed lows, big air shelf, forward presence,
            // tight room, firm tuning.
            p.pitchCorrectionStrength = 0.7
            p.warmthGainDB = -4.0
            p.airGainDB = 10.0
            p.presenceGainDB = 6.5
            p.reverbWet = 0.10
            p.deEsserRatio = 6.0

        case .airy:
            // Dream: ethereal wash — huge soft reverb, floating air, a
            // slow echo shimmering underneath.
            p.pitchCorrectionStrength = 0.5
            p.warmthGainDB = -1.0
            p.airGainDB = 8.0
            p.presenceGainDB = 2.0
            p.reverbWet = 0.55
            p.saturationBlend = 0.10
            p.echoDelayMS = 260
            p.echoFeedback = 0.30
            p.echoWet = 0.18

        case .concert:
            // Stadium: huge hall, forward vocal, a short slap echo that
            // reads as the back wall.
            p.pitchCorrectionStrength = 0.5
            p.warmthGainDB = 1.5
            p.airGainDB = 4.0
            p.presenceGainDB = 4.0
            p.reverbWet = 0.60
            p.saturationBlend = 0.15
            p.echoDelayMS = 150
            p.echoFeedback = 0.25
            p.echoWet = 0.22

        case .canyon:
            // Long regenerating echoes rolling back, in an open-air room.
            p.pitchCorrectionStrength = 0.45
            p.warmthGainDB = 1.0
            p.airGainDB = 2.0
            p.reverbWet = 0.30
            p.echoDelayMS = 340
            p.echoFeedback = 0.50
            p.echoWet = 0.40

        case .vintage:
            // Tape: dark top, thick saturation, a little mud left in on
            // purpose — worn, analogue, nostalgic.
            p.pitchCorrectionStrength = 0.3
            p.highPassFrequency = 110
            p.warmthFrequency = 180
            p.warmthGainDB = 5.0
            p.airGainDB = -8.0
            p.presenceGainDB = -1.0
            p.mudGainDB = 1.5
            p.saturationBlend = 0.65
            p.saturationDriveDB = 8.0
            p.reverbWet = 0.12

        case .radio:
            // AM Radio: narrowband grit — thin lows, honking midrange,
            // no air, driven and squashed, bone dry.
            p.pitchCorrectionStrength = 0.55
            p.highPassFrequency = 280
            p.warmthGainDB = -9.0
            p.presenceFrequency = 2_200
            p.presenceGainDB = 8.0
            p.presenceQ = 0.9
            p.airGainDB = -9.0
            p.saturationBlend = 0.50
            p.saturationDriveDB = 9.0
            p.reverbWet = 0.03
            p.multibandRatio = 5.0

        case .telephone:
            // Down the line: hard bandpass around speech, crunchy, dry.
            p.pitchCorrectionStrength = 0.5
            p.highPassFrequency = 750
            p.warmthFrequency = 300
            p.warmthGainDB = -14.0
            p.presenceFrequency = 1_800
            p.presenceGainDB = 9.0
            p.presenceQ = 0.8
            p.airFrequency = 8_000
            p.airGainDB = -14.0
            p.saturationBlend = 0.55
            p.saturationDriveDB = 10.0
            p.reverbWet = 0.02

        case .megaphone:
            // Loud and defiant: honking mids and full-blend hot tanh
            // drive — unmistakably a megaphone.
            p.pitchCorrectionStrength = 0.4
            p.highPassFrequency = 450
            p.warmthGainDB = -8.0
            p.presenceFrequency = 2_500
            p.presenceGainDB = 10.0
            p.presenceQ = 0.7
            p.airGainDB = -6.0
            p.saturationBlend = 1.0
            p.saturationDriveDB = 14.0
            p.reverbWet = 0.06
            p.glueRatio = 3.0
            p.multibandRatio = 5.0

        case .deep:
            // Late-night: big low-end body, subdued top, close and dry.
            p.pitchCorrectionStrength = 0.4
            p.highPassFrequency = 55
            p.warmthFrequency = 240
            p.warmthGainDB = 10.0
            p.airGainDB = -5.0
            p.presenceGainDB = -2.0
            p.reverbWet = 0.14
            p.saturationBlend = 0.30
        }
        return p
    }

    static let `default`: StudioPreset = .studio
}
