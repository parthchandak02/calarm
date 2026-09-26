//
//  DepartureBoard.swift
//  Calarm
//

import Foundation

/// Text for the schedule's departure-board layout: the next-alarm countdown, each row's
/// short alarm label, and day headers.
nonisolated enum DepartureBoard {
    static let countdownUnits = ["DAYS", "HRS", "MIN", "SEC"]

    /// Flight-board countdown groups, `DD HH MM SS`, each two digits. Days cap at 99.
    static func countdownGroups(until fireDate: Date, now: Date) -> [String] {
        let seconds = max(0, Int(fireDate.timeIntervalSince(now)))
        let days = min(99, seconds / 86_400)
        return [days, seconds % 86_400 / 3_600, seconds % 3_600 / 60, seconds % 60]
            .map { String(format: "%02d", $0) }
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

    static func rowLabel(for event: ScheduleEvent, tooSoon: Bool, missed: Bool = false) -> String {
        if missed { return "missed" }
        if tooSoon { return "too soon" }
        guard event.alarmEnabled else { return "off" }
        if event.isAlarmInPast { return "past" }
        if event.isReminderPassed { return "passed" }
        return event.scheduledAlarms.map { shortOffset($0.offset) }.joined(separator: " ")
    }

    struct DayParts: Equatable {
        let relative: String?
        let tiles: [String]
    }

    /// The day header split for flap tiles: "TODAY" + [SAT, 26], or [MON, 28, SEP] further out.
    static func dayParts(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> DayParts {
        func part(_ style: Date.FormatStyle) -> String {
            var style = style.locale(locale)
            style.timeZone = calendar.timeZone
            return date.formatted(style).uppercased(with: locale)
        }
        let weekday = part(Date.FormatStyle().weekday(.abbreviated))
        let day = part(Date.FormatStyle().day())
        if calendar.isDate(date, inSameDayAs: now) {
            return DayParts(relative: "TODAY", tiles: [weekday, day])
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return DayParts(relative: "TOMORROW", tiles: [weekday, day])
        }
        return DayParts(relative: nil, tiles: [weekday, day, part(Date.FormatStyle().month(.abbreviated))])
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
