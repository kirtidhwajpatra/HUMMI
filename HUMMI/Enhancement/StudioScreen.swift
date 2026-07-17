//
//  StudioScreen.swift
//  HUMMI
//
//  The Aurora Orb studio: a near-black canvas where the 12 character
//  orbs and 8 space tiles ARE the colour. Everything else — toolbar,
//  A/B toggle, playback — is white glass. Scoped dark; the rest of the
//  app stays light.
//

import SwiftUI

struct StudioScreen: View {
    let viewModel: ResultViewModel
    let onDiscard: () -> Void
    let onSaved: () -> Void

    @State private var showPanel = false
    @State private var showDiscardAlert = false
    @State private var scrubFocus: Double? = nil
    @State private var tooltip: String?
    @State private var tooltipDismiss: Task<Void, Never>?
    @State private var entered = false
    @AppStorage("studioCoachmarkCharacter") private var dismissedCharacterCoachmark = false
    @AppStorage("studioCoachmarkSwipe") private var dismissedSpaceCoachmark = false
    @AppStorage("studioCoachmarkPanel") private var dismissedPanelCoachmark = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            StudioTheme.canvas.ignoresSafeArea()
            StudioTheme.vignette.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    playbackSection
                    characterSection
                    spaceSection
                    panelRow
                }
                // Clears the floating tab pill so the panel row stays reachable.
                .padding(.bottom, Spacing.xxl * 2.5)
            }
            .scrollIndicators(.hidden)
        }
        .opacity(entered ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.25)) { entered = true } }
        .navigationTitle("Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GlowPillButton(title: "Discard", tint: Color(white: 0.4),
                               foreground: .white, feel: .destructive, compact: true) {
                    showDiscardAlert = true
                }
            }
            .sharedBackgroundVisibility(.hidden)  // no system glass behind our pill
            ToolbarItem(placement: .topBarTrailing) {
                GlowPillButton(title: "Save", feel: .prominent,
                               compact: true, isBusy: viewModel.isSavingStudio,
                               busyTitle: "Saving…") {
                    Task { if await viewModel.renderFinalStudioVersion() { onSaved() } }
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .alert("Discard studio session?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { onDiscard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your recording stays in your library. The filter choices here will be lost.")
        }
        .sheet(isPresented: $showPanel) {
            StudioPanelSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .overlay { if viewModel.isSavingStudio { savingOverlay } }
        .overlay(alignment: .bottom) {
            if let tooltip {
                coachPill(tooltip)
                    .padding(.bottom, Spacing.xl)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.filterTapCount)
        .task { await viewModel.prepareRealtimePreview() }
        .onDisappear { viewModel.tearDown() }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        VStack(spacing: Spacing.s) {
            abToggle.padding(.top, Spacing.m)
            waveform.frame(height: 150)
            playbackControls
        }
        .padding(.horizontal, Spacing.l)
    }

    private var abToggle: some View {
        HStack(spacing: Spacing.xxs) {
            abSegment("Original", isOn: !viewModel.abPlayer.listeningToProcessed) {
                viewModel.abPlayer.listeningToProcessed = false
            }
            abSegment("Studio", isOn: viewModel.abPlayer.listeningToProcessed) {
                viewModel.abPlayer.listeningToProcessed = true
            }
        }
        .padding(Spacing.xxs)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(Motion.micro, value: viewModel.abPlayer.listeningToProcessed)
    }

    private func abSegment(_ label: String, isOn: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? .black : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background {
                    if isOn {
                        Capsule().fill(.white)
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var waveform: some View {
        GeometryReader { geometry in
            WaveformView(
                peaks: viewModel.peaks,
                tint: .primary.opacity(0.22),
                progress: viewModel.abPlayer.isPlaying ? nil : (viewModel.abPlayer.duration > 0 ? viewModel.abPlayer.currentTime / viewModel.abPlayer.duration : 0),
                live: viewModel.abPlayer.isPlaying ? { viewModel.abPlayer.duration > 0 ? viewModel.abPlayer.currentTime / viewModel.abPlayer.duration : 0 } : nil,
                style: .bars,
                playedTint: viewModel.abPlayer.listeningToProcessed ? viewModel.selectedCharacter.dominant : .primary,
                focusFraction: scrubFocus
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        viewModel.abPlayer.setScrubbing(true)
                        let fraction = min(max(value.location.x / geometry.size.width, 0), 1)
                        viewModel.abPlayer.currentTime = fraction * viewModel.abPlayer.duration
                        scrubFocus = fraction
                    }
                    .onEnded { _ in
                        viewModel.abPlayer.setScrubbing(false)
                        scrubFocus = nil
                    }
            )
        }
    }

    private var playbackControls: some View {
        HStack(spacing: Spacing.xl) {
            Text(timeString(viewModel.abPlayer.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(StudioTheme.textSecondary)
            GlowIconButton(
                icon: viewModel.abPlayer.isPlaying ? "pause.fill" : "play.fill",
                label: viewModel.abPlayer.isPlaying ? "Pause" : "Play",
                feel: .quiet) {
                viewModel.abPlayer.togglePlayPause()
            }
            Text(timeString(viewModel.abPlayer.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(StudioTheme.textSecondary)
        }
        .padding(.bottom, Spacing.m)
    }

    // MARK: - Filter rows

    private var characterSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionHeader("Character", caption: viewModel.selectedCharacter.tagline)
            if !dismissedCharacterCoachmark {
                coachPill("Tap any orb to try a voice").padding(.horizontal, Spacing.l)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Spacing.l) {
                    ForEach(Array(FilterLibrary.characters.enumerated()), id: \.element.id) { index, filter in
                        FilterOrb(filter: filter,
                                  isActive: viewModel.selectedCharacterID == filter.id,
                                  index: index) {
                            dismissedCharacterCoachmark = true
                            viewModel.selectCharacter(filter.id)
                        } onLongPress: {
                            showTooltip("\(filter.name) · \(filter.tagline)")
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .padding(.top, Spacing.l)
    }

    private var spaceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            sectionHeader(
                "Space",
                caption: "\(viewModel.selectedSpace.name) · \(String(format: "%.1f", viewModel.reverbDecay))s decay")
            if dismissedCharacterCoachmark, viewModel.filterTapCount >= 2, !dismissedSpaceCoachmark {
                coachPill("Combine with a space").padding(.horizontal, Spacing.l)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Spacing.m) {
                    ForEach(Array(FilterLibrary.spaces.enumerated()), id: \.element.id) { index, filter in
                        SpaceTile(filter: filter,
                                  isActive: viewModel.selectedSpaceID == filter.id,
                                  index: index) {
                            dismissedSpaceCoachmark = true
                            viewModel.selectSpace(filter.id)
                        } onLongPress: {
                            showTooltip("\(filter.name) · \(filter.tagline)")
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .padding(.top, Spacing.l)
    }

    private func sectionHeader(_ title: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(StudioTheme.textPrimary)
            Spacer()
            Text(caption)
                .font(.caption)
                .foregroundStyle(StudioTheme.textSecondary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: caption)
        }
        .padding(.horizontal, Spacing.l)
    }

    // MARK: - Studio Panel row

    private var panelRow: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button {
                dismissedPanelCoachmark = true
                showPanel = true
            } label: {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.primary.opacity(0.06), in: Circle())
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.xs) {
                            Text("Studio Panel").font(.headline).foregroundStyle(.primary)
                            if viewModel.isCustomized {
                                Circle()
                                    .fill(viewModel.selectedCharacter.dominant)
                                    .frame(width: 7, height: 7)
                                    .accessibilityLabel("Custom adjustments active")
                            }
                        }
                        Text(viewModel.isCustomized ? "Custom adjustments active" : "Advanced controls · Voice, EQ, Reverb")
                            .font(.callout)
                            .foregroundStyle(StudioTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(StudioTheme.textTertiary)
                }
                .padding(Spacing.m)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            if !dismissedPanelCoachmark, dismissedSpaceCoachmark {
                coachPill("Advanced controls here")
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.l)
    }

    // MARK: - Chrome

    private func coachPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Spacing.m) {
                ZStack {
                    Circle()
                        .fill(viewModel.selectedCharacter.dominant.opacity(0.35))
                        .frame(width: 120, height: 120)
                        .blur(radius: 30)
                    ProgressView().controlSize(.large).tint(.white)
                }
                Text("Saving your studio version…")
                    .font(.callout)
                    .foregroundStyle(.white)
            }
        }
    }

    private func showTooltip(_ text: String) {
        tooltipDismiss?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { tooltip = text }
        tooltipDismiss = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { tooltip = nil }
        }
    }

    private func timeString(_ time: Double) -> String {
        let total = Int(time.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
