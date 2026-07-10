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
