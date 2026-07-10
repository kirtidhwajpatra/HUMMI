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
        List {
            ForEach(viewModel.items) { item in
                RecordingRow(
                    item: item,
                    isPlaying: viewModel.currentlyPlayingID == item.id,
                    onPlayTapped: { viewModel.togglePlayback(for: item) },
                    onRowTapped: { onSelect(item.url) }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingDeletion = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.items.isEmpty, !viewModel.isLoading {
                EmptyStateView(
                    title: "No recordings yet",
                    systemImage: "waveform",
                    message: "Record a take or import an audio file.")
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("All recordings")
                    .font(.title3.weight(.semibold))
            }
        }
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


}
