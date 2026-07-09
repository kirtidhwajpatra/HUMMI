//
//  GlassToolbar.swift
//  HUMMI
//
//  Floating bottom bar on ultra-thin material with a hairline top
//  separator. Safe-area aware when placed via `.safeAreaInset(edge:.bottom)`.
//

import SwiftUI

struct GlassToolbar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Rectangle().fill(.ultraThinMaterial)
                    Divider()
                }
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

#if DEBUG
private struct ToolbarGallery: View {
    var body: some View {
        VStack {
            Spacer()
            GlassToolbar {
                HStack(spacing: Spacing.m) {
                    Label("Save Audio", systemImage: "square.and.arrow.up")
                    Spacer()
                    Label("Share Video", systemImage: "film")
                }
                .font(.dsCallout)
            }
        }
        .background(Color(.systemBackground))
        .tint(.accentColor)
    }
}

#Preview("Light") { ToolbarGallery().preferredColorScheme(.light) }
#Preview("Dark") { ToolbarGallery().preferredColorScheme(.dark) }
#Preview("A11y2 · RTL") {
    ToolbarGallery().dynamicTypeSize(.accessibility2).environment(\.layoutDirection, .rightToLeft)
}
#endif
