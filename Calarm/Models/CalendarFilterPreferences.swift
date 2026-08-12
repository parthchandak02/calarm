//
//  CalendarFilterPreferences.swift
//  Calarm
//

import Foundation

@MainActor
enum CalendarFilterPreferences {
    static var enabledCalendarIDs: Set<String> {
        get {
            let stored = CalarmPersistence.decode([String].self, forKey: CalarmPersistence.Key.enabledCalendarIDs)
            return Set(stored ?? [])
        }
        set {
            if newValue.isEmpty {
                CalarmPersistence.remove(forKey: CalarmPersistence.Key.enabledCalendarIDs)
            } else {
                CalarmPersistence.encode(Array(newValue).sorted(), forKey: CalarmPersistence.Key.enabledCalendarIDs)
            }
        }
    }

    static func isEnabled(calendarID: String) -> Bool {
        let enabled = enabledCalendarIDs
        if enabled.isEmpty { return true }
        return enabled.contains(calendarID)
    }

    static func setEnabled(_ enabled: Bool, calendarID: String, allCalendarIDs: [String]) {
        var ids = enabledCalendarIDs
        if ids.isEmpty, !enabled {
            ids = Set(allCalendarIDs)
            ids.remove(calendarID)
        } else if enabled {
            ids.insert(calendarID)
            if ids.count == allCalendarIDs.count {
                ids = []
            }
        } else {
            if ids.isEmpty {
                ids = Set(allCalendarIDs)
            }
            ids.remove(calendarID)
        }
        enabledCalendarIDs = ids
    }
}
