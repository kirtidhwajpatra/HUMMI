//
//  RecordView.swift
//  HUMMI
//
//  The Ollin home screen workstation: manages idle recording, live recording,
//  recorded review, processing, and the final A/B comparison Studio.
//

import AudioToolbox
import SwiftUI
import UniformTypeIdentifiers

struct RecordView: View {
    let viewModel: RecordingViewModel
    @Binding var phase: HomePhase
    @Binding var path: [AppRoute]
    var namespace: Namespace.ID?
    var onImportFile: (URL) -> Void = { _ in }
    @Binding var showLyrics: Bool

    @State private var showImporter = false
    @AppStorage("savedLyricsData") private var lyricsData: Data = Data()
    @StateObject private var richTextContext = RichTextContext()
    @State private var isLyricsFocused: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { viewModel.isRecording }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .idle, .recording, .recorded:
                homeCanvas(phase: phase)
            case .studio(let rVM):
                studioLayout(rVM)
            }
        }
        .frame(maxWidth: Spacing.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .animation(reduceMotion ? .none : Motion.standard, value: phase)
        .sensoryFeedback(trigger: isRecording) { _, recording in
            recording ? Haptic.recordStart : Haptic.recordStop
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { onImportFile(url) }
        }
        .onChange(of: viewModel.isRecording) { _, isRecording in
            if isRecording {
                phase = .recording
            }
        }
        .onChange(of: viewModel.lastRecording) { _, url in
            if let url {
                let rVM = ResultViewModel(originalURL: url)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--studio-autorun") {
                    phase = .studio(rVM)
                    return
                }
                #endif
                phase = .recorded(rVM)
            }
        }
        .task(id: phase) {
            if case .recorded(let rVM) = phase {
                await rVM.onAppear()
            }
        }
        #if DEBUG
        .task { await autorunIfRequested() }
        #endif
    }

    // MARK: - Layouts

    /// The living home canvas: an aurora that breathes with the voice,
    /// glowing bars centre-stage, and one glowing mic. Once recorded,
    /// the waveform and playback controls seamlessly appear here.
    private func homeCanvas(phase: HomePhase) -> some View {
        let isRecording = (phase == .recording)
        let rVM: ResultViewModel? = {
            if case .recorded(let vm) = phase { return vm }
            return nil
        }()
        
        return ZStack {
            AuroraBackground(energy: isRecording ? CGFloat(viewModel.rms) : 0)


            VStack(spacing: Spacing.m) {
                if showLyrics {
                    // No masthead here — the script gets the whole canvas,
                    // full width and full height.
                    lyricsCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                } else {

                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                    statusHeader(phase: phase, rVM: rVM)
                    VoiceGlowBars(level: CGFloat(viewModel.rms), isRecording: isRecording, isIdle: phase == .idle)
                    Spacer(minLength: 0)
                    canvasCaption(phase: phase, rVM: rVM)
                        .padding(.bottom, Spacing.l)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
            // Reserved space for the pinned control row below; while the
            // editor has the keyboard the controls are hidden, so the
            // script can use the room instead.
            .padding(.bottom, isLyricsFocused ? Spacing.m : 180)
        }
        // The controls live in a bottom overlay, NOT in the content
        // stack, so toggling the script (or any content change) can
        // never shove the record and import buttons around — they only
        // ever fade while the editor has the keyboard.
        .overlay(alignment: .top) {
            HStack {
                Button {
                    path.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .disabled(phase != .idle || showLyrics)
                .opacity((phase == .idle && !showLyrics) ? 1 : 0)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button {
                        path.append(.library)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Brand.ink)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .disabled(phase != .idle || showLyrics)
                    .opacity((phase == .idle && !showLyrics) ? 1 : 0)
                    
                    Button {
                        withAnimation(.snappy) {
                            showLyrics.toggle()
                            isLyricsFocused = showLyrics
                        }
                    } label: {
                        Image(systemName: showLyrics ? "xmark" : "text.quote")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Brand.ink)
                            .frame(width: 62, height: 44)
                            .background(Color(.systemBackground))
                            .clipShape(Capsule())
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .opacity(phase == .idle ? 1 : 0)
                    .disabled(phase != .idle)
                    .accessibilityLabel(showLyrics ? "Hide script" : "Show script")
                    .accessibilityHidden(phase != .idle)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.s)
        }
        .overlay(alignment: .bottom) {
            if !isLyricsFocused {
                controlRow(phase: phase, rVM: rVM)
                    .padding(.horizontal, Spacing.l + Spacing.s)
                    // Clears the floating nav bar pill which now sits lower.
                    .padding(.bottom, 84)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: isLyricsFocused)
        .animation(.snappy, value: showLyrics)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Masthead: a quiet eyebrow line over rounded-heavy display type in
    /// the brand ink. Recording swaps it for LISTENING and the big timer.
    /// The frame height is FIXED so the swap never shifts the layout
    /// below it — that was the "button jumps when recording starts" bug.
    private func statusHeader(phase: HomePhase, rVM: ResultViewModel?) -> some View {
        let isRecording = (phase == .recording)
        let isPlayback = (rVM != nil)
        let timeText = isPlayback 
            ? (rVM!.abPlayer.isPlaying ? timeString(rVM!.abPlayer.currentTime) : String(format: "%.1fs", rVM!.duration))
            : elapsedText
        
        return Text(timeText)
            .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Brand.ink.opacity(0.4))
            .contentTransition(.numericText())
            .accessibilityLabel(isRecording ? "Recording time" : "Playback time")
            .accessibilityValue(timeText)
            .padding(.bottom, Spacing.xs)
            .opacity(phase == .idle ? 0 : 1)
            .animation(.snappy, value: phase)
    }

    private func canvasCaption(phase: HomePhase, rVM: ResultViewModel?) -> some View {
        let isRecording = (phase == .recording)
        let isPlayback = (rVM != nil)
        let defaultText = isPlayback
            ? (rVM!.isRendering ? "Polishing your vocal — this takes a few seconds" : "Great take. Hear it back, then make it studio ✨")
            : (isRecording ? "Sing your heart out — every word lands in the studio" : "Hit record and sing. One tap makes it sound produced.")
            
        return Text(viewModel.notice ?? defaultText)
            .font(.body.weight(.medium))
            .foregroundStyle(Brand.ink.opacity(0.65))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
            .frame(height: 56)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: phase)
    }

    private func controlRow(phase: HomePhase, rVM: ResultViewModel?) -> some View {
        let isRecording = (phase == .recording)
        
        return HStack {
            // Left Button
            if let rVM {
                GlowIconButton(
                    icon: rVM.abPlayer.isPlaying ? "pause.fill" : "play.fill",
                    label: rVM.abPlayer.isPlaying ? "Pause" : "Play",
                    feel: .quiet, size: CGSize(width: 72, height: 50)) {
                    rVM.abPlayer.togglePlayPause()
                }
            } else {
                Color.clear
                    .frame(width: 72, height: 50)
            }

            Spacer()

            // Center Button
            if let rVM {
                GlowPillButton(
                    title: "Process Audio",
                    feel: .prominent,
                    isBusy: isEnhancing(rVM), busyTitle: "Polishing…") {
                    Task {
                        await rVM.enhanceWithStudio()
                        self.phase = .studio(rVM)
                    }
                }
                .disabled(rVM.phase != .idle && !isEnhancing(rVM))
            } else {
                RecordButton(isRecording: isRecording, rms: viewModel.rms) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if isRecording {
                        AudioServicesPlaySystemSound(1114)  // end_record.caf
                        viewModel.stop()
                    } else {
                        AudioServicesPlaySystemSound(1113)  // begin_record.caf
                        viewModel.start()
                    }
                }
            }

            Spacer()

            // Right Button
            if let rVM {
                GlowIconButton(
                    icon: "xmark", label: "Retake",
                    tint: AnyShapeStyle(LinearGradient(
                        colors: [Color.red.opacity(0.35), Color.red.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )),
                    foreground: Brand.forest,
                    style: .quiet, feel: .destructive, size: CGSize(width: 72, height: 50)) {
                    self.phase = .idle
                }
                .disabled(rVM.phase != .idle)
            } else {
                GlowIconButton(
                    icon: isRecording ? "xmark" : "square.and.arrow.down",
                    label: isRecording ? "Cancel recording" : "Import audio",
                    style: .secondary,
                    feel: isRecording ? .destructive : .standard,
                    size: CGSize(width: 72, height: 50),
                    weight: .regular) {
                    if isRecording {
                        viewModel.cancel()
                        self.phase = .idle
                    } else {
                        showImporter = true
                    }
                }
                .opacity(showLyrics && !isRecording ? 0 : 1)
                .disabled(showLyrics && !isRecording)
                .accessibilityHidden(showLyrics && !isRecording)
            }
        }
        .padding(.horizontal, Spacing.s)
        .animation(.snappy, value: phase)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }



    private func studioLayout(_ rVM: ResultViewModel) -> some View {
        StudioScreen(
            viewModel: rVM,
            onDiscard: { phase = .idle },
            onSaved: { path.append(.save(rVM)) })
    }



    private var notice: some View {
        Group {
            if let notice = viewModel.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.m)
                    .padding(.horizontal, Spacing.m)
                    .transition(.opacity)
            }
        }
    }

    private var lyricsCard: some View {
        Group {
            if showLyrics {
                VStack(spacing: Spacing.s) {
                    HStack {
                        Text("Script")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isLyricsFocused {
                            Button { richTextContext.changeFontSize(increase: false) } label: { Image(systemName: "textformat.size.smaller") }
                            Button { richTextContext.changeFontSize(increase: true) } label: { Image(systemName: "textformat.size.larger") }
                            Button { richTextContext.toggleBold() } label: { Image(systemName: "bold") }
                            ColorPicker("", selection: Binding(get: { .black }, set: { c in richTextContext.changeColor(UIColor(c)) })).labelsHidden()
                        }
                    }
                    .padding(.horizontal, Spacing.s)
                    .transition(.opacity)

                    ZStack(alignment: .topLeading) {
                        if richTextContext.isEmpty {
                            Text("Paste your recording script")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(.tertiaryLabel))
                                .padding(.horizontal, Spacing.m)
                                .padding(.top, Spacing.m)
                                .allowsHitTesting(false)
                        }
                        RichTextEditor(rtfData: $lyricsData, isFocused: $isLyricsFocused, context: richTextContext)
                            .padding(.horizontal, Spacing.m)
                            .padding(.top, Spacing.m)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            .blendMode(.overlay)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)

                    if isLyricsFocused {
                        HStack {
                            Spacer()
                            Button("Done") {
                                isLyricsFocused = false
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.accentColor, in: Capsule())
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Spacing.xs)
                // A quiet crossfade: toggling the script is an in-place
                // state change, not a screen navigation — it must never
                // look like the routing transition.
                .transition(.opacity)
                .layoutPriority(1)
            }
        }
    }

    // MARK: - Helpers

    private func isEnhancing(_ rVM: ResultViewModel) -> Bool {
        if case .enhancing = rVM.phase { return true }
        return false
    }

    private func timeString(_ time: Double) -> String {
        let total = Int(time.rounded(.down))
        if total == 0 {
            return "0"
        } else if total < 60 {
            return "\(total)s"
        } else {
            return String(format: "%d.%02ds", total / 60, total % 60)
        }
    }

    private var elapsedText: String {
        timeString(viewModel.elapsed)
    }

    #if DEBUG
    private func autorunIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--record-autorun"),
              !viewModel.isRecording else { return }
        viewModel.start()
        try? await Task.sleep(for: .seconds(3))
        viewModel.stop()
    }
    #endif

    private var ambientGlow: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }
}

struct ToneTunerSheet: View {
    @Bindable var viewModel: ResultViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    slider("Autotune", value: $viewModel.autotuneStrength, range: 0...1)
                    slider("Reverb", value: $viewModel.reverbAmount, range: 0...0.7)
                    slider("Noise removal", value: $viewModel.noiseRemoval, range: 0...1)
                    slider("Warmth", value: $viewModel.warmth, range: -15...10)
                } footer: {
                    Text("Fine-tune the selected filter. Apply re-renders your take with the new settings.")
                }
            }
            .navigationTitle("Fine-tune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        Task { await viewModel.applyAdjustments() }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isDirty || viewModel.isRendering)
                }
            }
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text(label).font(.dsCaption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.dsCaption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Slider(value: value, in: range).tint(.accentColor)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

struct ToneFilterCardBackground: View {
    let preset: StudioPreset
    let isSelected: Bool

    var baseColors: (Color, Color, Color, Color) {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch preset {
        case .balanced:  return (c(0.22, 0.62, 0.55), c(0.12, 0.82, 0.42), c(0.0, 0.3, 0.6), c(0.1, 0.2, 0.1))
        case .studio:    return (c(0.93, 0.32, 0.26), c(1.0, 0.6, 0.2), c(0.8, 0.1, 0.5), c(0.2, 0.0, 0.0))
        case .hardTune:  return (c(0.20, 0.70, 0.95), c(0.55, 0.95, 1.0), c(0.10, 0.35, 0.90), c(0.9, 1.0, 1.0))
        case .warm:      return (c(0.96, 0.52, 0.22), c(1.0, 0.8, 0.2), c(0.9, 0.2, 0.1), c(1.0, 1.0, 1.0))
        case .bright:    return (c(0.90, 0.66, 0.18), c(1.0, 0.9, 0.4), c(1.0, 0.5, 0.1), c(1.0, 1.0, 0.8))
        case .airy:      return (c(0.32, 0.72, 0.86), c(0.6, 0.9, 1.0), c(1.0, 1.0, 1.0), c(0.2, 0.8, 0.6))
        case .concert:   return (c(0.62, 0.32, 0.82), c(0.9, 0.4, 0.8), c(0.3, 0.1, 0.6), c(0.1, 0.0, 0.2))
        case .canyon:    return (c(0.80, 0.45, 0.28), c(0.95, 0.70, 0.45), c(0.55, 0.30, 0.20), c(0.95, 0.85, 0.70))
        case .vintage:   return (c(0.62, 0.46, 0.30), c(0.8, 0.6, 0.4), c(0.3, 0.2, 0.1), c(0.9, 0.8, 0.6))
        case .radio:     return (c(0.26, 0.56, 0.92), c(0.4, 0.8, 1.0), c(0.6, 0.2, 0.9), c(0.0, 0.1, 0.3))
        case .telephone: return (c(0.38, 0.42, 0.48), c(0.58, 0.62, 0.68), c(0.20, 0.22, 0.28), c(0.82, 0.86, 0.90))
        case .megaphone: return (c(0.90, 0.30, 0.15), c(1.0, 0.55, 0.10), c(0.60, 0.10, 0.10), c(1.0, 0.9, 0.6))
        case .deep:      return (c(0.38, 0.36, 0.72), c(0.6, 0.2, 0.8), c(0.1, 0.1, 0.4), c(0.2, 0.4, 0.8))
        }
    }

    var body: some View {
        let (c1, c2, c3, c4) = baseColors
        ZStack {
            if isSelected {
                c1
                Circle().fill(c2).frame(width: 100).offset(x: -30, y: -30).blur(radius: 20)
                Circle().fill(c3).frame(width: 100).offset(x: 30, y: 30).blur(radius: 20)
                Circle().fill(c4).frame(width: 80).offset(x: -30, y: 30).blur(radius: 15).opacity(0.8)
            } else {
                Color(.secondarySystemGroupedBackground)
                Circle().fill(c1.opacity(0.15)).frame(width: 80).offset(x: -20, y: -20).blur(radius: 20)
                Circle().fill(c2.opacity(0.1)).frame(width: 80).offset(x: 20, y: 20).blur(radius: 20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.5) : Color(.separator), lineWidth: 0.5)
                .blendMode(isSelected ? .overlay : .normal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .padding(1)
                .blur(radius: 1)
                .opacity(isSelected ? 1 : 0)
        )
        .overlay(
            // Gloss: light catching the top of the card.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(isSelected ? 0.32 : 0.16), .clear],
                        startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(isSelected ? 0.22 : 0.07),
                radius: isSelected ? 10 : 5, y: 4)
    }
}
