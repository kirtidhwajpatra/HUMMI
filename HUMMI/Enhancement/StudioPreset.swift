//
//  StudioPreset.swift
//  HUMMI
//

import Foundation

/// The user-facing enhancement presets. Each maps to a full set of DSP
/// parameters; the Result screen's four sliders (autotune, reverb, noise
/// removal, warmth) then adjust on top of the chosen preset.
nonisolated enum StudioPreset: String, CaseIterable, Identifiable, Sendable {
    case balanced   // "Default" — natural, lightly enhanced
    case studio
    case warm
    case bright
    case vintage
    case radio
    case deep
    case airy
    case concert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Default"
        case .studio: return "Studio"
        case .warm: return "Warm"
        case .bright: return "Bright"
        case .vintage: return "Vintage"
        case .radio: return "Radio"
        case .deep: return "Deep"
        case .airy: return "Airy"
        case .concert: return "Concert"
        }
    }

    var systemImage: String {
        switch self {
        case .balanced: return "wand.and.rays"
        case .studio: return "sparkles"
        case .warm: return "flame"
        case .bright: return "sun.max"
        case .vintage: return "dial.medium"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .deep: return "speaker.wave.3.fill"
        case .airy: return "wind"
        case .concert: return "music.mic"
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
            p.reverbWet = 0.12
            p.warmthGainDB = 1.5
            p.presenceGainDB = 1.0
            p.airGainDB = 1.5

        case .studio:
            break  // the shipping defaults

        case .warm:
            // Full low-end body, darker top, lush reverb, gentle tuning.
            p.warmthGainDB = 6.0
            p.airGainDB = 1.0
            p.presenceGainDB = 1.0
            p.reverbWet = 0.34
            p.saturationBlend = 0.22   // a touch more analogue warmth
            p.pitchCorrectionStrength = 0.4

        case .bright:
            // Crisp air and presence, tight (dry) reverb, firm tuning.
            p.warmthGainDB = -1.5      // trim low-end for clarity
            p.airGainDB = 7.5
            p.presenceGainDB = 4.5
            p.reverbWet = 0.08
            p.pitchCorrectionStrength = 0.7

        case .vintage:
            // Lo-fi: warm, dark top, heavy analogue grit, tight room.
            p.warmthGainDB = 3.5
            p.airGainDB = -4.0
            p.presenceGainDB = -1.0
            p.reverbWet = 0.14
            p.saturationBlend = 0.5
            p.pitchCorrectionStrength = 0.3

        case .radio:
            // Broadcast: thin low end, strong midrange presence, dry, driven.
            p.warmthGainDB = -2.0
            p.airGainDB = 1.5
            p.presenceGainDB = 6.0
            p.reverbWet = 0.05
            p.saturationBlend = 0.32
            p.pitchCorrectionStrength = 0.6

        case .deep:
            // Big low-end body, subdued top, minimal room.
            p.warmthGainDB = 8.0
            p.airGainDB = -2.5
            p.presenceGainDB = 0.0
            p.reverbWet = 0.10
            p.saturationBlend = 0.15
            p.pitchCorrectionStrength = 0.4

        case .airy:
            // Open and spacious: lots of air and a soft, wide tail.
            p.warmthGainDB = 0.0
            p.airGainDB = 7.0
            p.presenceGainDB = 2.0
            p.reverbWet = 0.32
            p.saturationBlend = 0.0
            p.pitchCorrectionStrength = 0.5

        case .concert:
            // Hall: large reverb, forward presence, a little body.
            p.warmthGainDB = 2.5
            p.airGainDB = 3.0
            p.presenceGainDB = 3.0
            p.reverbWet = 0.42
            p.saturationBlend = 0.10
            p.pitchCorrectionStrength = 0.4
        }
        return p
    }

    static let `default`: StudioPreset = .studio
}
