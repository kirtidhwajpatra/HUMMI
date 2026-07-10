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

            VStack(spacing: Spacing.xl) {
                nameField
                    .padding(.top, Spacing.xl)
                    .padding(.horizontal, Spacing.l)
                
                VStack(spacing: Spacing.m) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "wand.and.stars")
                        Text("Enhanced Studio Audio")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    
                    WaveformView(peaks: viewModel.peaks, tint: .accentColor, style: .bars)
                        .frame(height: 120)
                }
                .padding(.horizontal, Spacing.m)

                Text(durationText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Spacing.xl)
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 20, x: 0, y: 10)
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
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.library) {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "list.bullet")
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
        .task {
            await viewModel.onAppear()
        }
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
            Button {
                Task { await viewModel.saveAudio() }
            } label: {
                if viewModel.isExporting && viewModel.videoProgress == nil {
                    ProgressView()
                } else {
                    Label("Save Audio", systemImage: "arrow.down.document")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isExporting)

            Button {
                Task { await viewModel.shareVideo() }
            } label: {
                if viewModel.videoProgress != nil {
                    ProgressView()
                } else {
                    Label("Share Video", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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
