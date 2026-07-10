//
//  DynamicBackground.swift
//  HUMMI
//
//  A fluid, animated gradient background that reacts to touches and pulses.
//

import SwiftUI
import UIKit

public struct AppInteraction {
    public static func pulse() {
        NotificationCenter.default.post(name: Notification.Name("HUMMI_didInteract"), object: nil)
    }
}

struct DynamicBackground: View {
    @State private var isAnimating = false
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Base background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // Animated Gradients
            GeometryReader { proxy in
                ZStack {
                    // Blob 1 (Accent)
                    Circle()
                        .fill(Color.accentColor.opacity(0.35))
                        .frame(width: proxy.size.width * 1.5, height: proxy.size.width * 1.5)
                        .offset(x: isAnimating ? -proxy.size.width * 0.3 : proxy.size.width * 0.3,
                                y: isAnimating ? -proxy.size.height * 0.3 : proxy.size.height * 0.2)
                    
                    // Blob 2 (Purple)
                    Circle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: proxy.size.width * 1.2, height: proxy.size.width * 1.2)
                        .offset(x: isAnimating ? proxy.size.width * 0.4 : -proxy.size.width * 0.2,
                                y: isAnimating ? proxy.size.height * 0.4 : -proxy.size.height * 0.4)
                    
                    // Blob 3 (Orange)
                    Circle()
                        .fill(Color.orange.opacity(0.25))
                        .frame(width: proxy.size.width * 1.0, height: proxy.size.width * 1.0)
                        .offset(x: isAnimating ? -proxy.size.width * 0.2 : proxy.size.width * 0.4,
                                y: isAnimating ? proxy.size.height * 0.2 : -proxy.size.height * 0.3)
                }
                .blur(radius: 80)
            }
            .ignoresSafeArea()
            
            // Pulse Overlay
            Color.accentColor
                .opacity(isPulsing ? 0.3 : 0.0)
                .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HUMMI_didInteract"))) { _ in
            // Trigger Haptic
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            // Trigger Pulse
            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.5, blendDuration: 0.2)) {
                isPulsing = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.4)) {
                    isPulsing = false
                }
            }
        }
    }
}
