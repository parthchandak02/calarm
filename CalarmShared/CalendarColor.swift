//
//  CalendarColor.swift
//  CalarmShared
//

import CoreGraphics
import SwiftUI

/// EventKit calendar colors encoded for Live Activity / AlarmKit tinting.
enum CalendarColor {
    /// `#RRGGBB` from an EventKit calendar `CGColor`, or nil when unavailable.
    static func hexString(from cgColor: CGColor?) -> String? {
        guard let components = cgColor?.components, components.count >= 3 else { return nil }
        let red = clampedByte(components[0])
        let green = clampedByte(components[1])
        let blue = clampedByte(components[2])
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func color(fromHex hex: String?) -> Color? {
        guard let hex, let rgb = parseHex(hex) else { return nil }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func clampedByte(_ value: CGFloat) -> Int {
        Int(round(min(max(value, 0), 1) * 255))
    }

    private static func parseHex(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        guard normalized.count == 6, let value = UInt32(normalized, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return (red, green, blue)
    }
}
