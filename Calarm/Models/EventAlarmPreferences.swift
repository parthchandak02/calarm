//
//  EventAlarmPreferences.swift
//  Calarm
//

import Foundation

struct EventOverride: Codable, Equatable {
    var alarmOffsets: [String]?
    /// Legacy single-offset storage (migrated on read).
    var legacyOffsetMinutes: Int?
    var legacyEnabled: Bool?
}

@MainActor
final class EventAlarmPreferences {
    init() {}

    var defaultAlarmOffset: AlarmOffsetOption {
        get {
            if let raw = CalarmPersistence.string(forKey: CalarmPersistence.Key.defaultAlarmOffset),
               let value = AlarmOffsetOption(rawValue: raw) {
                return value
            }
            if CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.legacyDefaultOffsetMinutes) {
                return AlarmOffsetOption.nearest(
                    toMinutes: CalarmPersistence.integer(forKey: CalarmPersistence.Key.legacyDefaultOffsetMinutes)
                )
            }
            return .tenMinutes
        }
        set {
            CalarmPersistence.setString(newValue.rawValue, forKey: CalarmPersistence.Key.defaultAlarmOffset)
        }
    }

    var defaultSnooze: SnoozeDurationOption {
        get {
            let minutes = CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
                ? CalarmPersistence.integer(forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
                : SnoozeDurationOption.fiveMinutes.rawValue
            return SnoozeDurationOption(rawValue: minutes) ?? .fiveMinutes
        }
        set {
            CalarmPersistence.setInteger(newValue.rawValue, forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
        }
    }

    func alarmOffsets(for eventID: String) -> [AlarmOffsetOption] {
        let override = overrides(for: eventID)
        if let rawValues = override.alarmOffsets {
            return rawValues.compactMap(AlarmOffsetOption.init(rawValue:))
        }
        if override.legacyEnabled == true, let minutes = override.legacyOffsetMinutes {
            return [AlarmOffsetOption.nearest(toMinutes: minutes)]
        }
        if override.legacyEnabled == true {
            return [defaultAlarmOffset]
        }
        return []
    }

    func setAlarmOffsets(_ offsets: [AlarmOffsetOption], for eventID: String) {
        var override = overrides(for: eventID)
        override.legacyEnabled = nil
        override.legacyOffsetMinutes = nil
        let unique = offsets.reduce(into: [AlarmOffsetOption]()) { result, offset in
            if !result.contains(offset) {
                result.append(offset)
            }
        }
        override.alarmOffsets = unique.isEmpty ? nil : unique.map(\.rawValue)
        save(override, for: eventID)
    }

    func addAlarmOffset(_ offset: AlarmOffsetOption, for eventID: String) {
        var current = alarmOffsets(for: eventID)
        guard !current.contains(offset) else { return }
        current.append(offset)
        setAlarmOffsets(current, for: eventID)
    }

    func removeAlarmOffset(_ offset: AlarmOffsetOption, for eventID: String) {
        let current = alarmOffsets(for: eventID).filter { $0 != offset }
        setAlarmOffsets(current, for: eventID)
    }

    func removeOverride(for eventID: String) {
        var all = allOverrides()
        all.removeValue(forKey: eventID)
        persist(all)
    }

    private func overrides(for eventID: String) -> EventOverride {
        allOverrides()[eventID] ?? EventOverride()
    }

    private func save(_ override: EventOverride, for eventID: String) {
        var all = allOverrides()
        let isEmpty = override.alarmOffsets == nil
            && override.legacyEnabled == nil
            && override.legacyOffsetMinutes == nil
        if isEmpty {
            all.removeValue(forKey: eventID)
        } else {
            all[eventID] = override
        }
        persist(all)
    }

    private func allOverrides() -> [String: EventOverride] {
        CalarmPersistence.decode([String: EventOverride].self, forKey: CalarmPersistence.Key.eventOverrides) ?? [:]
    }

    private func persist(_ overrides: [String: EventOverride]) {
        if overrides.isEmpty {
            CalarmPersistence.remove(forKey: CalarmPersistence.Key.eventOverrides)
        } else {
            CalarmPersistence.encode(overrides, forKey: CalarmPersistence.Key.eventOverrides)
        }
    }
}
