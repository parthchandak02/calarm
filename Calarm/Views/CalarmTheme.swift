//
//  CalarmTheme.swift
//  Calarm
//

import SwiftUI

enum CalarmAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CalarmBrand {
    static let appName = "CALarm"
}

struct CalarmTheme: Equatable {
    let isDark: Bool
    let accent: Color
    let accentMuted: Color
    let background: Color
    let surface: Color
    let surfaceStroke: Color
    let textPrimary: Color
    let textSecondary: Color
    let onAccent: Color
    let toolbarIcon: Color
    let toolbarIconBackground: Color
    let destructive: Color
    let warning: Color

    static let cornerRadius: CGFloat = 16
    static let sectionHeaderTracking: CGFloat = 1.1
    static let rowPaddingH: CGFloat = 16
    static let screenPaddingH: CGFloat = 20
    static let settingsRowHeight: CGFloat = 44
    static let settingsTabHeight: CGFloat = 40
    static let timeColumnWidth: CGFloat = 78
    static let bellTapSize: CGFloat = 44
    static let minimumTouchTarget: CGFloat = 44

    var accentSubtle: Color { accent.opacity(0.08) }
    var accentSelected: Color { accent.opacity(0.12) }

    init(accent choice: CalarmAccent, isDark: Bool) {
        self.isDark = isDark
        accent = choice.color
        accentMuted = choice.color.opacity(0.85)

        if isDark {
            background = Color(red: 0.06, green: 0.06, blue: 0.07)
            surface = Color.white.opacity(0.06)
            surfaceStroke = Color.white.opacity(0.1)
            textPrimary = Color.white
            textSecondary = Color.white.opacity(0.55)
            onAccent = Color(red: 0.06, green: 0.06, blue: 0.07)
            toolbarIcon = Color.white.opacity(0.92)
            toolbarIconBackground = Color.white.opacity(0.1)
            destructive = Color(red: 1, green: 0.35, blue: 0.35)
            warning = Color(red: 1, green: 0.65, blue: 0.2)
        } else {
            background = Color(red: 0.97, green: 0.97, blue: 0.98)
            surface = Color.black.opacity(0.05)
            surfaceStroke = Color.black.opacity(0.1)
            textPrimary = Color(red: 0.1, green: 0.1, blue: 0.12)
            textSecondary = Color.black.opacity(0.5)
            onAccent = Color.white
            toolbarIcon = Color(red: 0.12, green: 0.12, blue: 0.14)
            toolbarIconBackground = Color.black.opacity(0.06)
            destructive = Color(red: 0.86, green: 0.15, blue: 0.15)
            warning = Color(red: 0.92, green: 0.45, blue: 0.05)
        }
    }

    static func resolved(accent: CalarmAccent, appearance: CalarmAppearance, colorScheme: ColorScheme) -> CalarmTheme {
        let isDark: Bool
        switch appearance {
        case .system: isDark = colorScheme == .dark
        case .light: isDark = false
        case .dark: isDark = true
        }
        return CalarmTheme(accent: accent, isDark: isDark)
    }

    static func eventTimeString(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
    }

    var toolbarColorScheme: ColorScheme {
        isDark ? .dark : .light
    }
}

private struct CalarmThemeKey: EnvironmentKey {
    static let defaultValue = CalarmTheme(accent: .orange, isDark: true)
}

extension EnvironmentValues {
    var calarmTheme: CalarmTheme {
        get { self[CalarmThemeKey.self] }
        set { self[CalarmThemeKey.self] = newValue }
    }
}
