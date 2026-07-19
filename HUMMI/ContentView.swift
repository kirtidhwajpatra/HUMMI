//
//  ContentView.swift
//  HUMMI
//
//  Created by Uday on 05/07/26.
//

import SwiftUI

/// Where the app's single navigation stack can go.
enum AppRoute: Hashable {
    case save(ResultViewModel)
    case library
    case settings
}

enum HomePhase: Equatable {
    case idle
    case recording
    case recorded(ResultViewModel)
    case studio(ResultViewModel)

    static func == (lhs: HomePhase, rhs: HomePhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.recording, .recording): return true
        case (.recorded(let l), .recorded(let r)): return l === r
        case (.studio(let l), .studio(let r)): return l === r
        default: return false
        }
    }
}

struct ContentView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("appTransition") private var appTransition: AppTransition = .slide
    
    @State private var audioSession = AudioSessionManager()
    @State private var recording = RecordingViewModel()
    @State private var homePath: [AppRoute] = []
    @State private var homePhase: HomePhase = .idle
    @Namespace private var transition
    #if DEBUG
    @State private var showSpikeTest =
        ProcessInfo.processInfo.arguments.contains("--spike-autorun")
    @State private var showProcessingTest =
        ProcessInfo.processInfo.arguments.contains(ProcessingTestViewModel.autorunArgument)
        || ProcessInfo.processInfo.arguments.contains(ProcessingTestViewModel.profileAutorunArgument)
    #endif

    @State private var showLyrics: Bool = false

    var body: some View {
        ZStack {
            sessionContent
                .zIndex(0)
            
            ForEach(Array(homePath.enumerated()), id: \.offset) { index, route in
                Group {
                    switch route {
                    case .save(let rVM):
                        SaveAudioView(viewModel: rVM, path: $homePath)
                    case .library:
                        RecordingsListView(path: $homePath) { selectedURL in
                            let rVM = ResultViewModel(originalURL: selectedURL)
                            homePhase = .studio(rVM)
                            homePath.removeAll()
                        }
                    case .settings:
                        SettingsView(path: $homePath)
                    }
                }
                .transition(appTransition.anyTransition)
                .zIndex(Double(index + 1))
                .id(route.hashValue)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: homePath)
        .overlay(alignment: .top) {
            if ToastManager.shared.isShowing {
                ToastView(
                    message: ToastManager.shared.message,
                    icon: ToastManager.shared.icon,
                    isProcessing: ToastManager.shared.isProcessing
                )
                .padding(.top, Spacing.s)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
    }

    private var sessionContent: some View {
        VStack(spacing: 16) {
            switch audioSession.state {
            case .idle:
                ProgressView("Preparing microphone…")
                    .padding(Spacing.m)

            case .ready, .routeChanged, .interrupted:
                // No padding here: the record/studio canvases own the full
                // screen and draw their backgrounds edge to edge.
                RecordView(
                    viewModel: recording,
                    phase: $homePhase,
                    path: $homePath,
                    namespace: transition,
                    onImportFile: handleImport,
                    showLyrics: $showLyrics
                )

            case .permissionDenied:
                Group {
                    Text("StudioVocals needs microphone access to record your singing.")
                        .font(.dsBody)
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(Spacing.m)

            case .failed(let message):
                Text(message)
                    .font(.dsCallout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(Spacing.m)
            }
        }
        .task {
            _ = await audioSession.requestPermissionAndActivate()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--open-recordings") {
                homePath.append(.library)
            }
            if ProcessInfo.processInfo.arguments.contains("--open-settings") {
                homePath.append(.settings)
            }
            if ProcessInfo.processInfo.arguments.contains("--result-first"),
               let first = try? RecordingLibrary.listRecordings().first?.url {
                let rVM = ResultViewModel(originalURL: first)
                homePhase = .studio(rVM)
            }
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $showSpikeTest) {
            SpikeTestView()
        }
        .sheet(isPresented: $showProcessingTest) {
            ProcessingTestView()
        }
        #endif
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Imports a picked audio file into the library, then loads it in recorded state.
    private func handleImport(_ url: URL) {
        Task {
            if let imported = try? await Self.performImport(url) {
                let rVM = ResultViewModel(originalURL: imported)
                homePhase = .recorded(rVM)
            }
        }
    }

    @concurrent
    private static func performImport(_ url: URL) async throws -> URL {
        try RecordingLibrary.importAudio(from: url)
    }
}

#Preview {
    ContentView()
}
