import SwiftUI

enum AppTab: Int, CaseIterable {
    case record = 0
    case library = 1
    case settings = 2
    
    var icon: String {
        switch self {
        case .record: return "waveform"
        case .library: return "folder"
        case .settings: return "gear"
        }
    }
    
    var title: String {
        switch self {
        case .record: return "Record"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }
}

struct FloatingNavBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    // Prevent the native impact if already selected
                    guard selectedTab != tab else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Brand.lime)
                                .matchedGeometryEffect(id: "activeTab", in: animation)
                        }
                        
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? Brand.forest : Brand.ink.opacity(0.6))
                    }
                    .frame(width: 64, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        }
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}
