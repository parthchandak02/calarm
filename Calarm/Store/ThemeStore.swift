//
//  ThemeStore.swift
//  Calarm
//

import Combine
import SwiftUI

@MainActor
final class ThemeStore: ObservableObject {
    @Published var accent: CalarmAccent {
        didSet { persist() }
    }

    @Published var appearance: CalarmAppearance {
        didSet { persist() }
    }

    /// Experimental: tint Live Activity / Dynamic Island with each event's calendar color.
    @Published var useCalendarColorInLiveActivity: Bool {
        didSet { persist() }
    }

    init() {
        if let raw = CalarmPersistence.string(forKey: CalarmPersistence.Key.themeAccent),
           let value = CalarmAccent(rawValue: raw) {
            accent = value
        } else {
            accent = .orange
        }
        if let raw = CalarmPersistence.string(forKey: CalarmPersistence.Key.themeAppearance),
           let value = CalarmAppearance(rawValue: raw) {
            appearance = value
        } else {
            appearance = .dark
        }
        if CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.useCalendarColorInLiveActivity) {
            useCalendarColorInLiveActivity = CalarmPersistence.bool(
                forKey: CalarmPersistence.Key.useCalendarColorInLiveActivity
            )
        } else {
            useCalendarColorInLiveActivity = false
        }
    }

    var themeToken: String {
        "\(appearance.rawValue)-\(accent.rawValue)-cal-\(useCalendarColorInLiveActivity)"
    }

    func theme(colorScheme: ColorScheme) -> CalarmTheme {
        CalarmTheme.resolved(accent: accent, appearance: appearance, colorScheme: colorScheme)
    }

    private func persist() {
        CalarmPersistence.setString(accent.rawValue, forKey: CalarmPersistence.Key.themeAccent)
        CalarmPersistence.setString(appearance.rawValue, forKey: CalarmPersistence.Key.themeAppearance)
        CalarmPersistence.setBool(
            useCalendarColorInLiveActivity,
            forKey: CalarmPersistence.Key.useCalendarColorInLiveActivity
        )
    }
}

private struct ThemeStoreKey: EnvironmentKey {
    static let defaultValue: ThemeStore? = nil
}

extension EnvironmentValues {
    var themeStore: ThemeStore? {
        get { self[ThemeStoreKey.self] }
        set { self[ThemeStoreKey.self] = newValue }
    }
}
