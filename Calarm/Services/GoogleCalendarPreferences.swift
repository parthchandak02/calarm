//
//  GoogleCalendarPreferences.swift
//  Calarm
//

import Foundation

final class GoogleCalendarPreferences {
    init() {}
    private enum Key {
        static let connectedEmail = "calarm.google.connectedEmail"
        /// Legacy allow-list, migrated into `disabledCalendarIDs` then removed.
        static let enabledCalendarIDs = "calarm.google.enabledCalendarIDs"
        static let disabledCalendarIDs = "calarm.google.disabledCalendarIDs"
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

    /// The Google calendars the user switched **off**. A deny-list for the same reason as
    /// `CalendarFilterPreferences`: an allow-list silently hid every calendar subscribed
    /// after it was written, and a missed meeting is this app's worst outcome.
    var disabledCalendarIDs: Set<String> {
        get { Set(CalarmPersistence.decode([String].self, forKey: Key.disabledCalendarIDs) ?? []) }
        set {
            if newValue.isEmpty {
                CalarmPersistence.remove(forKey: Key.disabledCalendarIDs)
            } else {
                CalarmPersistence.encode(Array(newValue).sorted(), forKey: Key.disabledCalendarIDs)
            }
        }
    }

    func isCalendarEnabled(_ calendarID: String) -> Bool {
        !disabledCalendarIDs.contains(calendarID)
    }

    func setCalendarEnabled(_ calendarID: String, enabled: Bool) {
        var disabled = disabledCalendarIDs
        if enabled {
            disabled.remove(calendarID)
        } else {
            disabled.insert(calendarID)
        }
        disabledCalendarIDs = disabled
    }

    /// Inverts a stored allow-list against a real calendar list. Skipped while the list is
    /// empty, since inverting against nothing would disable every remembered choice.
    func migrateAllowListIfNeeded(allCalendarIDs: [String]) {
        guard !allCalendarIDs.isEmpty, CalarmPersistence.objectExists(forKey: Key.enabledCalendarIDs) else { return }
        let allowed = Set(CalarmPersistence.decode([String].self, forKey: Key.enabledCalendarIDs) ?? [])
        if !allowed.isEmpty {
            disabledCalendarIDs = Set(allCalendarIDs).subtracting(allowed)
        }
        CalarmPersistence.remove(forKey: Key.enabledCalendarIDs)
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
        disabledCalendarIDs = []
        CalarmPersistence.remove(forKey: Key.enabledCalendarIDs)
        clearSyncTokens()
    }

    private func syncTokens() -> [String: String] {
        CalarmPersistence.decode([String: String].self, forKey: Key.syncTokens) ?? [:]
    }
}
