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
    static let currentSchemaVersion = 2

    enum Key {
        static let storageSchemaVersion = "calarm.storage.schemaVersion"
        static let themeAccent = "calarm.theme.accent"
        static let themeAppearance = "calarm.theme.appearance"
        static let defaultAlarmOffset = "calarm.defaultAlarmOffset"
        static let defaultSnoozeMinutes = "calarm.defaultSnoozeMinutes"
        static let eventOverrides = "calarm.eventOverrides"
        static let legacyDefaultOffsetMinutes = "calarm.defaultOffsetMinutes"
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
