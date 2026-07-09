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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { viewModel.isRecording }

    var body: some View {
        ZStack {
            // Hero Dynamic Mesh Backgrounds
            if case .idle = phase {
                FluidBackground(colors: [.purple, .indigo, .pink])
                    .transition(.opacity)
            } else if case .recording = phase {
                FluidBackground(colors: [.red, .orange, .pink])
                    .transition(.opacity)
            } else if case .studio(let rVM) = phase {
                FluidBackground(colors: toneColors(rVM.selectedPreset))
                    .opacity(0.2)
                    .transition(.opacity)
            }
            
            VStack(spacing: 0) {
                switch phase {
                case .idle:
                    idleLayout
                case .recording:
                    recordingLayout
                case .recorded(let rVM):
                    recordedLayout(rVM)
                case .enhancing(let rVM):
                    enhancingLayout(rVM)
                case .studio(let rVM):
                    studioLayout(rVM)
                }
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
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.l)

            recordingSurface

            Spacer(minLength: Spacing.l)

            RecordButton(isRecording: false) {
                viewModel.start()
            }

            notice
            
            Spacer(minLength: Spacing.xl)
        }
        .navigationTitle("Record")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showImporter = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.library) {
                    Image(systemName: "list.bullet")
                }
            }
        }
    }

    private var recordingLayout: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.l)

            recordingSurface

            Spacer(minLength: Spacing.l)

            RecordButton(isRecording: true, rms: viewModel.rms) {
                viewModel.stop()
            }

            notice
            
            Spacer(minLength: Spacing.xl)
        }
        .navigationTitle("Listening...")
    }

    private func recordedLayout(_ rVM: ResultViewModel) -> some View {
        VStack(spacing: Spacing.xl) {
            Text("Review your take")
                .font(.largeTitle.weight(.bold))
                .padding(.top, Spacing.l)
                
            WaveformView(peaks: rVM.peaks, tint: Color(.systemGray3), style: .bars)
                .frame(height: 120)

            VStack(spacing: Spacing.s) {
                Button {
                    phase = .enhancing(rVM)
                    Task {
                        await rVM.enhanceWithStudio()
                        phase = .studio(rVM)
                    }
                } label: {
                    Label("Enhance Audio", systemImage: "wand.and.stars")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Discard") {
                    phase = .idle
                }
                .font(.body)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.l)
        .navigationTitle("Review")
        .task {
            await rVM.onAppear()
        }
    }

    private func enhancingLayout(_ rVM: ResultViewModel) -> some View {
        VStack(spacing: Spacing.l) {
            Spacer()

            WaveformView(peaks: rVM.peaks, tint: .accentColor, style: .bars)
                .frame(height: 120)
                .padding(.horizontal, Spacing.m)

            VStack(spacing: Spacing.xs) {
                if case .enhancing(let fraction) = rVM.phase, let fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .padding(.horizontal, Spacing.xxl)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.large)
                }

                Text("Enhancing your vocals\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .navigationTitle("Processing")
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
                .frame(height: 140)
                .padding(.horizontal, Spacing.m)

                // Dedicated Playback Controls
                HStack(spacing: Spacing.xl) {
                    Text(timeString(rVM.abPlayer.currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    Button {
                        rVM.abPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: rVM.abPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rVM.abPlayer.isPlaying ? "Pause" : "Play")
                    
                    Text(timeString(rVM.abPlayer.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, Spacing.l)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .padding(Spacing.m)
            
            // Filter Carousel
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Tone Filters")
                    .font(.headline)
                    .padding(.horizontal, Spacing.m)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.s) {
                        ForEach(StudioPreset.allCases, id: \.rawValue) { preset in
                            let isSelected = rVM.selectedPreset == preset
                            Button {
                                Task { await rVM.selectPreset(preset) }
                            } label: {
                                VStack(spacing: Spacing.xs) {
                                    Image(systemName: preset.systemImage)
                                        .font(.title2)
                                    Text(preset.title)
                                        .font(.caption.weight(.medium))
                                }
                                .frame(width: 80, height: 80)
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .background(
                                    isSelected
                                        ? AnyShapeStyle(LinearGradient(colors: toneColors(preset), startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isSelected ? Color.clear : Color(.separator), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(rVM.isRendering)
                        }
                    }
                    .padding(.horizontal, Spacing.m)
                }
            }
            .padding(.top, Spacing.s)
            
            Spacer()
        }
        .navigationTitle("Studio")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Discard") { phase = .idle }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: Spacing.m) {
                    Button {
                        showTuner = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .disabled(rVM.isRendering)
                    
                    Button("Save") { path.append(.save(rVM.originalURL)) }
                        .fontWeight(.semibold)
                }
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



    private var recordingSurface: some View {
        VStack(spacing: Spacing.xl) {
            Text(elapsedText)
                .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isRecording ? Color.primary : Color(.tertiaryLabel))
                .contentTransition(.numericText())
                .accessibilityLabel(isRecording ? "Recording time" : "Ready")
                .accessibilityValue(elapsedText)

            LiveWaveform(
                level: CGFloat(viewModel.rms),
                isRecording: isRecording,
                tint: isRecording ? .accentColor : Color(.systemGray3))
                .frame(height: 84)
                .waveformTransitionSource(in: namespace)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .snappy, value: isRecording)
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

    // MARK: - Helpers

    private func timeString(_ time: Double) -> String {
        let total = Int(time.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var elapsedText: String {
        timeString(viewModel.elapsed)
    }

    private func toneColors(_ preset: StudioPreset) -> [Color] {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch preset {
        case .balanced: return [c(0.22, 0.62, 0.55), c(0.12, 0.42, 0.42)]
        case .studio:   return [c(0.93, 0.32, 0.26), c(0.78, 0.16, 0.16)]
        case .warm:     return [c(0.96, 0.52, 0.22), c(0.88, 0.30, 0.20)]
        case .bright:   return [c(0.90, 0.66, 0.18), c(0.80, 0.45, 0.12)]
        case .vintage:  return [c(0.62, 0.46, 0.30), c(0.42, 0.30, 0.20)]
        case .radio:    return [c(0.26, 0.56, 0.92), c(0.14, 0.38, 0.74)]
        case .deep:     return [c(0.38, 0.36, 0.72), c(0.20, 0.20, 0.50)]
        case .airy:     return [c(0.32, 0.72, 0.86), c(0.20, 0.54, 0.72)]
        case .concert:  return [c(0.62, 0.32, 0.82), c(0.44, 0.20, 0.66)]
        }
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
