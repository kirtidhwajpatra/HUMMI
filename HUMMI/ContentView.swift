//
//  ContentView.swift
//  HUMMI
//
//  Created by Uday on 05/07/26.
//

import SwiftUI

/// Where the app's single navigation stack can go.
enum AppRoute: Hashable {
    case save(URL)
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
    @State private var selectedTab = 0
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

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack(path: $homePath) {
                    sessionContent
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .save(let url):
                                SaveAudioView(url: url)
                            }
                        }
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(0)
                
                NavigationStack(path: $libraryPath) {
                    RecordingsListView(path: $libraryPath) { selectedURL in
                        let rVM = ResultViewModel(originalURL: selectedURL)
                        homePhase = .studio(rVM)
                        selectedTab = 0
                        libraryPath.removeAll()
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .save(let url):
                            SaveAudioView(url: url)
                        }
                    }
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(1)
                
                NavigationStack {
                    SettingsView()
                }
                .toolbar(.hidden, for: .tabBar)
                .tag(2)
            }
            
            customTabBar
        }
        .preferredColorScheme(appTheme.colorScheme)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            Button { selectedTab = 0 } label: {
                VStack(spacing: 4) {
                    CustomMicIcon(isActive: selectedTab == 0)
                    Text("Record")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(selectedTab == 0 ? Color.red : Color.gray)
                }
                .frame(maxWidth: .infinity)
            }
            
            Button { selectedTab = 1 } label: {
                VStack(spacing: 4) {
                    CustomLibraryIcon(isActive: selectedTab == 1)
                    Text("Library")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(selectedTab == 1 ? Color.blue : Color.gray)
                }
                .frame(maxWidth: .infinity)
            }
            
            Button { selectedTab = 2 } label: {
                VStack(spacing: 4) {
                    CustomSettingsIcon(isActive: selectedTab == 2)
                    Text("Settings")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(selectedTab == 2 ? Color.purple : Color.gray)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(.systemBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: -5)
                .ignoresSafeArea()
        )
    }

    private var sessionContent: some View {
        VStack(spacing: 16) {
            switch audioSession.state {
            case .idle:
                ProgressView("Preparing microphone…")

            case .ready, .routeChanged, .interrupted:
                RecordView(
                    viewModel: recording,
                    phase: $homePhase,
                    path: $homePath,
                    namespace: transition,
                    onImportFile: handleImport
                )

            case .permissionDenied:
                Text("StudioVocals needs microphone access to record your singing.")
                    .font(.dsBody)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)

            case .failed(let message):
                Text(message)
                    .font(.dsCallout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.m)
        .task {
            _ = await audioSession.requestPermissionAndActivate()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--open-recordings") {
                selectedTab = 1
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
