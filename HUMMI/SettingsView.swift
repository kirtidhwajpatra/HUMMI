//
//  SettingsView.swift
//  HUMMI
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("exportFormat") private var exportFormat: ExportFormat = .m4a
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    
    @State private var isShowingDeleteConfirmation = false
    
    var body: some View {
        Form {
            Section {
                Picker("App Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .onChange(of: appTheme) { _ in
                    Haptics.shared.play(.light)
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Choose a theme or use the system default.")
            }
            
            Section {
                Picker("Export Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .onChange(of: exportFormat) { _ in
                    Haptics.shared.play(.light)
                }
            } header: {
                Text("Audio Export")
            } footer: {
                Text("M4A provides smaller file sizes. WAV provides uncompressed, lossless studio quality.")
            }
            
            Section {
                Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                    .onChange(of: hapticsEnabled) { _ in
                        Haptics.shared.play(.light)
                    }
            } header: {
                Text("Interactions")
            }
            
            Section {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Text("Delete All Recordings")
                }
            } header: {
                Text("Data Management")
            } footer: {
                Text("This permanently deletes all your recordings and cannot be undone.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .confirmationDialog("Delete All Recordings?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                Haptics.shared.notify(.warning)
                deleteAllRecordings()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private func deleteAllRecordings() {
        Task {
            do {
                let recordings = try RecordingLibrary.listRecordings()
                for recording in recordings {
                    try RecordingLibrary.delete(recording.url)
                }
                Haptics.shared.notify(.success)
            } catch {
                Haptics.shared.notify(.error)
                print("Failed to delete recordings: \(error)")
            }
        }
    }
}
