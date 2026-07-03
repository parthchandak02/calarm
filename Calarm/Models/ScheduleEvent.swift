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

    /// Next upcoming fire time across all configured alarms.
    var nextAlarmDate: Date? {
        scheduledAlarms.first?.fireDate
    }

    /// Legacy helper used by list highlighting.
    var alarmDate: Date {
        nextAlarmDate ?? startDate
    }

    var isAlarmInPast: Bool {
        alarmEnabled && scheduledAlarms.isEmpty
    }

    var canScheduleAlarm: Bool {
        !scheduledAlarms.isEmpty
    }

    var alarmSummary: String {
        guard alarmEnabled else { return "Alarm off" }
        let upcoming = scheduledAlarms
        if upcoming.isEmpty { return "All alarms passed" }
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
