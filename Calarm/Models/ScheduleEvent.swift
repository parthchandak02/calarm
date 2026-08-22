//
//  ScheduleEvent.swift
//  Calarm
//

import Foundation

struct ScheduleEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let calendarTitle: String
    let source: CalendarSource
    /// EventKit calendar color (`#RRGGBB`), when available.
    let calendarColorHex: String?

    var alarmOffsets: [AlarmOffsetOption]

    var alarmEnabled: Bool {
        !alarmOffsets.isEmpty
    }

    var scheduledAlarms: [ScheduledAlarm] {
        alarmOffsets
            .map { offset in
                ScheduledAlarm(offset: offset, fireDate: offset.fireDate(for: startDate))
            }
            .filter { $0.fireDate > Date() }
            .sorted { $0.fireDate < $1.fireDate }
    }

    var isEventUpcoming: Bool {
        startDate > Date()
    }

    /// Next upcoming fire time across all configured alarms.
    /// Falls back to event start when the reminder window closed but the event has not started.
    var nextAlarmDate: Date? {
        if let fire = scheduledAlarms.first?.fireDate { return fire }
        if alarmEnabled, isEventUpcoming { return startDate }
        return nil
    }

    /// Legacy helper used by list highlighting.
    var alarmDate: Date {
        nextAlarmDate ?? startDate
    }

    /// True when the calendar event has started and no alarms remain.
    var isAlarmInPast: Bool {
        alarmEnabled && !isEventUpcoming && scheduledAlarms.isEmpty
    }

    /// Reminder fire time passed but the event has not started yet.
    var isReminderPassed: Bool {
        alarmEnabled && isEventUpcoming && scheduledAlarms.isEmpty
    }

    var canScheduleAlarm: Bool {
        alarmEnabled && isEventUpcoming && !scheduledAlarms.isEmpty
    }

    var alarmSummary: String {
        guard alarmEnabled else { return "Alarm off" }
        let upcoming = scheduledAlarms
        if upcoming.isEmpty {
            return isEventUpcoming ? "Reminder passed" : "All alarms passed"
        }
        if upcoming.count == 1 {
            return upcoming[0].offset.title
        }
        return "\(upcoming.count) alarms"
    }
}

struct DaySection: Identifiable {
    let id: String
    let title: String
    let date: Date
    let events: [ScheduleEvent]
}
