//
//  SettingsView.swift
//  HUMMI
//
//  Settings in the brand language: white canvas, eyebrow section
//  headers, quiet ink cards with icon rows, lime only on live controls.
//

import SwiftUI

struct SettingsView: View {
    @Binding var path: [AppRoute]
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("exportFormat") private var exportFormat: ExportFormat = .m4a
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true
    @AppStorage("appTransition") private var appTransition: AppTransition = .slide

    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            customTopBar

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    section("Appearance") {
                        row(icon: "circle.lefthalf.filled", title: "Theme") {
                            Picker("", selection: $appTheme) {
                                ForEach(AppTheme.allCases) { theme in
                                    Text(theme.rawValue).tag(theme)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 220)
                        }
                        divider
                        row(icon: "arrow.left.arrow.right", title: "Transitions") {
                            Picker("", selection: $appTransition) {
                                ForEach(AppTransition.allCases) { transition in
                                    Text(transition.rawValue).tag(transition)
                                }
                            }
                            .tint(Brand.ink)
                            .fixedSize()  // keep the selected label on one line
                        }
                    } footer: {
                        Text("How screens move. Back always plays the reverse.")
                    }

                    section("Audio") {
                        row(icon: "waveform", title: "Export Format") {
                            Picker("", selection: $exportFormat) {
                                ForEach(ExportFormat.allCases) { format in
                                    // Short labels — the footer carries the detail.
                                    Text(format == .m4a ? "M4A" : "WAV").tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 160)
                        }
                    } footer: {
                        Text("M4A keeps files small. WAV is uncompressed studio quality.")
                    }

                    section("Interactions") {
                        row(icon: "hand.tap.fill", title: "Haptic Feedback") {
                            Toggle("", isOn: $hapticsEnabled)
                                .labelsHidden()
                                .tint(Brand.limeDeep)
                        }
                    }

                    section("Data") {
                        Button {
                            isShowingDeleteConfirmation = true
                        } label: {
                            row(icon: "trash", title: "Delete All Recordings") {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Brand.ink.opacity(0.3))
                            }
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        Text("Permanently deletes every recording. This cannot be undone.")
                    }

                    Text("HUMMI \(appVersion)")
                        .font(.footnote)
                        .foregroundStyle(Brand.ink.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.m)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.l)
            }
        }
        .background(Color(.systemBackground))
        .onChange(of: appTheme) { Haptics.shared.play(.light) }
        .onChange(of: appTransition) { Haptics.shared.play(.light) }
        .onChange(of: exportFormat) { Haptics.shared.play(.light) }
        .onChange(of: hapticsEnabled) { Haptics.shared.play(.light) }
        .confirmationDialog(
            "Delete all recordings?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Haptics.shared.notify(.warning)
                deleteAllRecordings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Chrome

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

            Text("SETTINGS")
                .font(.footnote.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Brand.ink.opacity(0.55))

            Spacer()

            // Invisible placeholder for symmetry.
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.xs)
        .background(Color(.systemBackground))
    }

    // MARK: - Building blocks

    /// A quiet ink card under an eyebrow header — the same surface
    /// language as the studio's filter cards.
    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View,
        @ViewBuilder footer: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Brand.ink.opacity(0.55))
                .padding(.horizontal, Spacing.xs)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Brand.ink.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Brand.ink.opacity(0.1), lineWidth: 1))

            footer()
                .font(.dsCaption)
                .foregroundStyle(Brand.ink.opacity(0.45))
                .padding(.horizontal, Spacing.xs)
        }
    }

    private func row(
        icon: String, title: String, @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.ink)
                .frame(width: 36, height: 36)
                .background(Color(.systemBackground), in: Circle())
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Brand.ink)
            Spacer(minLength: Spacing.s)
            control()
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    private var divider: some View {
        Divider()
            .overlay(Brand.ink.opacity(0.08))
            .padding(.leading, Spacing.m + 36 + Spacing.s)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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
