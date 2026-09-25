//
//  CalarmPersistence.swift
//  Calarm
//
//  UserDefaults-backed storage for alarm + theme preferences.
//  Data in UserDefaults.standard survives app updates; it is removed only if
//  the user deletes the app or clears app data.
//

import Foundation

enum CalarmPersistence {
    /// Bump when migration steps are added.
    static let currentSchemaVersion = 3

    enum Key {
        static let storageSchemaVersion = "calarm.storage.schemaVersion"
        static let themeAccent = "calarm.theme.accent"
        static let activityLog = "calarm.activityLog"
        static let themeAppearance = "calarm.theme.appearance"
        static let defaultAlarmOffset = "calarm.defaultAlarmOffset"
        static let defaultSnoozeMinutes = "calarm.defaultSnoozeMinutes"
        static let eventOverrides = "calarm.eventOverrides"
        static let legacyDefaultOffsetMinutes = "calarm.defaultOffsetMinutes"
        static let occurrenceMetadataMigrationDone = "calarm.migration.occurrenceMetadata"
        /// Legacy allow-list, migrated into `disabledCalendarIDs` then removed.
        static let enabledCalendarIDs = "calarm.enabledCalendarIDs"
        static let disabledCalendarIDs = "calarm.disabledCalendarIDs"
        /// When true, Live Activity / Dynamic Island tint follows the EventKit calendar color.
        static let useCalendarColorInLiveActivity = "calarm.liveActivity.useCalendarColor"
        /// Intended ring time of each countdown-mode alarm, keyed by alarm UUID. AlarmKit
        /// keeps no fire date for an alarm without a schedule.
        static let countdownTargets = "calarm.alarm.countdownTargets"
        /// Title each alarm was scheduled with, keyed by alarm UUID. AlarmKit does not expose
        /// an alarm's attributes, and a grouped alarm's title changes with its members.
        static let alarmTitles = "calarm.alarm.titles"
        /// Settings → Alarms → Vibrate instead of ringing.
        static let vibrateInsteadOfRinging = "calarm.alarm.vibrateInsteadOfRinging"
        /// Set by `CalarmFocusFilter` while a Focus asks for vibration.
        static let focusVibrate = "calarm.alarm.focusVibrate"
        /// Settings → Alarms → Island. Minutes before the ring the Live Activity appears; 0 is
        /// Always. Absent means `LiveActivityLead.defaultLead`.
        static let liveActivityLeadMinutes = "calarm.liveActivity.leadMinutes"
        /// When each snoozed alarm re-rings, keyed by alarm UUID. Set by `SnoozeAlarmIntent`;
        /// AlarmKit does not say when a snoozed countdown ends.
        static let snoozedUntil = "calarm.alarm.snoozedUntil"
        /// The fire date each alarm UUID last rang for, so a ring that came early is not
        /// re-armed to ring again at the same fire date.
        static let rangFireDates = "calarm.alarm.rangFireDates"
    }

    /// Standard app preferences — persisted across updates for the same bundle ID.
    static var defaults: UserDefaults { .standard }

    /// Run once at launch before reading preference stores.
    static func migrateIfNeeded() {
        let storedVersion = defaults.integer(forKey: Key.storageSchemaVersion)
        guard storedVersion < currentSchemaVersion else { return }

        if storedVersion < 2 {
            migrateLegacyDefaultOffsetMinutes()
        }

        defaults.set(currentSchemaVersion, forKey: Key.storageSchemaVersion)
    }

    static func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    static func setString(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func integer(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }

    static func setInteger(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    static func objectExists(forKey key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }

    static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    static func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    static func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    static func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    private static func migrateLegacyDefaultOffsetMinutes() {
        guard
            defaults.string(forKey: Key.defaultAlarmOffset) == nil,
            defaults.object(forKey: Key.legacyDefaultOffsetMinutes) != nil
        else { return }

        let minutes = defaults.integer(forKey: Key.legacyDefaultOffsetMinutes)
        let migrated = AlarmOffsetOption.nearest(toMinutes: minutes).rawValue
        defaults.set(migrated, forKey: Key.defaultAlarmOffset)
    }
}

extension LiveActivityLead {
    static var persisted: LiveActivityLead {
        guard CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.liveActivityLeadMinutes) else { return defaultLead }
        return LiveActivityLead(rawValue: CalarmPersistence.integer(forKey: CalarmPersistence.Key.liveActivityLeadMinutes)) ?? defaultLead
    }
}
