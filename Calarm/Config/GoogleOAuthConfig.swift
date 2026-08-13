//
//  GoogleOAuthConfig.swift
//  Calarm
//

import Foundation

enum GoogleOAuthConfig {
    private static let plistName = "GoogleService-Info"

    static var clientID: String? {
        bundledPlistString(for: "CLIENT_ID")
    }

    static var reversedClientID: String? {
        bundledPlistString(for: "REVERSED_CLIENT_ID")
    }

    static var isConfigured: Bool {
        clientID != nil && reversedClientID != nil
    }

    static let calendarReadonlyScope = "https://www.googleapis.com/auth/calendar.readonly"

    private static func bundledPlistString(for key: String) -> String? {
        guard
            let url = Bundle.main.url(forResource: plistName, withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let value = plist[key] as? String,
            !value.isEmpty,
            !value.hasPrefix("REPLACE_")
        else {
            return nil
        }
        return value
    }
}
