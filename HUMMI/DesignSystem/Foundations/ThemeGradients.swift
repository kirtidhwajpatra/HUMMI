import SwiftUI

public enum ThemeGradients {
    public static var livenGreen: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.65, green: 0.90, blue: 0.30),
                Color(red: 0.45, green: 0.75, blue: 0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    public static var livenAccent: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.85, blue: 0.25),
                Color(red: 0.35, green: 0.65, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
