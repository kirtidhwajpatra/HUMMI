//
//  AnimatedBackground.swift
//  HUMMI
//

import SwiftUI

struct AnimatedBackground: View {
    var isRecording: Bool
    @State private var phase = 0.0
    
    var body: some View {
        ZStack {
            // Base background
            Color("Background", bundle: nil) // or just black if we want dark theme
                .ignoresSafeArea()
            
            // We use overlapping blurred circles for a mesh-like feel
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                
                ZStack {
                    // Orb 1
                    Circle()
                        .fill(isRecording ? Color.red.opacity(0.4) : Color.purple.opacity(0.3))
                        .frame(width: width * 0.8)
                        .offset(x: cos(phase) * 50, y: sin(phase) * 50 - height * 0.2)
                        .blur(radius: 60)
                    
                    // Orb 2
                    Circle()
                        .fill(isRecording ? Color.orange.opacity(0.3) : Color.blue.opacity(0.3))
                        .frame(width: width * 0.9)
                        .offset(x: -cos(phase * 0.8) * 60 + width * 0.2, y: -sin(phase * 0.8) * 60 + height * 0.3)
                        .blur(radius: 80)
                    
                    // Orb 3
                    Circle()
                        .fill(isRecording ? Color.pink.opacity(0.4) : Color.indigo.opacity(0.4))
                        .frame(width: width * 0.7)
                        .offset(x: sin(phase * 1.2) * 40 - width * 0.3, y: cos(phase * 1.2) * 40 + height * 0.1)
                        .blur(radius: 70)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 2.0), value: isRecording)
        .onAppear {
            withAnimation(.linear(duration: 10.0).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
