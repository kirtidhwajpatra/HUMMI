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
        ScrollView {
            VStack(spacing: Spacing.xl) {
                StudioArtwork(compact: true)
                    .accessibilityLabel("HUMMI studio")
                    .padding(.vertical, Spacing.m)

                settingsCard(title: "Appearance", footer: "Choose a theme or use the system default.") {
                    Picker("App Theme", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .onChange(of: appTheme) { _ in
                        Haptics.shared.play(.light)
                    }
                }
                
                settingsCard(title: "Audio Export", footer: "M4A provides smaller file sizes. WAV provides uncompressed, lossless studio quality.") {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .onChange(of: exportFormat) { _ in
                        Haptics.shared.play(.light)
                    }
                }
                
                settingsCard(title: "Interactions") {
                    Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                        .onChange(of: hapticsEnabled) { _ in
                            Haptics.shared.play(.light)
                        }
                }
                
                settingsCard(title: "Data Management", footer: "This permanently deletes all your recordings and cannot be undone.") {
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Text("Delete All Recordings")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.xl)
            // Extra bottom padding to clear the new floating nav bar
            .padding(.bottom, 100)
        }
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

    @ViewBuilder
    private func settingsCard<Content: View>(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title.uppercased())
                .font(.dsSectionHeader)
                .foregroundStyle(.primary)
                .padding(.horizontal, Spacing.xs)
            
            VStack(spacing: 0) {
                content()
                    .padding(Spacing.l)
            }
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
            }
            
            if let footer {
                Text(footer)
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.top, Spacing.xxs)
            }
        }
    }
}
