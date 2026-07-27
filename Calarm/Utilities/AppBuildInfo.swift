//
//  AppBuildInfo.swift
//  Calarm
//

import Foundation

/// Reads version metadata from the app bundle (Info.plist / Xcode build settings).
enum AppBuildInfo {
    static let developerName = "Parth Chandak"
    static let copyrightHolder = "Parth Chandak"

    static var appName: String {
        let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return display ?? name ?? "CALarm"
    }

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Raw `CFBundleVersion` from the bundle (Apple build number).
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }

    /// Human-readable deploy stamp for Settings (e.g. `2026.07.19 · 22:04`).
    static var formattedBuildStamp: String {
        Self.formatBuildNumber(buildNumber)
    }

    static var copyrightYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    static func formatBuildNumber(_ raw: String) -> String {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              parts[0].count == 8, parts[0].allSatisfy(\.isNumber),
              parts[1].count == 4, parts[1].allSatisfy(\.isNumber) else {
            return raw
        }

        let date = parts[0]
        let time = parts[1]
        let year = date.prefix(4)
        let month = date.dropFirst(4).prefix(2)
        let day = date.dropFirst(6).prefix(2)
        let hour = time.prefix(2)
        let minute = time.suffix(2)
        return "\(year).\(month).\(day) · \(hour):\(minute)"
    }
}
