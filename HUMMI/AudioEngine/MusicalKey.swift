//
//  MusicalKey.swift
//  HUMMI
//

import Foundation

/// A diatonic key: root pitch class (0 = C … 11 = B) plus mode.
nonisolated struct MusicalKey: Sendable, Equatable {
    var root: Int
    var minor: Bool

    private static let majorDegrees = [0, 2, 4, 5, 7, 9, 11]
    private static let minorDegrees = [0, 2, 3, 5, 7, 8, 10]  // natural minor
    private static let names = ["C", "C#", "D", "D#", "E", "F",
                                "F#", "G", "G#", "A", "A#", "B"]

    var scalePitchClasses: Set<Int> {
        let degrees = minor ? Self.minorDegrees : Self.majorDegrees
        return Set(degrees.map { ($0 + root) % 12 })
    }

    var name: String {
        "\(Self.names[((root % 12) + 12) % 12]) \(minor ? "minor" : "major")"
    }

    /// The in-scale integer semitone closest to a (fractional) semitone
    /// value — the note a corrected pitch should land on.
    func nearestScaleSemitone(to semitone: Double) -> Double {
        let scale = scalePitchClasses
        var best = semitone.rounded()
        var bestDistance = Double.infinity
        let center = Int(semitone.rounded())
        for candidate in (center - 6)...(center + 6) {
            let pitchClass = ((candidate % 12) + 12) % 12
            guard scale.contains(pitchClass) else { continue }
            let distance = abs(Double(candidate) - semitone)
            if distance < bestDistance {
                bestDistance = distance
                best = Double(candidate)
            }
        }
        return best
    }
}
