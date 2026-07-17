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
    @Bindable var viewModel: ResultViewModel
    /// Opens the "All recordings" library.
    var onOpenPlaylist: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.xl)

            nameField
                .padding(.bottom, Spacing.m)
                .padding(.horizontal, Spacing.l)
            
            VStack(spacing: Spacing.m) {
                HStack(spacing: Spacing.xs) {
                    IconTile(systemImage: "wand.and.stars",
                             colors: [.pink, .orange], size: 24)
                    Text("Enhanced Studio Audio")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)

                GeometryReader { geometry in
                    WaveformView(
                        peaks: viewModel.peaks,
                        progress: viewModel.abPlayer.isPlaying ? nil : (viewModel.abPlayer.duration > 0 ? viewModel.abPlayer.currentTime / viewModel.abPlayer.duration : 0),
                        live: viewModel.abPlayer.isPlaying ? { viewModel.abPlayer.duration > 0 ? viewModel.abPlayer.currentTime / viewModel.abPlayer.duration : 0 } : nil,
                        style: .bars,
                        playedTint: .accentColor
                    )
                }
                .frame(height: 80)

                HStack(spacing: Spacing.xl) {
                    Text(timeString(viewModel.abPlayer.currentTime))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    GlowIconButton(
                        icon: viewModel.abPlayer.isPlaying ? "pause.fill" : "play.fill",
                        label: viewModel.abPlayer.isPlaying ? "Pause" : "Play",
                        feel: .quiet) {
                        viewModel.abPlayer.togglePlayPause()
                    }
                    
                    Text(timeString(viewModel.duration))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.l)

            Spacer(minLength: Spacing.xl)

            exportButtons
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: Spacing.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
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

    private var exportButtons: some View {
        VStack(spacing: Spacing.s) {
            GlowPillButton(
                title: "Save Audio", icon: "arrow.down.document",
                feel: .prominent,
                isBusy: viewModel.isExporting && viewModel.videoProgress == nil,
                busyTitle: "Exporting…") {
                Task { await viewModel.saveAudio() }
            }
            .disabled(viewModel.isExporting)

            GlowPillButton(
                title: "Share as Video", icon: "play.rectangle",
                tint: Brand.forest, foreground: Brand.lime, feel: .standard,
                isBusy: viewModel.isExporting && viewModel.videoProgress != nil,
                busyTitle: "Exporting Video", progress: viewModel.videoProgress) {
                Task { await viewModel.shareVideo() }
            }
            .disabled(viewModel.isExporting)

            Text("Your enhanced take, ready to send anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.xxs)
        }
        .animation(Motion.standard, value: viewModel.isExporting)
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
