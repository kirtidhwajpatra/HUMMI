//
//  RecordingsListView.swift
//  HUMMI
//

import SwiftUI

/// The library screen: takes newest first, swipe-to-delete with
/// confirmation, and tap to open playback.
struct RecordingsListView: View {
    @Binding var path: [AppRoute]
    var onSelect: (URL) -> Void
    @State private var viewModel = RecordingsListViewModel()
    @State private var pendingDeletion: RecordingItem?

    var body: some View {
        VStack(spacing: 0) {
            customTopBar
            
            List {
            ForEach(viewModel.items) { item in
                RecordingRow(
                    item: item,
                    isPlaying: viewModel.currentlyPlayingID == item.id && viewModel.isAudioPlaying,
                    playbackProgress: viewModel.currentlyPlayingID == item.id ? viewModel.playbackProgress : nil,
                    onPlayTapped: { viewModel.togglePlayback(for: item) },
                    onRowTapped: { onSelect(item.url) }
                )
                .padding(Spacing.s)
                // The design system's quiet ink card, like Settings rows.
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Brand.ink.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Brand.ink.opacity(0.1), lineWidth: 1))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: Spacing.xs, leading: Spacing.l,
                    bottom: Spacing.xs, trailing: Spacing.l))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingDeletion = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    // Forest, not red: destructiveness is carried by the
                    // confirmation dialog, per the brand guideline.
                    .tint(Brand.forest)
                }
            }
        }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if viewModel.items.isEmpty, !viewModel.isLoading {
                EmptyStateView(
                    title: "No recordings yet",
                    systemImage: "waveform",
                    message: "Record a take or import an audio file.")
            }
        }
        // Centre the list column on wide (iPad / landscape) screens; the
        // plate behind still fills edge to edge.
        .frame(maxWidth: Spacing.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .confirmationDialog(
            "Delete this recording?",
            isPresented: deleteDialogPresented,
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                Task { await viewModel.delete(item) }
            }
        } message: { _ in
            Text("This permanently removes the audio file.")
        }
        .alert(
            "Something went wrong",
            isPresented: errorPresented
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } })
    }


    
    private var customTopBar: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    _ = path.popLast()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.ink)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            
            Spacer()

            Text("ALL RECORDINGS")
                .font(.footnote.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Brand.ink.opacity(0.55))

            Spacer()

            // Invisible placeholder for symmetry
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.xs)
        .background(Color(.systemBackground))
    }
}
