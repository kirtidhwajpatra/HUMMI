//
//  SplashScreen.swift
//  HUMMI
//
//  The launch moment, staged to feel like tapping the home-screen icon: the
//  app opens on the icon's note-and-waves mark, which recoils from the tap
//  and springs back, holds a beat, then hands off to the app. Tap to skip.
//  Reduce Motion trades the bounce for a calm fade. Purely presentational;
//  calls `onFinish` exactly once.
//

import SwiftUI

struct SplashScreen: View {
    /// Called once when the intro completes or the user taps to skip.
    var onFinish: () -> Void

    private let reduceMotionPreference: Bool
    @Environment(\.accessibilityReduceMotion) private var envReduceMotion
    private var reduceMotion: Bool { reduceMotionPreference || envReduceMotion }

    @State private var scale: CGFloat = 1
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 0
    @State private var finished = false

    /// The icon's dark forest field — a touch darker than the wave art so the
    /// ripple ellipses read, exactly like the app icon.
    private let forest = Color(red: 13 / 255, green: 28 / 255, blue: 3 / 255)

    init(reduceMotion: Bool = false, onFinish: @escaping () -> Void) {
        self.reduceMotionPreference = reduceMotion
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            forest.ignoresSafeArea()

            Image("SplashNote")
                .resizable()
                .scaledToFit()
                .frame(width: 150)
                .scaleEffect(scale)
                .offset(y: offsetY)
                .opacity(opacity)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement()
        .accessibilityLabel(Text("VOICE Studio"))
        .accessibilityAddTraits(.isImage)
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { opacity = 1 }
            try? await sleep(1.4)
            finish()
            return
        }

        // The app opens already recoiling from the tap — press back…
        withAnimation(.easeOut(duration: 0.12)) { opacity = 1 }
        withAnimation(.easeInOut(duration: 0.1)) {
            scale = 0.8
            offsetY = 12
        }
        try? await sleep(0.1)

        // …then snap back with a quick bounce and hold before the home screen.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.42)) {
            scale = 1
            offsetY = 0
        }
        try? await sleep(2.0)

        finish()
    }

    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

#Preview {
    SplashScreen(onFinish: {})
}
