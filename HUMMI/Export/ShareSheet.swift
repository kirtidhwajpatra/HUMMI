//
//  ShareSheet.swift
//  HUMMI
//

import SwiftUI
import UIKit

/// Presents a UIActivityViewController for a generated file. Used instead
/// of `ShareLink` because export files are produced asynchronously.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so `.sheet(item:)` can drive the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
