//
//  SaveAudioView.swift
//  HUMMI
//
//  The save/share screen reached from the Result screen's "Save" action.
//  Shows the (editable) take name over its waveform, and exports the
//  enhanced render as audio or a share video.
//

import SwiftUI

struct SaveAudioView: View {
    @State private var viewModel: ResultViewModel
    /// Opens the "All recordings" library.
    var onOpenPlaylist: () -> Void = {}

    init(url: URL, onOpenPlaylist: @escaping () -> Void = {}) {
        self._viewModel = State(initialValue: ResultViewModel(originalURL: url))
        self.onOpenPlaylist = onOpenPlaylist
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.xl)

            // 1. Premium Name Field above the card
            nameField
                .padding(.bottom, Spacing.m)
                .padding(.horizontal, Spacing.l)
            
            // 2. Playable Media Card
            VStack(spacing: Spacing.xl) {
                // Badge
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "wand.and.stars.inverse")
                    Text("Enhanced Studio Audio")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .background(Color.accentColor, in: Capsule())
                .padding(.top, Spacing.xl)
                
                // Playable Waveform Area
                VStack(spacing: Spacing.m) {
                    ZStack {
                        GeometryReader { geometry in
                            WaveformView(
                                peaks: viewModel.peaks,
                                progress: viewModel.abPlayer.isPlaying ? nil : (viewModel.abPlayer.duration > 0 ? viewModel.abPlayer.currentTime / viewModel.abPlayer.duration : 0),
                                live: viewModel.abPlayer.isPlaying ? { viewModel.abPlayer.duration > 0 ? viewModel.abPlayer.currentTime / viewModel.abPlayer.duration : 0 } : nil,
                                style: .bars,
                                playedTint: .primary
                            )
                        }
                        .frame(height: 80)
                    }

                    // Playback Controls
                    HStack(spacing: Spacing.xl) {
                        Text(timeString(viewModel.abPlayer.currentTime))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        
                        Button {
                            viewModel.abPlayer.togglePlayPause()
                        } label: {
                            Image(systemName: viewModel.abPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.abPlayer.isPlaying ? "Pause" : "Play")
                        
                        Text(timeString(viewModel.duration))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 30, x: 0, y: 15)
            .padding(.horizontal, Spacing.m)

            Spacer(minLength: Spacing.xl)

            exportButtons
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: Spacing.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
        }
        .sheet(item: shareBinding) { item in
            ShareSheet(url: item.url)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: paywallBinding) { reason in
            PaywallPlaceholderView(reason: reason)
                .presentationBackground(.thinMaterial)
        }
        .onDisappear { viewModel.commitName() }
        .task {
            await viewModel.onAppear()
        }
    }

    // MARK: - Editable name

    private var nameField: some View {
        TextField("Recording", text: $viewModel.displayName)
            .font(.largeTitle.weight(.heavy))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .lineLimit(1)
            .accessibilityLabel("Recording name")
            .accessibilityHint("Tap to rename")
    }

    // MARK: - Export

    private var exportButtons: some View {
        VStack(spacing: Spacing.m) {
            Button {
                Task { await viewModel.saveAudio() }
            } label: {
                if viewModel.isExporting && viewModel.videoProgress == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "waveform")
                        Text("Save Audio")
                        Spacer()
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .font(.title3.weight(.bold))
            .tint(Color.accentColor)
            .disabled(viewModel.isExporting)

            Button {
                Task { await viewModel.shareVideo() }
            } label: {
                if viewModel.videoProgress != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Image(systemName: "video")
                        Text("Share Video")
                        Spacer()
                        Image(systemName: "square.and.arrow.up.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .font(.title3.weight(.bold))
            .tint(Color(.tertiarySystemFill))
            .foregroundStyle(.primary)
            .disabled(viewModel.isExporting)

            if let progress = viewModel.videoProgress {
                ProgressPill(label: "Rendering video \(Int(progress * 100))%", value: progress)
            } else if viewModel.isExporting {
                ProgressPill(label: "Exporting\u{2026}")
            }
        }
        .animation(Motion.standard, value: viewModel.videoProgress != nil)
    }

    private func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let totalSeconds = max(Int(time.rounded()), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var shareBinding: Binding<ShareItem?> {
        Binding(get: { viewModel.shareItem }, set: { viewModel.shareItem = $0 })
    }

    private var paywallBinding: Binding<PaywallPlaceholderView.Reason?> {
        Binding(get: { viewModel.paywallReason }, set: { viewModel.paywallReason = $0 })
    }
}
