//
//  Motion.swift
//  HUMMI
//
//  Design system — motion vocabulary. Every animation reveals, confirms,
//  guides, or celebrates. Default spring for UI, interactive spring for
//  gestures, linear only for determinate progress. Reduce Motion swaps
//  scale/slide for opacity.
//

import SwiftUI

nonisolated enum Motion {
    /// The house spring for state changes (250–350 ms feel).
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.82)
    /// Gesture-tracking spring.
    static let interactive = Animation.interactiveSpring(response: 0.35, dampingFraction: 0.82)
    /// Micro confirmations (120 ms).
    static let micro = Animation.easeInOut(duration: 0.12)
    /// Celebratory beats — capped at 500 ms.
    static let celebratory = Animation.spring(response: 0.5, dampingFraction: 0.7)
    /// Determinate progress only.
    static let progress = Animation.linear(duration: 0.2)

    /// Crossfade used as the Reduce-Motion substitute for scale/slide.
    static let reducedCrossfade = Animation.easeInOut(duration: 0.2)

    /// Returns `animation`, or a plain crossfade when Reduce Motion is on.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedCrossfade : animation
    }

    /// Shared id for the signature Record → Result waveform transition.
    static let waveformTransitionID = "take-waveform"
}

extension View {
    /// Marks this view as the source of the zoom navigation transition,
    /// when a namespace is available (no-op in previews).
    @ViewBuilder
    func waveformTransitionSource(in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: Motion.waveformTransitionID, in: namespace)
        } else {
            self
        }
    }
}
