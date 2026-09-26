//
//  CalendarSelectionPolicy.swift
//  Calarm
//

import Foundation

enum CalendarBulkAction: Equatable {
    case turnAllOn
    case turnAllOff

    nonisolated var title: String {
        switch self {
        case .turnAllOn: "Turn all on"
        case .turnAllOff: "Turn all off"
        }
    }

    nonisolated var enables: Bool { self == .turnAllOn }
}

enum CalendarSelectionPolicy {
    /// Any calendar off offers "Turn all on" first: restoring coverage is the safer default.
    nonisolated static func bulkAction(enabledStates: [Bool]) -> CalendarBulkAction? {
        guard !enabledStates.isEmpty else { return nil }
        return enabledStates.allSatisfy { $0 } ? .turnAllOff : .turnAllOn
    }

    /// Deny-list semantics: only calendars known now are switched off, so one subscribed
    /// later still shows up.
    nonisolated static func disabledIDs(allCalendarIDs: [String], enabled: Bool) -> Set<String> {
        enabled ? [] : Set(allCalendarIDs)
    }

    /// EventKit returns meetings already in progress and Google does not, so both are cut
    /// to events that have not started yet to keep the counts comparable.
    nonisolated static func upcomingCount(
        in events: [ScheduleEvent],
        source: CalendarSource,
        calendarTitle: String,
        now: Date
    ) -> Int {
        events.filter { $0.source == source && $0.calendarTitle == calendarTitle && $0.startDate >= now }.count
    }

    nonisolated static func countsFootnote(fetchDays: Int) -> String {
        "All-day events are always skipped. Numbers are upcoming events in the next \(fetchDays) \(fetchDays == 1 ? "day" : "days")."
    }
}
