import SwiftUI

struct CustomMicIcon: View {
    var isActive: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                .frame(width: 48, height: 48)
            
            VStack(spacing: 2) {
                Capsule()
                    .fill(isActive ? Color.red : Color.gray)
                    .frame(width: 10, height: 16)
                
                ZStack(alignment: .top) {
                    Capsule()
                        .stroke(isActive ? Color.red : Color.gray, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 16, height: 12)
                    
                    Rectangle()
                        .fill(isActive ? Color.red : Color.gray)
                        .frame(width: 2.5, height: 5)
                        .offset(y: 12)
                }
            }
            .offset(y: 1)
        }
    }
}

struct CustomLibraryIcon: View {
    var isActive: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(isActive ? Color.blue : Color.gray).frame(width: 4, height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(isActive ? Color.blue : Color.gray).frame(width: 14, height: 4)
                }
                HStack(spacing: 4) {
                    Circle().fill(isActive ? Color.blue : Color.gray).frame(width: 4, height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(isActive ? Color.blue : Color.gray).frame(width: 14, height: 4)
                }
                HStack(spacing: 4) {
                    Circle().fill(isActive ? Color.blue : Color.gray).frame(width: 4, height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(isActive ? Color.blue : Color.gray).frame(width: 14, height: 4)
                }
            }
        }
    }
}

struct CustomSettingsIcon: View {
    var isActive: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Color.purple.opacity(0.15) : Color.gray.opacity(0.1))
                .frame(width: 48, height: 48)
            
            ZStack {
                // Gear teeth
                ForEach(0..<6) { i in
                    Capsule()
                        .fill(isActive ? Color.purple : Color.gray)
                        .frame(width: 6, height: 20)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                
                // Gear body
                Circle()
                    .fill(isActive ? Color.purple : Color.gray)
                    .frame(width: 14, height: 14)
                
                // Gear center hole
                Circle()
                    .fill(isActive ? Color.purple.opacity(0.15) : Color(.systemBackground))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
