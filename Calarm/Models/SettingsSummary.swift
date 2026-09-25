//
//  SettingsSummary.swift
//  Calarm
//

import Foundation

/// Text for the departure-board Settings: the root's one-line summaries, the Alarms
/// sentence, and the Status verdict.
nonisolated enum SettingsSummary {
    static func offsetTile(_ offset: AlarmOffsetOption) -> String {
        switch offset {
        case .noAlarm: "OFF"
        case .atEventTime: "0"
        case .oneMinute: "1"
        case .fiveMinutes: "5"
        case .tenMinutes: "10"
        case .thirtyMinutes: "30"
        case .sixtyMinutes: "1H"
        case .oneDayBefore: "1D"
        }
    }

    static func snoozeTile(_ snooze: SnoozeDurationOption) -> String {
        "\(snooze.rawValue)"
    }

    static func alarmsLine(offset: AlarmOffsetOption, snooze: SnoozeDurationOption, vibrates: Bool) -> String {
        let ring = offset == .noAlarm ? "off" : DepartureBoard.shortOffset(offset)
        return "\(ring) · \(snooze.rawValue)m · \(vibrates ? "vibrate" : "ring")"
    }

    static func alarmsSentence(offset: AlarmOffsetOption, snooze: SnoozeDurationOption, vibrates: Bool) -> String {
        var parts: [String] = []
        switch offset {
        case .noAlarm: parts.append("New events start with no alarm.")
        case .atEventTime: parts.append("New events ring when they start.")
        default: parts.append("New events ring \(offset.title).")
        }
        parts.append("Snooze waits \(snooze.title).")
        if vibrates {
            parts.append("Alarms vibrate, then ring if not dismissed within a minute.")
        }
        return parts.joined(separator: " ")
    }

    static func calendarsLine(enabled: Int, total: Int, googleConnected: Bool) -> String {
        let count = total == 0 ? "none" : "\(enabled) of \(total)"
        return googleConnected ? "\(count) · Google" : count
    }
}

/// Answers "will my alarms ring?" for Settings → Status. Only states the owner can act on
/// count as problems; everything else is a passing check.
nonisolated enum StatusVerdict {
    enum Fix: Equatable {
        case openSystemSettings
        case retrySync
        case runTestAlarm
    }

    struct Problem: Equatable {
        let title: String
        let detail: String
        let fix: Fix
        /// True when this problem alone means no alarm can ring.
        let blocksAlarms: Bool
    }

    struct Input {
        var alarmsDenied: Bool
        var hasEventSource: Bool
        var googleSyncError: String?
        var scheduleFailureCount: Int
        var firstScheduleFailure: String?
        var timingLateSeconds: Int?
    }

    static func problems(for input: Input) -> [Problem] {
        var problems: [Problem] = []
        if input.alarmsDenied {
            problems.append(Problem(
                title: "Alarms are off for CALarm",
                detail: "iOS Settings → CALarm → Alarms",
                fix: .openSystemSettings,
                blocksAlarms: true
            ))
        }
        if !input.hasEventSource {
            problems.append(Problem(
                title: "No calendar connected",
                detail: "Allow calendar access or connect Google",
                fix: .openSystemSettings,
                blocksAlarms: true
            ))
        }
        if let error = input.googleSyncError {
            problems.append(Problem(title: "Google sync failed", detail: error, fix: .retrySync, blocksAlarms: false))
        }
        if input.scheduleFailureCount > 0 {
            let title = input.scheduleFailureCount == 1
                ? "An alarm couldn’t be scheduled"
                : "\(input.scheduleFailureCount) alarms couldn’t be scheduled"
            problems.append(Problem(title: title, detail: input.firstScheduleFailure ?? "", fix: .retrySync, blocksAlarms: false))
        }
        if let late = input.timingLateSeconds {
            problems.append(Problem(
                title: "Test alarm rang late",
                detail: "Rang at \(late)s instead of 8s",
                fix: .runTestAlarm,
                blocksAlarms: false
            ))
        }
        return problems
    }

    static func headline(for problems: [Problem]) -> String {
        switch problems.count {
        case 0: "ALL GOOD"
        case 1: "1 PROBLEM"
        default: "\(problems.count) PROBLEMS"
        }
    }

    static func subline(for problems: [Problem], hasUpcomingAlarm: Bool) -> String {
        if problems.contains(where: \.blocksAlarms) { return "Alarms will not ring until this is fixed." }
        if !problems.isEmpty { return "Alarms will still ring." }
        return hasUpcomingAlarm ? "Alarms will ring." : "Nothing is set to ring yet."
    }
}
