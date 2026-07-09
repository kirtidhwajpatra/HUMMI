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
                .padding(.horizontal, Spacing.l)

            Spacer(minLength: Spacing.xxl)

            WaveformView(peaks: viewModel.peaks, tint: .accentColor, style: .bars)
                .frame(height: 100)
                .padding(.horizontal, Spacing.m)

            Text(durationText)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.xxl)

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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onOpenPlaylist()
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        PlaylistIcon(width: 16)
                        Text("Playlist")
                    }
                    .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Playlist")
            }
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
    }

    // MARK: - Editable name

    private var nameField: some View {
        TextField("Recording", text: $viewModel.displayName)
            .font(.title2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .lineLimit(1)
            .accessibilityLabel("Recording name")
            .accessibilityHint("Tap to rename")
    }

    // MARK: - Export

    private var exportButtons: some View {
        VStack(spacing: Spacing.s) {
            PrimaryCTA(
                title: "Save Audio",
                systemImage: "arrow.down.document",
                isLoading: viewModel.isExporting && viewModel.videoProgress == nil
            ) {
                Task { await viewModel.saveAudio() }
            }
            .disabled(viewModel.isExporting)

            PrimaryCTA(
                title: "Share Video",
                systemImage: "square.and.arrow.up",
                isLoading: viewModel.videoProgress != nil,
                isSecondary: true
            ) {
                Task { await viewModel.shareVideo() }
            }
            .disabled(viewModel.isExporting)

            if let progress = viewModel.videoProgress {
                ProgressPill(label: "Rendering video \(Int(progress * 100))%", value: progress)
            } else if viewModel.isExporting {
                ProgressPill(label: "Exporting\u{2026}")
            }
        }
        .animation(Motion.standard, value: viewModel.videoProgress != nil)
    }

    private var durationText: String {
        let total = Int(viewModel.duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var shareBinding: Binding<ShareItem?> {
        Binding(get: { viewModel.shareItem }, set: { viewModel.shareItem = $0 })
    }

    private var paywallBinding: Binding<PaywallPlaceholderView.Reason?> {
        Binding(get: { viewModel.paywallReason }, set: { viewModel.paywallReason = $0 })
    }
}
