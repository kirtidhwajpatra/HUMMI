//
//  ProStore.swift
//  HUMMI
//

import Foundation
import Observation

/// Tracks the Pro entitlement. No StoreKit yet — this is the flag the
/// paywall gates read; `isPro` is persisted so a (future) purchase or the
/// debug unlock sticks across launches.
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    /// Free exports are capped at this duration; longer takes are Pro.
    static let freeMaxDurationSeconds: TimeInterval = 60

    private let defaultsKey = "isPro"

    var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: defaultsKey) }
    }

    private init() {
        isPro = UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// A take of `duration` may be exported for free only when short enough.
    func canExportForFree(duration: TimeInterval) -> Bool {
        duration <= Self.freeMaxDurationSeconds
    }
}
