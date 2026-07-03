//
//  CalarmTheme.swift
//  Calarm
//

import SwiftUI

enum CalarmAccent: String, CaseIterable, Identifiable, Codable {
    case orange
    case amber
    case coral
    case rose
    case violet
    case sky
    case mint
    case lime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orange: "Orange"
        case .amber: "Amber"
        case .coral: "Coral"
        case .rose: "Rose"
        case .violet: "Violet"
        case .sky: "Sky"
        case .mint: "Mint"
        case .lime: "Lime"
        }
    }

    var color: Color {
        switch self {
        case .orange: Color(red: 1.0, green: 0.58, blue: 0.0)
        case .amber: Color(red: 1.0, green: 0.75, blue: 0.2)
        case .coral: Color(red: 1.0, green: 0.45, blue: 0.42)
        case .rose: Color(red: 1.0, green: 0.38, blue: 0.55)
        case .violet: Color(red: 0.62, green: 0.45, blue: 1.0)
        case .sky: Color(red: 0.35, green: 0.72, blue: 1.0)
        case .mint: Color(red: 0.35, green: 0.88, blue: 0.75)
        case .lime: Color(red: 0.72, green: 0.92, blue: 0.35)
        }
    }
}

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

    static let cornerRadius: CGFloat = 16
    static let sectionHeaderTracking: CGFloat = 1.1
    static let rowPaddingH: CGFloat = 16
    static let timeColumnWidth: CGFloat = 78
    static let bellTapSize: CGFloat = 44

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
        } else {
            background = Color(red: 0.97, green: 0.97, blue: 0.98)
            surface = Color.black.opacity(0.05)
            surfaceStroke = Color.black.opacity(0.1)
            textPrimary = Color(red: 0.1, green: 0.1, blue: 0.12)
            textSecondary = Color.black.opacity(0.5)
            onAccent = Color.white
            toolbarIcon = Color(red: 0.12, green: 0.12, blue: 0.14)
            toolbarIconBackground = Color.black.opacity(0.06)
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
