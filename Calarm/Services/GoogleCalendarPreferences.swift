//
//  GoogleCalendarPreferences.swift
//  Calarm
//

import Foundation

final class GoogleCalendarPreferences {
    init() {}
    private enum Key {
        static let connectedEmail = "calarm.google.connectedEmail"
        static let enabledCalendarIDs = "calarm.google.enabledCalendarIDs"
        static let lastSyncCheck = "calarm.google.lastSyncCheck"
        static let syncTokens = "calarm.google.syncTokens"
    }

    var connectedEmail: String? {
        get { CalarmPersistence.string(forKey: Key.connectedEmail) }
        set { CalarmPersistence.setString(newValue, forKey: Key.connectedEmail) }
    }

    var isConnected: Bool { connectedEmail != nil }

    var lastSyncCheck: Date? {
        get {
            let raw = CalarmPersistence.string(forKey: Key.lastSyncCheck)
            guard let raw, let interval = TimeInterval(raw) else { return nil }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let newValue {
                CalarmPersistence.setString(String(newValue.timeIntervalSince1970), forKey: Key.lastSyncCheck)
            } else {
                CalarmPersistence.remove(forKey: Key.lastSyncCheck)
            }
        }
    }

    var enabledCalendarIDs: Set<String> {
        get {
            if let decoded = CalarmPersistence.decode([String].self, forKey: Key.enabledCalendarIDs) {
                return Set(decoded)
            }
            return []
        }
        set {
            CalarmPersistence.encode(Array(newValue).sorted(), forKey: Key.enabledCalendarIDs)
        }
    }

    func isCalendarEnabled(_ calendarID: String) -> Bool {
        let enabled = enabledCalendarIDs
        if enabled.isEmpty { return true }
        return enabled.contains(calendarID)
    }

    func setCalendarEnabled(_ calendarID: String, enabled: Bool, allCalendarIDs: [String]) {
        var enabledSet = enabledCalendarIDs
        if enabledSet.isEmpty {
            enabledSet = Set(allCalendarIDs)
        }
        if enabled {
            enabledSet.insert(calendarID)
        } else {
            enabledSet.remove(calendarID)
        }
        enabledCalendarIDs = enabledSet
    }

    func syncToken(for calendarID: String) -> String? {
        syncTokens()[calendarID]
    }

    func setSyncToken(_ token: String?, for calendarID: String) {
        var tokens = syncTokens()
        if let token {
            tokens[calendarID] = token
        } else {
            tokens.removeValue(forKey: calendarID)
        }
        CalarmPersistence.encode(tokens, forKey: Key.syncTokens)
    }

    func clearSyncTokens() {
        CalarmPersistence.remove(forKey: Key.syncTokens)
    }

    func disconnect() {
        connectedEmail = nil
        lastSyncCheck = nil
        enabledCalendarIDs = []
        clearSyncTokens()
    }

    private func syncTokens() -> [String: String] {
        CalarmPersistence.decode([String: String].self, forKey: Key.syncTokens) ?? [:]
    }
}
