//
//  ToastView.swift
//  HUMMI
//
//  A floating, glassy pill to display transient status messages.
//

import SwiftUI

struct ToastView: View {
    let message: String
    let icon: String?
    let isProcessing: Bool
    
    var body: some View {
        HStack(spacing: Spacing.s) {
            if isProcessing {
                ProgressView()
                    .tint(Brand.forest)
                    .controlSize(.small)
            } else if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.forest)
            }
            
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.ink)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background {
            Brand.ink.opacity(0.07)
        }
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}
