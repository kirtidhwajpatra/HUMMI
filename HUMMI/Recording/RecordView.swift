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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { viewModel.isRecording }

    var body: some View {
        ZStack {
            ambientGlow
                .accessibilityHidden(true)

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
            .frame(maxWidth: Spacing.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.l)
        }
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
        VStack(spacing: 0) {
            navBar(showLibrary: true)

            Spacer(minLength: Spacing.l)

            headline

            Spacer(minLength: Spacing.l)

            recordingSurface

            Spacer(minLength: Spacing.l)

            RecordButton(isRecording: false) {
                viewModel.start()
            }

            notice

            Spacer(minLength: Spacing.l)

            importButton
                .padding(.bottom, Spacing.xl)
        }
    }

    private var recordingLayout: some View {
        VStack(spacing: 0) {
            navBar(showLibrary: false)

            Spacer(minLength: Spacing.l)

            recordingHeadline

            Spacer(minLength: Spacing.l)

            recordingSurface

            Spacer(minLength: Spacing.l)

            RecordButton(isRecording: true) {
                viewModel.stop()
            }

            notice

            Spacer(minLength: Spacing.l)

            // Hidden during recording to avoid distraction
            Color.clear
                .frame(height: 52)
                .padding(.bottom, Spacing.xl)
        }
    }

    private func recordedLayout(_ rVM: ResultViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Discard") {
                    phase = .idle
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(minHeight: 48)

                Spacer()
            }
            .padding(.top, Spacing.s)

            Spacer(minLength: Spacing.l)

            VStack(spacing: Spacing.xs) {
                Text("Review your take")
                    .font(.system(.title2, design: .default).weight(.semibold))
                Text("Ready to enhance or record again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Spacer(minLength: Spacing.xl)

            WaveformView(peaks: rVM.peaks, tint: Color(.systemGray3), style: .bars)
                .frame(height: 120)
                .padding(.horizontal, Spacing.m)

            Spacer(minLength: Spacing.xl)

            VStack(spacing: Spacing.s) {
                PrimaryCTA(
                    title: "Let's Enhance",
                    systemImage: "wand.and.stars"
                ) {
                    phase = .enhancing(rVM)
                    Task {
                        await rVM.enhanceWithStudio()
                        phase = .studio(rVM)
                    }
                }

                Button("Record Again") {
                    phase = .idle
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .task {
            await rVM.onAppear()
        }
    }

    private func enhancingLayout(_ rVM: ResultViewModel) -> some View {
        VStack(spacing: 0) {
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
                        .font(.dsCaption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.large)
                }

                Text("Enhancing your vocals\u{2026}")
                    .font(.dsCallout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Spacing.m)

            Spacer()
        }
    }

    private func studioLayout(_ rVM: ResultViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("New Take") {
                    phase = .idle
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 48)

                Spacer()

                Button("Save") {
                    path.append(.save(rVM.originalURL))
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: 48)
            }
            .padding(.top, Spacing.s)

            Spacer(minLength: Spacing.l)

            BeforeAfterToggle(isAfter: Binding(
                get: { rVM.abPlayer.listeningToProcessed },
                set: { rVM.abPlayer.listeningToProcessed = $0 }
            ))
            .padding(.top, Spacing.s)

            TimelineView(.animation(paused: !rVM.abPlayer.isPlaying)) { _ in
                HStack(spacing: Spacing.xxs) {
                    let current = Int(rVM.abPlayer.currentTime.rounded(.down))
                    Text(String(format: "%d.%02d", current / 60, current % 60))
                        .font(.system(.callout, design: .default).monospacedDigit())
                    Text("\u{00b7}")
                    Text(rVM.abPlayer.listeningToProcessed ? "Enhanced" : "Original")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, Spacing.l)

            GeometryReader { geometry in
                WaveformView(
                    peaks: rVM.peaks,
                    progress: rVM.abPlayer.isPlaying ? nil : (rVM.abPlayer.duration > 0 ? rVM.abPlayer.currentTime / rVM.abPlayer.duration : 0),
                    live: rVM.abPlayer.isPlaying ? { rVM.abPlayer.duration > 0 ? rVM.abPlayer.currentTime / rVM.abPlayer.duration : 0 } : nil,
                    style: .bars,
                    playedTint: rVM.abPlayer.listeningToProcessed ? .accentColor : .primary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            rVM.abPlayer.setScrubbing(true)
                            let fraction = min(max(value.location.x / geometry.size.width, 0), 1)
                            rVM.abPlayer.currentTime = fraction * rVM.abPlayer.duration
                        }
                        .onEnded { _ in rVM.abPlayer.setScrubbing(false) }
                )
            }
            .frame(height: 160)
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.m)

            Spacer(minLength: Spacing.l)

            ABPlaybackRow(player: rVM.abPlayer)
                .padding(.vertical, Spacing.s)
                .padding(.horizontal, Spacing.xl)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer(minLength: Spacing.l)

            VStack(spacing: Spacing.m) {
                HStack {
                    Text("Tone filters")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        showTuner = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
                    }
                    .accessibilityLabel("Fine-tune")
                }
                .padding(.horizontal, Spacing.l)

                PresetChipRow(
                    items: StudioPreset.allCases.map {
                        PresetChipModel(id: $0.rawValue, title: $0.title,
                                        systemImage: $0.systemImage, colors: toneColors($0))
                    },
                    selectedID: rVM.selectedPreset.rawValue,
                    isEnabled: !rVM.isRendering
                ) { id in
                    if let preset = StudioPreset(rawValue: id) {
                        Task { await rVM.selectPreset(preset) }
                    }
                }
            }
            .padding(.bottom, Spacing.l)
        }
        .sheet(isPresented: $showTuner) {
            ToneTunerSheet(viewModel: rVM)
                .presentationDetents([.medium])
        }
        .onDisappear {
            rVM.tearDown()
        }
    }

    // MARK: - Shared subviews

    private func navBar(showLibrary: Bool) -> some View {
        HStack {
            Image("Ollin_logo")
                .resizable()
                .scaledToFit()
                .frame(height: 30)
                .accessibilityLabel("Ollin")

            Spacer()

            if showLibrary {
                NavigationLink(value: AppRoute.library) {
                    PlaylistIcon(width: 22)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
                }
                .accessibilityLabel("Library")
            }
        }
        .padding(.top, Spacing.s)
    }

    private var headline: some View {
        VStack(spacing: Spacing.xs) {
            (Text("Record your ").foregroundStyle(.primary)
                + Text("voice").foregroundStyle(Color.accentColor))
                .font(.system(.title2, design: .default).weight(.semibold))

            Text("High quality recording, crystal clear results!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var recordingHeadline: some View {
        VStack(spacing: Spacing.xs) {
            Text("Listening\u{2026}")
                .font(.system(.title2, design: .default).weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text("Try to sing clearly in a quiet environment")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var recordingSurface: some View {
        VStack(spacing: Spacing.m) {
            Text(elapsedText)
                .font(.system(.largeTitle, design: .rounded).monospacedDigit().weight(.medium))
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
        .background(
            Radius.rect(Radius.sheet)
                .fill(isRecording
                      ? Color.accentColor.opacity(0.06)
                      : Color(.secondarySystemBackground))
        )
        .animation(reduceMotion ? nil : Motion.standard, value: isRecording)
    }

    private var notice: some View {
        Group {
            if let notice = viewModel.notice {
                Text(notice)
                    .font(.dsCallout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.m)
                    .padding(.horizontal, Spacing.m)
                    .transition(.opacity)
            }
        }
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.and.arrow.down")
                    .font(.body.weight(.medium))
                Text("Import audio")
                    .font(.body.weight(.medium))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, Spacing.xl)
            .frame(minHeight: 52)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Import an audio file to enhance")
    }

    // MARK: - Helpers

    private var elapsedText: String {
        let total = Int(viewModel.elapsed.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
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
        ZStack {
            Color(.systemBackground)

            Circle()
                .fill(Color.accentColor.opacity(0.04))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -120, y: -200)

            Circle()
                .fill(Color.accentColor.opacity(0.02))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: 140, y: 250)
        }
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
