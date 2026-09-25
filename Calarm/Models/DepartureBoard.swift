//
//  DepartureBoard.swift
//  Calarm
//

import Foundation

/// Text for the schedule's departure-board layout: the next-alarm countdown, each row's
/// short alarm label, and day headers.
nonisolated enum DepartureBoard {
    struct Countdown: Equatable {
        let digits: String
        let unit: String
    }

    static func countdown(until fireDate: Date, now: Date) -> Countdown {
        let seconds = max(0, Int(fireDate.timeIntervalSince(now)))
        if seconds < 3_600 {
            return Countdown(digits: String(format: "%02d:%02d", seconds / 60, seconds % 60), unit: "MIN")
        }
        if seconds < 100 * 3_600 {
            return Countdown(digits: String(format: "%d:%02d", seconds / 3_600, seconds % 3_600 / 60), unit: "HRS")
        }
        let days = seconds / 86_400
        return Countdown(digits: "\(days)", unit: days == 1 ? "DAY" : "DAYS")
    }

    static func shortOffset(_ offset: AlarmOffsetOption) -> String {
        switch offset {
        case .noAlarm: "off"
        case .atEventTime: "at start"
        case .oneMinute: "−1m"
        case .fiveMinutes: "−5m"
        case .tenMinutes: "−10m"
        case .thirtyMinutes: "−30m"
        case .sixtyMinutes: "−1h"
        case .oneDayBefore: "−1d"
        }
    }

    static func rowLabel(for event: ScheduleEvent, tooSoon: Bool) -> String {
        if tooSoon { return "too soon" }
        guard event.alarmEnabled else { return "off" }
        if event.isAlarmInPast { return "past" }
        if event.isReminderPassed { return "passed" }
        return event.scheduledAlarms.map { shortOffset($0.offset) }.joined(separator: " ")
    }

    static func dayTitle(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let weekdayAndDay = date.formatted(.dateTime.weekday(.abbreviated).day().locale(locale))
        if calendar.isDate(date, inSameDayAs: now) {
            return "TODAY · \(weekdayAndDay)".uppercased(with: locale)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "TOMORROW · \(weekdayAndDay)".uppercased(with: locale)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
            .uppercased(with: locale)
    }
}
