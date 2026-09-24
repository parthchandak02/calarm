//
//  ScheduleEventSourcePolicy.swift
//  Calarm
//

import Foundation

/// Pure rules about where schedule data comes from and how the sources combine.
///
/// Everything here is `nonisolated` on purpose. This target sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated `static func` is
/// MainActor-isolated and cannot be called from a `map` closure or a background context
/// without a warning that becomes an error under the Swift 6 language mode. These are
/// functions over value types with no state, so isolating them buys nothing.
enum ScheduleEventSourcePolicy {
    nonisolated static func hasEventSource(eventKitFullAccess: Bool, googleConnected: Bool) -> Bool {
        eventKitFullAccess || googleConnected
    }

    /// Combines the two calendar sources into one schedule, dropping duplicates.
    ///
    /// Pure and sorted, so the merge rules are testable without EventKit, AlarmKit or a
    /// network. That matters more than it sounds: this function decides how many alarms
    /// a meeting gets, and it used to live inline in `ScheduleStore.reload()` where
    /// nothing could reach it.
    ///
    /// **Google wins every collision.** It is the fresher source when connected, and it
    /// carries fields EventKit does not.
    ///
    /// Two independent dedup passes, because one is not enough:
    ///
    /// 1. **By source identity**, upstream of here — `CalendarService.isGoogleMirroredCalendar`
    ///    drops EventKit calendars whose account looks Google-shaped.
    /// 2. **By title and start time**, here. Pass 1 string-matches
    ///    `calendar.source.title`, which the user can rename. A Google account added to
    ///    iOS as a generic CalDAV entry titled "Work" does not match it, so the same
    ///    meeting arrives through both paths with two different identifiers, becomes two
    ///    `ScheduleEvent`s with two different `stableAlarmID`s, and rings twice with two
    ///    independent bell toggles. This pass is what stops that.
    ///
    /// Start times are compared at minute resolution. The two sources disagree by
    /// sub-second amounts for the same meeting, so exact `Date` equality would let every
    /// duplicate through.
    nonisolated static func merge(eventKit: [ScheduleEvent], google: [ScheduleEvent]) -> [ScheduleEvent] {
        var seen = Set(google.map(collisionKey))
        var merged = google

        for event in eventKit {
            let key = collisionKey(for: event)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(event)
        }

        return merged.sorted { $0.startDate < $1.startDate }
    }

    /// Drops busy-only placeholders that start in the same minute as a titled event: the
    /// same meeting seen through a free/busy share. Only busy-only events are ever dropped,
    /// and a busy block that would ring stays unless its titled twin rings too, so the list
    /// never hides the one event responsible for an alarm.
    nonisolated static func hidingBusyTwins(_ events: [ScheduleEvent]) -> [ScheduleEvent] {
        let titled = events.filter { !$0.isBusyOnly }
        let titledMinutes = Set(titled.map(startMinute))
        let ringingTitledMinutes = Set(titled.filter(\.alarmEnabled).map(startMinute))
        return events.filter { event in
            guard event.isBusyOnly else { return true }
            let minute = startMinute(of: event)
            let twinRings = ringingTitledMinutes.contains(minute)
            let hideable = event.alarmEnabled ? twinRings : titledMinutes.contains(minute)
            return !hideable
        }
    }

    nonisolated private static func startMinute(of event: ScheduleEvent) -> Int {
        Int(event.startDate.timeIntervalSince1970 / 60)
    }

    /// Identity of a *meeting*, as opposed to identity of a calendar row.
    ///
    /// Case and interior whitespace are normalised because the same event reaches the
    /// two sources with cosmetically different titles.
    nonisolated static func collisionKey(for event: ScheduleEvent) -> String {
        let title = event.title
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let minute = startMinute(of: event)
        return "\(minute)|\(title)"
    }
}
