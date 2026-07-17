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
    
    @State private var audioSession = AudioSessionManager()
    @State private var recording = RecordingViewModel()
    @State private var selectedTab: AppTab = .record
    @State private var homePath: [AppRoute] = []
    @State private var libraryPath: [AppRoute] = []
    @State private var homePhase: HomePhase = .idle
    @Namespace private var transition
    #if DEBUG
    @State private var showSpikeTest =
        ProcessInfo.processInfo.arguments.contains("--spike-autorun")
    @State private var showProcessingTest =
        ProcessInfo.processInfo.arguments.contains(ProcessingTestViewModel.autorunArgument)
        || ProcessInfo.processInfo.arguments.contains(ProcessingTestViewModel.profileAutorunArgument)
    #endif

    @State private var isNavBarVisible = true
    @State private var navBarHideTask: Task<Void, Never>?
    @State private var showLyrics: Bool = false

    private func userDidInteract() {
        if showLyrics {
            isNavBarVisible = false
            return
        }
        if !isNavBarVisible {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isNavBarVisible = true
            }
        }
        navBarHideTask?.cancel()
        navBarHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isNavBarVisible = false
                }
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content Area
            Group {
                switch selectedTab {
                case .record:
                    NavigationStack(path: $homePath) {
                        sessionContent
                            .navigationDestination(for: AppRoute.self) { route in
                                switch route {
                                case .save(let rVM):
                                    SaveAudioView(viewModel: rVM)
                                }
                            }
                    }
                case .library:
                    NavigationStack(path: $libraryPath) {
                        RecordingsListView(path: $libraryPath) { selectedURL in
                            let rVM = ResultViewModel(originalURL: selectedURL)
                            homePhase = .studio(rVM)
                            selectedTab = .record
                            libraryPath.removeAll()
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .save(let rVM):
                                SaveAudioView(viewModel: rVM)
                            }
                        }
                    }
                case .settings:
                    NavigationStack {
                        SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom Floating Navigation Bar
            if isNavBarVisible && !showLyrics {
                FloatingNavBar(selectedTab: $selectedTab)
                    .padding(.bottom, 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            userDidInteract()
        })
        .onAppear {
            userDidInteract()
        }
        .onChange(of: showLyrics) { _, show in
            if show {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isNavBarVisible = false
                }
            } else {
                userDidInteract()
            }
        }
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
                selectedTab = .library
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

