//
//  EventAlarmPreferences.swift
//  Calarm
//

import EventKit
import Foundation

struct EventOverride: Codable, Equatable {
    /// `nil` = no per-event override (use default-for-new-events policy).
    /// `[]` = user explicitly turned alarms off for this event.
    var alarmOffsets: [String]?
    /// Offsets preserved when the user pauses alarms from the schedule list.
    var pausedAlarmOffsets: [String]?
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
            return .noAlarm
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

    /// Copy legacy bare `eventIdentifier` overrides to each in-window occurrence, then remove legacy keys.
    func migrateLegacyKeys(for ekEvents: [EKEvent]) {
        var all = allOverrides()
        let legacyKeys = all.keys.filter { EventOccurrenceID.isLegacyBareIdentifier($0) }
        guard !legacyKeys.isEmpty else { return }

        for legacyKey in legacyKeys {
            guard let override = all[legacyKey] else { continue }
            let matching = ekEvents.filter { $0.eventIdentifier == legacyKey }
            for ekEvent in matching {
                guard let eventIdentifier = ekEvent.eventIdentifier else { continue }
                let occurrence = EventOccurrenceID(eventIdentifier: eventIdentifier, startDate: ekEvent.startDate)
                if all[occurrence.rawValue] == nil {
                    all[occurrence.rawValue] = override
                }
            }
            all.removeValue(forKey: legacyKey)
        }
        persist(all)
    }

    func alarmOffsets(for occurrenceID: String) -> [AlarmOffsetOption] {
        let override = overrides(for: occurrenceID)
        let hasStoredOverride = allOverrides()[occurrenceID] != nil

        if let rawValues = override.alarmOffsets {
            return rawValues.compactMap(AlarmOffsetOption.init(rawValue:))
        }
        if override.legacyEnabled == true, let minutes = override.legacyOffsetMinutes {
            return [AlarmOffsetOption.nearest(toMinutes: minutes)]
        }
        if override.legacyEnabled == true {
            return defaultOffsetsForNewEvents
        }
        if hasStoredOverride {
            return []
        }
        return defaultOffsetsForNewEvents
    }

    private var defaultOffsetsForNewEvents: [AlarmOffsetOption] {
        if defaultAlarmOffset == .noAlarm {
            return []
        }
        return [defaultAlarmOffset]
    }

    func setAlarmOffsets(_ offsets: [AlarmOffsetOption], for occurrenceID: String) {
        var override = overrides(for: occurrenceID)
        override.legacyEnabled = nil
        override.legacyOffsetMinutes = nil
        let unique = offsets.reduce(into: [AlarmOffsetOption]()) { result, offset in
            if offset.isSchedulable, !result.contains(offset) {
                result.append(offset)
            }
        }
        override.alarmOffsets = unique.map(\.rawValue)
        save(override, for: occurrenceID)
    }

    func addAlarmOffset(_ offset: AlarmOffsetOption, for occurrenceID: String) {
        var current = alarmOffsets(for: occurrenceID)
        guard !current.contains(offset) else { return }
        current.append(offset)
        setAlarmOffsets(current, for: occurrenceID)
    }

    func removeAlarmOffset(_ offset: AlarmOffsetOption, for occurrenceID: String) {
        let current = alarmOffsets(for: occurrenceID).filter { $0 != offset }
        setAlarmOffsets(current, for: occurrenceID)
    }

    func hasPausedAlarms(for occurrenceID: String) -> Bool {
        guard let paused = allOverrides()[occurrenceID]?.pausedAlarmOffsets else { return false }
        return !paused.isEmpty
    }

    /// Pause alarms but preserve configured offsets for a later resume.
    func pauseAlarms(for occurrenceID: String) {
        let current = alarmOffsets(for: occurrenceID)
        var override = overrides(for: occurrenceID)
        override.legacyEnabled = nil
        override.legacyOffsetMinutes = nil
        override.pausedAlarmOffsets = current.map(\.rawValue)
        override.alarmOffsets = []
        save(override, for: occurrenceID)
    }

    /// Restore alarms from paused offsets, or apply the default enabling offset.
    func resumeAlarms(for occurrenceID: String, defaultOffset: AlarmOffsetOption) {
        var override = overrides(for: occurrenceID)
        override.legacyEnabled = nil
        override.legacyOffsetMinutes = nil
        if let paused = override.pausedAlarmOffsets, !paused.isEmpty {
            override.alarmOffsets = paused
            override.pausedAlarmOffsets = nil
        } else {
            override.alarmOffsets = [defaultOffset.enablingFallback.rawValue]
            override.pausedAlarmOffsets = nil
        }
        save(override, for: occurrenceID)
    }

    func removeOverride(for occurrenceID: String) {
        var all = allOverrides()
        all.removeValue(forKey: occurrenceID)
        persist(all)
    }

    private func overrides(for occurrenceID: String) -> EventOverride {
        allOverrides()[occurrenceID] ?? EventOverride()
    }

    private func save(_ override: EventOverride, for occurrenceID: String) {
        var all = allOverrides()
        let isEmpty = override.alarmOffsets == nil
            && override.pausedAlarmOffsets == nil
            && override.legacyEnabled == nil
            && override.legacyOffsetMinutes == nil
        if isEmpty {
            all.removeValue(forKey: occurrenceID)
        } else {
            all[occurrenceID] = override
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
