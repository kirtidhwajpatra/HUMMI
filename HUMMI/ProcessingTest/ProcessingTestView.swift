//
//  ProcessingTestView.swift
//  HUMMI
//

#if DEBUG
import SwiftUI

/// Temporary developer screen for the offline processing chain: pick a
/// take, toggle stages, render, then A/B original vs processed with an
/// instant switch at the same playback position.
struct ProcessingTestView: View {
    @State private var viewModel = ProcessingTestViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    Picker("Take", selection: $viewModel.selectedRecording) {
                        ForEach(viewModel.recordings) { item in
                            Text(item.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .tag(Optional(item))
                        }
                    }
                }

                Section("Stages") {
                    ForEach($viewModel.stageToggles) { $toggle in
                        Toggle(toggle.id, isOn: $toggle.isOn)
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.processSelected() }
                    } label: {
                        if viewModel.isProcessing {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Processing…")
                            }
                        } else {
                            Text("Process")
                        }
                    }
                    .disabled(viewModel.selectedRecording == nil || viewModel.isProcessing)

                    if let progress = viewModel.mlProgress {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress)
                            Text("ML enhance \(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let seconds = viewModel.processSeconds {
                        LabeledContent("Render time", value: String(format: "%.2f s", seconds))
                    }
                }

                if let message = viewModel.errorMessage {
                    Section("Error") {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                if viewModel.abPlayer.isLoaded {
                    abSection
                }
            }
            .navigationTitle("Processing Test")
        }
        .task {
            await viewModel.loadRecordings()
            await viewModel.autorunIfRequested()
            await viewModel.profileAutorunIfRequested()
        }
        .onDisappear {
            viewModel.abPlayer.unload()
        }
    }

    private var abSection: some View {
        Section("A/B (switches in place)") {
            Button {
                viewModel.abPlayer.togglePlayPause()
            } label: {
                Label(
                    viewModel.abPlayer.isPlaying ? "Pause" : "Play (loops)",
                    systemImage: viewModel.abPlayer.isPlaying ? "pause.fill" : "play.fill")
            }

            Toggle(isOn: Binding(
                get: { viewModel.abPlayer.listeningToProcessed },
                set: { viewModel.abPlayer.listeningToProcessed = $0 }
            )) {
                Text(viewModel.abPlayer.listeningToProcessed ? "Listening to: Processed (B)" : "Listening to: Original (A)")
                    .frame(maxWidth: .infinity)
            }
            .toggleStyle(.button)
            .tint(.blue)
        }
    }
}

#Preview {
    ProcessingTestView()
}
#endif
