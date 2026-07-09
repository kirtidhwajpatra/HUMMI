//
//  FluidBackground.swift
//  HUMMI
//

import SwiftUI

/// A lush, slow-moving fluid background similar to Apple Siri or Apple Music.
struct FluidBackground: View {
    let colors: [Color]
    
    @State private var rotation1 = 0.0
    @State private var rotation2 = 0.0
    @State private var rotation3 = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                if colors.count >= 1 {
                    Ellipse()
                        .fill(colors[0])
                        .frame(width: geometry.size.width * 1.5, height: geometry.size.height * 1.5)
                        .offset(x: -geometry.size.width * 0.2, y: -geometry.size.height * 0.2)
                        .rotationEffect(.degrees(rotation1))
                }
                
                if colors.count >= 2 {
                    Ellipse()
                        .fill(colors[1])
                        .frame(width: geometry.size.width * 1.5, height: geometry.size.height * 1.5)
                        .offset(x: geometry.size.width * 0.2, y: geometry.size.height * 0.2)
                        .rotationEffect(.degrees(rotation2))
                }
                
                if colors.count >= 3 {
                    Ellipse()
                        .fill(colors[2])
                        .frame(width: geometry.size.width * 1.5, height: geometry.size.height * 1.5)
                        .offset(x: 0, y: -geometry.size.height * 0.1)
                        .rotationEffect(.degrees(rotation3))
                }
            }
            .blur(radius: 100)
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.linear(duration: 15).repeatForever(autoreverses: false)) {
                rotation1 = 360
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotation2 = -360
            }
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                rotation3 = 360
            }
        }
        .opacity(0.4) // Subtle, not overwhelming
    }
}
