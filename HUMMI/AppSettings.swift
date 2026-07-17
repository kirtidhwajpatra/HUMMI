//
//  AppSettings.swift
//  HUMMI
//

import SwiftUI
import CoreHaptics

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppBackgroundStyle: String, CaseIterable, Identifiable {
    case plain = "Plain"
    case oceanBreeze = "Ocean Breeze"
    case blushPink = "Blush Pink"
    case mintGreen = "Mint Green"
    case softLavender = "Soft Lavender"
    var id: String { self.rawValue }
    
    var colors: [Color] {
        switch self {
        case .plain:
            return [
                Color.white,
                Color.black
            ]
        case .oceanBreeze:
            return [
                Color(red: 0.55, green: 0.75, blue: 0.90),
                Color(red: 0.75, green: 0.88, blue: 0.95),
                Color(red: 0.88, green: 0.93, blue: 0.97),
                Color(red: 0.35, green: 0.55, blue: 0.80)
            ]
        case .blushPink:
            return [
                Color(red: 0.98, green: 0.80, blue: 0.84),
                Color(red: 0.96, green: 0.65, blue: 0.74),
                Color(red: 0.99, green: 0.88, blue: 0.90),
                Color(red: 0.92, green: 0.55, blue: 0.68)
            ]
        case .mintGreen:
            return [
                Color(red: 0.65, green: 0.90, blue: 0.82),
                Color(red: 0.82, green: 0.96, blue: 0.90),
                Color(red: 0.55, green: 0.85, blue: 0.75),
                Color(red: 0.90, green: 0.98, blue: 0.95)
            ]
        case .softLavender:
            return [
                Color(red: 0.82, green: 0.78, blue: 0.95),
                Color(red: 0.90, green: 0.88, blue: 0.98),
                Color(red: 0.75, green: 0.65, blue: 0.92),
                Color(red: 0.68, green: 0.55, blue: 0.88)
            ]
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case m4a = "M4A (Compressed)"
    case wav = "WAV (Lossless)"
    var id: String { self.rawValue }
}

final class Haptics {
    static let shared = Haptics()
    
    @AppStorage("hapticsEnabled") private var isEnabled: Bool = true
    
    private init() {}
    
    func play(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}
