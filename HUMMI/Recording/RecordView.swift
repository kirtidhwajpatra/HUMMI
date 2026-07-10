//
//  RecordView.swift
//  HUMMI
//
//  The Ollin home screen workstation: manages idle recording, live recording,
//  recorded review, processing, and the final A/B comparison Studio.
//

import SwiftUI
import UniformTypeIdentifiers

struct RecordView: View {
    let viewModel: RecordingViewModel
    @Binding var phase: HomePhase
    @Binding var path: [AppRoute]
    var namespace: Namespace.ID?
    var onImportFile: (URL) -> Void = { _ in }

    @State private var showImporter = false
    @State private var showTuner = false
    @State private var scrubFocus: Double? = nil
    @AppStorage("savedLyricsData") private var lyricsData: Data = Data()
    @StateObject private var richTextContext = RichTextContext()
    @State private var showLyrics: Bool = false
    @State private var isLyricsFocused: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { viewModel.isRecording }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .idle:
                idleLayout
            case .recording:
                recordingLayout
            case .recorded(let rVM):
                recordedLayout(rVM)
            case .studio(let rVM):
                studioLayout(rVM)
            }
        }
        .frame(maxWidth: Spacing.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.l)
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
                phase = .recorded(rVM)
            }
        }
        #if DEBUG
        .task { await autorunIfRequested() }
        #endif
    }

    // MARK: - Layouts

    private var idleLayout: some View {
        VStack(spacing: showLyrics ? Spacing.m : Spacing.xl) {
            Spacer(minLength: showLyrics ? 0 : Spacing.l)
            lyricsCard

            if !isLyricsFocused {
                if showLyrics {
                    HStack(spacing: Spacing.l) {
                        RecordButton(isRecording: false) {
                            try? viewModel.start()
                        }
                        
                        recordingSurface()
                    }
                    .padding(.horizontal, Spacing.m)
                } else {
                    Spacer(minLength: 0)
                    recordingSurface()
                    Spacer(minLength: 0)
                    RecordButton(isRecording: false) {
                        try? viewModel.start()
                    }
                }
            }
            Spacer(minLength: showLyrics ? Spacing.s : Spacing.xl)
        }
        .animation(.snappy, value: isLyricsFocused)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { 
                    withAnimation(.snappy) {
                        showLyrics.toggle()
                        isLyricsFocused = showLyrics
                    }
                } label: {
                    Image(systemName: "text.quote")
                        .foregroundStyle(showLyrics ? Color.red : Color.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    private var recordingLayout: some View {
        VStack(spacing: showLyrics ? Spacing.m : Spacing.xl) {
            Spacer(minLength: showLyrics ? 0 : Spacing.l)
            lyricsCard

            if !isLyricsFocused {
                if showLyrics {
                    HStack(spacing: Spacing.l) {
                        RecordButton(isRecording: true, rms: viewModel.rms) {
                            viewModel.stop()
                        }
                        
                        recordingSurface()
                    }
                    .padding(.horizontal, Spacing.m)
                } else {
                    Spacer(minLength: 0)
                    recordingSurface()
                    Spacer(minLength: 0)
                    RecordButton(isRecording: true, rms: viewModel.rms) {
                        viewModel.stop()
                    }
                }
            }
            Spacer(minLength: showLyrics ? Spacing.s : Spacing.xl)
        }
        .animation(.snappy, value: isLyricsFocused)
    }

    private func recordedLayout(_ rVM: ResultViewModel) -> some View {
        VStack(spacing: showLyrics ? Spacing.m : Spacing.xl) {
            Spacer(minLength: showLyrics ? 0 : Spacing.l)
            lyricsCard

            if !isLyricsFocused {
                VStack(spacing: Spacing.xl) {
                    recordingSurface(rVM: rVM)
                        .padding(.horizontal, showLyrics ? Spacing.m : 0)
                    
                    HStack(spacing: Spacing.xl) {
                        // Play Button
                        Button {
                            rVM.abPlayer.togglePlayPause()
                        } label: {
                            Image(systemName: rVM.abPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.primary, in: Circle())
                        }
                        
                        // Enhance Button
                        Button {
                            Task {
                                await rVM.enhanceWithStudio()
                                phase = .studio(rVM)
                            }
                        } label: {
                            if case .enhancing = rVM.phase {
                                ProgressView().tint(.white)
                                    .frame(width: 64, height: 64)
                                    .background(Color.accentColor, in: Circle())
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 64, height: 64)
                                    .background(Color.accentColor, in: Circle())
                            }
                        }
                        .disabled(rVM.phase != .idle)

                        // Retake Button
                        Button {
                            phase = .idle
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.secondary, in: Circle())
                        }
                        .disabled(rVM.phase != .idle)
                    }
                }
            }
            Spacer(minLength: showLyrics ? Spacing.s : Spacing.xl)
        }
        .animation(.snappy, value: isLyricsFocused)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { 
                    withAnimation(.snappy) {
                        showLyrics.toggle()
                        isLyricsFocused = showLyrics
                    }
                } label: {
                    Image(systemName: "text.quote")
                        .foregroundStyle(showLyrics ? Color.red : Color.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showImporter = true } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .task {
            await rVM.onAppear()
        }
    }



    private func studioLayout(_ rVM: ResultViewModel) -> some View {
        VStack(spacing: 0) {
            
            // Hero Waveform Card
            VStack(spacing: Spacing.s) {
                Picker("Mode", selection: Binding(
                    get: { rVM.abPlayer.listeningToProcessed },
                    set: { rVM.abPlayer.listeningToProcessed = $0 }
                )) {
                    Text("Original").tag(false)
                    Text("Studio").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, Spacing.m)

                GeometryReader { geometry in
                    WaveformView(
                        peaks: rVM.peaks,
                        progress: rVM.abPlayer.isPlaying ? nil : (rVM.abPlayer.duration > 0 ? rVM.abPlayer.currentTime / rVM.abPlayer.duration : 0),
                        live: rVM.abPlayer.isPlaying ? { rVM.abPlayer.duration > 0 ? rVM.abPlayer.currentTime / rVM.abPlayer.duration : 0 } : nil,
                        style: .bars,
                        playedTint: rVM.abPlayer.listeningToProcessed ? .accentColor : .primary,
                        focusFraction: scrubFocus
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                rVM.abPlayer.setScrubbing(true)
                                let fraction = min(max(value.location.x / geometry.size.width, 0), 1)
                                rVM.abPlayer.currentTime = fraction * rVM.abPlayer.duration
                                scrubFocus = fraction
                            }
                            .onEnded { _ in
                                rVM.abPlayer.setScrubbing(false)
                                scrubFocus = nil
                            }
                    )
                }
                .frame(height: 180)
                .padding(.horizontal, Spacing.m)

                // Dedicated Playback Controls
                HStack(spacing: Spacing.xxl) {
                    Text(timeString(rVM.abPlayer.currentTime))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    Button {
                        rVM.abPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: rVM.abPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rVM.abPlayer.isPlaying ? "Pause" : "Play")
                    
                    Text(timeString(rVM.abPlayer.duration))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, Spacing.xl)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 20, x: 0, y: 10)
            .padding(Spacing.m)
            
            Spacer()
            
            // Filter Carousel
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    Text("Tone Filters")
                        .font(.title3.weight(.bold))
                    
                    Spacer()
                    
                    Button {
                        showTuner = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground), in: Circle())
                    }
                    .disabled(rVM.isRendering)
                }
                .padding(.horizontal, Spacing.l)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(StudioPreset.allCases, id: \.rawValue) { preset in
                            let isSelected = rVM.selectedPreset == preset
                            Button {
                                Task { await rVM.selectPreset(preset) }
                            } label: {
                                VStack(spacing: Spacing.s) {
                                    Image(systemName: preset.systemImage)
                                        .font(.title2)
                                    Text(preset.title)
                                        .font(.caption.weight(.medium))
                                }
                                .frame(width: 88, height: 88)
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .background(ToneFilterCardBackground(preset: preset, isSelected: isSelected))
                            }
                            .buttonStyle(.plain)
                            .disabled(rVM.isRendering)
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .navigationTitle("Studio")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Discard") { phase = .idle }
                    .foregroundStyle(.primary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { path.append(.save(rVM.originalURL)) }
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
        }
        .sheet(isPresented: $showTuner) {
            ToneTunerSheet(viewModel: rVM)
                .presentationDetents([.medium])
        }
        .onDisappear {
            rVM.tearDown()
        }
    }



    private func recordingSurface(rVM: ResultViewModel? = nil) -> some View {
        let isPlayback = rVM != nil
        let timeText = isPlayback ? timeString(rVM!.abPlayer.currentTime) : elapsedText
        
        return VStack(spacing: showLyrics ? 8 : Spacing.xl) {
            Text(timeText)
                .font(.system(size: showLyrics ? 24 : 64, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle((isPlayback || isRecording) ? Color.primary : Color(.tertiaryLabel))
                .contentTransition(.numericText())
                .accessibilityLabel(isRecording ? "Recording time" : "Ready")
                .accessibilityValue(timeText)

            if let rVM {
                GeometryReader { geometry in
                    WaveformView(
                        peaks: rVM.peaks,
                        progress: rVM.abPlayer.isPlaying ? nil : (rVM.abPlayer.duration > 0 ? rVM.abPlayer.currentTime / rVM.abPlayer.duration : 0),
                        live: rVM.abPlayer.isPlaying ? { rVM.abPlayer.duration > 0 ? rVM.abPlayer.currentTime / rVM.abPlayer.duration : 0 } : nil,
                        style: .bars,
                        playedTint: .primary
                    )
                }
                .frame(height: showLyrics ? 32 : 84)
            } else {
                LiveWaveform(
                    level: CGFloat(viewModel.rms),
                    isRecording: isRecording,
                    tint: isRecording ? .accentColor : Color(.systemGray3))
                    .frame(height: showLyrics ? 32 : 84)
                    .waveformTransitionSource(in: namespace)
            }
        }
        .padding(.vertical, showLyrics ? Spacing.m : Spacing.xl)
        .padding(.horizontal, Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: showLyrics ? 24 : 32, style: .continuous))
        .padding(.horizontal, showLyrics ? 0 : Spacing.m)
        .animation(reduceMotion ? nil : .snappy, value: isRecording)
        .animation(.snappy, value: showLyrics)
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
                                .padding(.horizontal, Spacing.s + 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        RichTextEditor(rtfData: $lyricsData, isFocused: $isLyricsFocused, context: richTextContext)
                            .padding(.horizontal, Spacing.s)
                            .padding(.top, 8)
                    }
                    .frame(maxHeight: .infinity)
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
                            .background(Color.red, in: Capsule())
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
                .layoutPriority(1)
            }
        }
    }

    // MARK: - Helpers

    private func timeString(_ time: Double) -> String {
        let total = Int(time.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
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
                    slider("Reverb", value: $viewModel.reverbAmount, range: 0...0.4)
                    slider("Noise removal", value: $viewModel.noiseRemoval, range: 0...1)
                    slider("Warmth", value: $viewModel.warmth, range: -3...6)
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
        case .balanced: return (c(0.22, 0.62, 0.55), c(0.12, 0.82, 0.42), c(0.0, 0.3, 0.6), c(0.1, 0.2, 0.1))
        case .studio:   return (c(0.93, 0.32, 0.26), c(1.0, 0.6, 0.2), c(0.8, 0.1, 0.5), c(0.2, 0.0, 0.0))
        case .warm:     return (c(0.96, 0.52, 0.22), c(1.0, 0.8, 0.2), c(0.9, 0.2, 0.1), c(1.0, 1.0, 1.0))
        case .bright:   return (c(0.90, 0.66, 0.18), c(1.0, 0.9, 0.4), c(1.0, 0.5, 0.1), c(1.0, 1.0, 0.8))
        case .vintage:  return (c(0.62, 0.46, 0.30), c(0.8, 0.6, 0.4), c(0.3, 0.2, 0.1), c(0.9, 0.8, 0.6))
        case .radio:    return (c(0.26, 0.56, 0.92), c(0.4, 0.8, 1.0), c(0.6, 0.2, 0.9), c(0.0, 0.1, 0.3))
        case .deep:     return (c(0.38, 0.36, 0.72), c(0.6, 0.2, 0.8), c(0.1, 0.1, 0.4), c(0.2, 0.4, 0.8))
        case .airy:     return (c(0.32, 0.72, 0.86), c(0.6, 0.9, 1.0), c(1.0, 1.0, 1.0), c(0.2, 0.8, 0.6))
        case .concert:  return (c(0.62, 0.32, 0.82), c(0.9, 0.4, 0.8), c(0.3, 0.1, 0.6), c(0.1, 0.0, 0.2))
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
    }
}
