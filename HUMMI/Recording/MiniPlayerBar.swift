//
//  MiniPlayerBar.swift
//  HUMMI
//
//  The floating "now playing" orb. A liquid-glass circle showing elapsed
//  time over a live equaliser. Tap it and a red cancel button springs out
//  to stop playback. Drag it anywhere on screen — it follows the finger 1:1
//  and rests where you drop it, remembering the spot. Drives
//  NowPlayingController. Shown only once the user leaves the take's own
//  screen (ContentView hides it while the library list is on top).
//

import SwiftUI

struct DraggableMiniPlayer: View {
    let track: NowPlayingController.Track

    // Default to the clear right-middle band, away from top toolbars and the
    // bottom record controls; the user can drag it anywhere from there.
    @AppStorage("miniPlayerX") private var fx = 0.9
    @AppStorage("miniPlayerY") private var fy = 0.5

    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var moved = false
    @State private var showCancel = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var np: NowPlayingController { .shared }

    private let radius: CGFloat = 41

    private var timeText: String {
        let total = Int(np.elapsed.rounded())
        return String(format: "%d.%02d", total / 60, total % 60)
    }

    var body: some View {
        GeometryReader { geo in
            let inset = radius + 8
            let w = geo.size.width, h = geo.size.height
            let base = CGPoint(x: fx * w, y: fy * h)
            let px = clamp(base.x + drag.width, inset, w - inset)
            let py = clamp(base.y + drag.height, inset, h - inset)
            let flipTop = py < h * 0.4

            VStack(spacing: Spacing.s) {
                if showCancel && !flipTop { cancelButton(flipped: false) }
                orb(base: base, size: geo.size, inset: inset)
                if showCancel && flipTop { cancelButton(flipped: true) }
            }
            .scaleEffect(dragging ? 1.1 : 1)
            .position(x: px, y: py)
            .animation(.spring(response: 0.3, dampingFraction: 0.62), value: dragging)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showCancel)
            .task(id: showCancel) {
                guard showCancel else { return }
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { withAnimation { showCancel = false } }
            }
            .onChange(of: np.track) { _, newValue in
                if newValue == nil { showCancel = false }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Orb (tap + drag in one gesture)

    private func orb(base: CGPoint, size: CGSize, inset: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(timeText)
                .font(.system(size: 23, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Brand.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            EqualizerWave(active: np.isPlaying)
                .frame(width: 32, height: 13)
        }
        .padding(.horizontal, Spacing.s)
        .frame(width: 82, height: 82)
        // Non-interactive: the interactive glass re-morphs on every touch
        // move, which shimmers/shakes while dragging.
        .glassEffect(.regular, in: .circle)
        .shadow(color: .black.opacity(dragging ? 0.28 : 0.16), radius: dragging ? 20 : 14, y: 6)
        .contentShape(Circle())
        .gesture(dragGesture(base: base, size: size, inset: inset))
        .accessibilityLabel("Now playing \(track.title), \(timeText)")
        .accessibilityHint("Double tap to show stop button")
    }

    private func dragGesture(base: CGPoint, size: CGSize, inset: CGFloat) -> some Gesture {
        // Global space: measuring in the orb's own (moving) space feeds the
        // movement back into the translation and makes it jitter/shake.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let dist = hypot(value.translation.width, value.translation.height)
                // A small wobble is still a tap; only past a threshold is it a drag.
                if dist > 6 {
                    if !moved {
                        moved = true
                        dragging = true
                        Haptics.shared.play(.soft)
                    }
                    drag = value.translation
                }
            }
            .onEnded { value in
                if moved {
                    let dropX = clamp(base.x + value.translation.width, inset, size.width - inset)
                    let dropY = clamp(base.y + value.translation.height, inset, size.height - inset)
                    Haptics.shared.play(.rigid)
                    dragging = false
                    moved = false
                    // Position already tracks the finger, so just persist it.
                    fx = dropX / size.width
                    fy = dropY / size.height
                    drag = .zero
                } else {
                    Haptics.shared.play(.light)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        showCancel.toggle()
                    }
                }
            }
    }

    // MARK: - Cancel

    private func cancelButton(flipped: Bool) -> some View {
        Button {
            np.stop()
        } label: {
            Image(systemName: "xmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Self.cancelRed, in: Circle())
                .shadow(color: Self.cancelRed.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(PressScale())
        .transition(reduceMotion
            ? .opacity
            : .scale(scale: 0.2, anchor: flipped ? .top : .bottom).combined(with: .opacity))
        .accessibilityLabel("Stop playback")
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }

    private static let cancelRed = Color(red: 0.90, green: 0.23, blue: 0.21)
}

/// A press-scale style for the cancel button.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Five bars that pump up and down while playing, and rest flat when paused.
private struct EqualizerWave: View {
    let active: Bool
    private let count = 5

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<count, id: \.self) { i in
                EqualizerBar(active: active, index: i)
            }
        }
    }
}

private struct EqualizerBar: View {
    let active: Bool
    let index: Int
    @State private var raised = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lows: [CGFloat] = [5, 8, 4, 8, 5]
    private let highs: [CGFloat] = [13, 9, 13, 8, 12]
    private let periods: [Double] = [0.46, 0.34, 0.52, 0.38, 0.44]

    var body: some View {
        Capsule()
            .fill(Brand.limeDeep)
            .frame(width: 3, height: raised ? highs[index] : lows[index])
            .onChange(of: active) { _, on in animate(on) }
            .onAppear { animate(active) }
    }

    private func animate(_ on: Bool) {
        guard on, !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.2)) { raised = false }
            return
        }
        withAnimation(.easeInOut(duration: periods[index])
            .repeatForever(autoreverses: true)) {
            raised = true
        }
    }
}
