//
//  ToastManager.swift
//  HUMMI
//
//  Central manager for presenting app-wide notifications and status alerts.
//

import SwiftUI

@Observable
final class ToastManager {
    static let shared = ToastManager()
    
    var isShowing = false
    var message: String = ""
    var icon: String? = nil
    var isProcessing = false
    
    private var hideTask: Task<Void, Never>?
    
    private init() {}
    
    func show(message: String, icon: String? = nil, isProcessing: Bool = false, duration: TimeInterval = 3.0) {
        Task { @MainActor in
            self.message = message
            self.icon = icon
            self.isProcessing = isProcessing
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                self.isShowing = true
            }
            
            hideTask?.cancel()
            
            // Only auto-dismiss if it's not a continuous processing state
            if !isProcessing {
                hideTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    hide()
                }
            }
        }
    }
    
    @MainActor
    func hide() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            self.isShowing = false
        }
    }
}
