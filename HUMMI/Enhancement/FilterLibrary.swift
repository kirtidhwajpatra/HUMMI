//
//  FilterLibrary.swift
//  HUMMI
//
//  The single source of truth for Studio's live filters — 12 character
//  orbs and 8 space tiles, each carrying its audio settings AND its
//  visual identity (orb sphere palette / tile gradient) so the Aurora
//  Orb screen and the audio graph can never disagree.
//

import AVFoundation
import SwiftUI

/// The complete, intentionally small source of truth for Studio's live filters.
/// Character and space are separate so either can be changed without resetting
/// the other one.
struct RealtimePreviewSettings: Equatable {
    var lowGain: Double = 0
    var midGain: Double = 0
    var highGain: Double = 0
    var saturation: Double = 0
    var pitch: Double = 0
    var speed: Double = 1
    var tempo: Double = 1
    var autotune: Double = 0
}

/// Visual identity of a character orb: a three-stop radial sphere whose
/// highlight style sells the material (soft skin, glossy chrome, brushed
/// metal), plus the dominant `glow` used for selection halos and the
/// waveform tint.
struct OrbPalette {
    enum Highlight { case soft, gloss, metallic }

    let core: Color
    let mid: Color
    let rim: Color
    let glow: Color
    var highlight: Highlight = .soft
    var grain = false
}

/// Visual identity of a space tile: gradient stops (2–3), rendered
/// diagonally when `angled` (Plate's brassy 135° sheen), and the
/// dominant `glow` for the active halo.
struct TilePalette {
    let stops: [Color]
    let glow: Color
    var angled = false
}

struct CharacterFilter: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let glyph: String
    let orb: OrbPalette
    let settings: RealtimePreviewSettings

    var dominant: Color { orb.glow }
    var colors: [Color] { [orb.mid, orb.rim] }
}

struct SpaceFilter: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let glyph: String
    let tile: TilePalette
    let preset: AVAudioUnitReverbPreset?
    let amount: Double
    let decay: Double
    let predelay: Double

    var dominant: Color { tile.glow }
    var colors: [Color] { tile.stops }
}

enum FilterLibrary {
    static let characters: [CharacterFilter] = [
        character("default", "Default", "Cleaned up, still you", "waveform",
                  orb(0xF8FAFC, 0xE8EFFA, 0xDBEAFE, glow: 0x93C5FD),
                  0, 0, 1, 0, 0),
        character("studio", "Studio", "Polished, radio-ready vocal", "music.mic",
                  orb(0xFF6B6B, 0xE8438F, 0x7C3AED, glow: 0xE8438F),
                  1, 3, 4, 18, 0),
        character("warm", "Warm", "Cozy low-end and tape glow", "flame.fill",
                  orb(0xFCD34D, 0xF59E0B, 0xDC2626, glow: 0xF59E0B),
                  3, 0, -2, 22, 0),
        character("bright", "Bright", "Crisp presence and air", "sun.max.fill",
                  orb(0xE0F2FE, 0x38BDF8, 0x0EA5E9, glow: 0x38BDF8, highlight: .gloss),
                  -1, 3, 5, 4, 0),
        character("radio", "Radio", "Broadcast midrange, kept smooth", "radio.fill",
                  orb(0xEF4444, 0x7F1D1D, 0x1C090B, glow: 0xEF4444),
                  -10, 8, -10, 28, 0),
        character("podcast", "Podcast", "Dense, clear spoken vocal", "mic.fill",
                  orb(0xA855F7, 0x6D28D9, 0x1E1B4B, glow: 0xA855F7),
                  -2, 2, 1, 8, 0),
        character("vintage", "Vintage", "Soft tape warmth and rolled-off top", "recordingtape",
                  orb(0xFCD9A5, 0xB45309, 0x78350F, glow: 0xD97706, grain: true),
                  3, -1, -7, 35, 0),
        character("whisper", "Whisper", "Intimate breath and soft presence", "moon.stars.fill",
                  orb(0xFCE7F3, 0xF9A8D4, 0xC084FC, glow: 0xF9A8D4),
                  -2, 3, 2, 4, 0),
        character("hard-tune", "Hard Tune", "Bold, snapped pop character", "tuningfork",
                  orb(0xF1F5F9, 0x7DD3FC, 0x0369A1, glow: 0x38BDF8, highlight: .gloss),
                  -1, 4, 4, 12, 0, autotune: 1),
        character("deep", "Deep", "Full, lower and late-night", "water.waves",
                  orb(0x1E3A8A, 0x0F766E, 0x164E63, glow: 0x14B8A6),
                  3, -1, -3, 12, -3),
        character("chipmunk", "Chipmunk", "Playful, bright and lifted", "hare.fill",
                  orb(0xFEF08A, 0xA3E635, 0x16A34A, glow: 0xA3E635, highlight: .gloss),
                  -2, 2, 4, 8, 5),
        character("robot", "Robot", "Compressed sci-fi transmission", "cpu",
                  orb(0xE5E7EB, 0x6B7280, 0x1F2937, glow: 0x94A3B8, highlight: .metallic),
                  -8, 7, -7, 38, 0)
    ]

    static let spaces: [SpaceFilter] = [
        space("dry", "Dry", "No room — close and direct", "speaker.fill",
              tile(0x374151, 0x1F2937, glow: 0x4B5563), nil, 0, 0.2, 0),
        space("booth", "Booth", "Small, focused vocal booth", "shippingbox.fill",
              tile(0x7F1D1D, 0x451A03, glow: 0xB91C1C), .smallRoom, 12, 0.6, 0),
        space("studio-room", "Studio Room", "Natural, controlled room", "music.note.house.fill",
              tile(0xF59E0B, 0x78350F, glow: 0xF59E0B), .mediumRoom, 18, 1.2, 20),
        space("live-room", "Live Room", "Open room with depth", "hifispeaker.2.fill",
              tile(0xF97316, 0x7C2D12, glow: 0xF97316), .largeRoom, 25, 1.8, 30),
        space("hall", "Hall", "A graceful concert hall", "building.columns.fill",
              tile(0x7C3AED, 0x312E81, glow: 0x8B5CF6), .largeHall, 30, 2.4, 40),
        space("cathedral", "Cathedral", "Epic space, long tail", "building.columns.circle.fill",
              tile(0x2563EB, 0x1E3A8A, 0x0F172A, glow: 0x3B82F6), .cathedral, 35, 3.5, 60),
        space("plate", "Plate", "Smooth vintage plate", "rectangle.inset.filled",
              tile(0xFCD34D, 0xA16207, glow: 0xEAB308, angled: true), .plate, 22, 1.6, 0),
        space("dream", "Dream", "Ethereal shimmer and air", "sparkles",
              tile(0xFBCFE8, 0xC4B5FD, 0xA7F3D0, glow: 0xF0ABFC), .largeHall, 32, 2.8, 45)
    ]

    static func character(id: String) -> CharacterFilter { characters.first { $0.id == id } ?? characters[0] }
    static func space(id: String) -> SpaceFilter { spaces.first { $0.id == id } ?? spaces[0] }

    private static func character(
        _ id: String, _ name: String, _ tagline: String, _ glyph: String, _ orb: OrbPalette,
        _ low: Double, _ mid: Double, _ high: Double, _ saturation: Double, _ pitch: Double,
        autotune: Double = 0
    ) -> CharacterFilter {
        CharacterFilter(id: id, name: name, tagline: tagline, glyph: glyph, orb: orb,
                        settings: .init(lowGain: low, midGain: mid, highGain: high,
                                        saturation: saturation, pitch: pitch, autotune: autotune))
    }

    private static func space(
        _ id: String, _ name: String, _ tagline: String, _ glyph: String, _ tile: TilePalette,
        _ preset: AVAudioUnitReverbPreset?, _ amount: Double, _ decay: Double, _ predelay: Double
    ) -> SpaceFilter {
        SpaceFilter(id: id, name: name, tagline: tagline, glyph: glyph, tile: tile,
                    preset: preset, amount: amount, decay: decay, predelay: predelay)
    }

    private static func orb(
        _ core: UInt32, _ mid: UInt32, _ rim: UInt32, glow: UInt32,
        highlight: OrbPalette.Highlight = .soft, grain: Bool = false
    ) -> OrbPalette {
        OrbPalette(core: hex(core), mid: hex(mid), rim: hex(rim), glow: hex(glow),
                   highlight: highlight, grain: grain)
    }

    private static func tile(
        _ stops: UInt32..., glow: UInt32, angled: Bool = false
    ) -> TilePalette {
        TilePalette(stops: stops.map(hex), glow: hex(glow), angled: angled)
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}
