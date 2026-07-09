//
//  HUMMIApp.swift
//  HUMMI
//
//  Created by Uday on 05/07/26.
//

import SwiftUI

@main
struct HUMMIApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .tint(.accentColor)
                .preferredColorScheme(.dark)
        }
    }
}
