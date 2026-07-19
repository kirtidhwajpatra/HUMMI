//
//  AppTransition.swift
//  HUMMI
//

import SwiftUI

/// Defines the transition style for full-screen routing
enum AppTransition: String, CaseIterable, Identifiable {
    case slide = "System Slide"
    case fade = "Smooth Fade"
    case scale = "Gentle Scale"
    case zoom = "Deep Zoom"
    case flyUp = "Fly Up"
    case dropDown = "Drop Down"
    case spin = "Spin & Fade"
    case flip3D = "3D Flip"
    case springBounce = "Spring Bounce"
    case cinematic = "Cinematic"
    
    var id: String { self.rawValue }
    
    /// Returns the active transition, combining insertion and removal
    var anyTransition: AnyTransition {
        switch self {
        case .slide:
            // The routed screen overlays a base that never moves, so the
            // overlay must LEAVE through the edge it ENTERED from: push
            // slides in right-to-left, back slides out left-to-right —
            // the reverse motion users expect from a pop.
            return .move(edge: .trailing)
            
        case .fade:
            return .opacity
            
        case .scale:
            return .scale(scale: 0.9).combined(with: .opacity)
            
        case .zoom:
            // Symmetric so back plays the exact reverse (shrinks away).
            return .scale(scale: 0.1).combined(with: .opacity)
            
        case .flyUp:
            return .move(edge: .bottom).combined(with: .opacity)
            
        case .dropDown:
            return .move(edge: .top).combined(with: .opacity)
            
        case .spin:
            // Symmetric so back unwinds the same spin it arrived with.
            return .modifier(
                active: SpinModifier(angle: 180, scale: 0.5, opacity: 0),
                identity: SpinModifier(angle: 0, scale: 1, opacity: 1))

        case .flip3D:
            // Symmetric so back flips through the same edge in reverse.
            return .modifier(
                active: FlipModifier(angle: 90, opacity: 0),
                identity: FlipModifier(angle: 0, opacity: 1))
            
        case .springBounce:
            return .asymmetric(
                insertion: .scale(scale: 0.5).combined(with: .opacity),
                removal: .scale(scale: 0.5).combined(with: .opacity)
            )
            
        case .cinematic:
            return .asymmetric(
                insertion: .modifier(active: CinematicModifier(blur: 20, scale: 1.2, opacity: 0), identity: CinematicModifier(blur: 0, scale: 1, opacity: 1)),
                removal: .modifier(active: CinematicModifier(blur: 20, scale: 1.2, opacity: 0), identity: CinematicModifier(blur: 0, scale: 1, opacity: 1))
            )
        }
    }
}

// MARK: - Custom Transition Modifiers

struct SpinModifier: ViewModifier {
    let angle: Double
    let scale: CGFloat
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

struct FlipModifier: ViewModifier {
    let angle: Double
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
            .opacity(opacity)
    }
}

struct CinematicModifier: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double
    
    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale)
            .opacity(opacity)
    }
}
