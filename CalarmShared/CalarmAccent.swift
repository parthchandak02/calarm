//
//  CalarmAccent.swift
//  CalarmShared
//

import SwiftUI

enum CalarmAccent: String, CaseIterable, Identifiable, Codable, Sendable {
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

    static func resolved(from rawValue: String?) -> CalarmAccent {
        guard let rawValue, let accent = CalarmAccent(rawValue: rawValue) else {
            return .orange
        }
        return accent
    }
}
