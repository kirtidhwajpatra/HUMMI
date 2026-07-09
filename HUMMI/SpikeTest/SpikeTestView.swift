//
//  SpikeTestView.swift
//  HUMMI
//

#if DEBUG
import SwiftUI

/// Temporary developer screen proving the on-device DeepFilterNet3
/// pipeline end to end: bundled clip → enhance → WAV in Documents.
struct SpikeTestView: View {
    @State private var viewModel = SpikeTestViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Runs the bundled 30 s test clip through STFT → "
                         + "DeepFilterNet3 (Core ML) → ISTFT and writes the "
                         + "enhanced WAV to Documents.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await viewModel.run() }
                    } label: {
                        if viewModel.phase == .running {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Enhancing…")
                            }
                        } else {
                            Text("Run Enhancement")
                        }
                    }
                    .disabled(viewModel.phase == .running)
                }

                if case .failed(let message) = viewModel.phase {
                    Section("Error") {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                if let result = viewModel.result {
                    Section("Result") {
                        row("Clip length", String(format: "%.1f s", result.clipSeconds))
                        row("Model load", String(format: "%.2f s", result.modelLoadSeconds))
                        row("Processing", String(format: "%.2f s", result.processSeconds))
                        row("Realtime factor", String(format: "%.1f× realtime", result.realtimeFactor))

                        ShareLink(item: result.outputURL) {
                            Label("Share enhanced WAV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Spike Test")
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--spike-autorun"),
               viewModel.phase == .idle {
                await viewModel.run()
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }
}

#Preview {
    SpikeTestView()
}
#endif
