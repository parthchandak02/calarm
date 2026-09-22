//
//  CalendarFilterPreferences.swift
//  Calarm
//

import Foundation

/// Stores the calendars the user switched **off**.
///
/// An allow-list was the previous shape and it failed closed: any calendar that
/// appeared after the list was written — a newly subscribed calendar, or an
/// existing one whose EventKit identifier changed on an account resync — was
/// absent from the list and so was silently excluded. Missing a meeting is this
/// app's worst outcome, so the default for anything unrecognised is "read it".
@MainActor
enum CalendarFilterPreferences {
    static var disabledCalendarIDs: Set<String> {
        get {
            let stored = CalarmPersistence.decode([String].self, forKey: CalarmPersistence.Key.disabledCalendarIDs)
            return Set(stored ?? [])
        }
        set {
            if newValue.isEmpty {
                CalarmPersistence.remove(forKey: CalarmPersistence.Key.disabledCalendarIDs)
            } else {
                CalarmPersistence.encode(Array(newValue).sorted(), forKey: CalarmPersistence.Key.disabledCalendarIDs)
            }
        }
    }

    static func isEnabled(calendarID: String) -> Bool {
        !disabledCalendarIDs.contains(calendarID)
    }

    static func setEnabled(_ enabled: Bool, calendarID: String) {
        var ids = disabledCalendarIDs
        if enabled {
            ids.remove(calendarID)
        } else {
            ids.insert(calendarID)
        }
        disabledCalendarIDs = ids
    }

    /// Converts a stored allow-list into the equivalent deny-list.
    ///
    /// Runs only with a real calendar list in hand: an empty `allCalendarIDs`
    /// means EventKit has not answered yet, and inverting against nothing would
    /// mark every remembered choice as disabled.
    static func migrateAllowListIfNeeded(allCalendarIDs: [String]) {
        guard !allCalendarIDs.isEmpty else { return }
        guard CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.enabledCalendarIDs) else { return }

        let allowed = Set(CalarmPersistence.decode([String].self, forKey: CalarmPersistence.Key.enabledCalendarIDs) ?? [])
        if !allowed.isEmpty {
            disabledCalendarIDs = Set(allCalendarIDs).subtracting(allowed)
        }
        CalarmPersistence.remove(forKey: CalarmPersistence.Key.enabledCalendarIDs)
    }
}
