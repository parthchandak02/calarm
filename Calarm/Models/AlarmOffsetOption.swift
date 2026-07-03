//
//  AlarmOffsetOption.swift
//  Calarm
//

import Foundation

/// Fixed alarm lead times supported by Calarm.
enum AlarmOffsetOption: String, Codable, CaseIterable, Identifiable, Hashable {
    case atEventTime
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes
    case sixtyMinutes
    case oneDayBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atEventTime: "At event time"
        case .oneMinute: "1 minute before"
        case .fiveMinutes: "5 minutes before"
        case .tenMinutes: "10 minutes before"
        case .thirtyMinutes: "30 minutes before"
        case .sixtyMinutes: "60 minutes before"
        case .oneDayBefore: "1 day before (24 hours)"
        }
    }

    /// Seconds before the event start when this alarm should fire.
    var leadTime: TimeInterval {
        switch self {
        case .atEventTime: 0
        case .oneMinute: 60
        case .fiveMinutes: 5 * 60
        case .tenMinutes: 10 * 60
        case .thirtyMinutes: 30 * 60
        case .sixtyMinutes: 60 * 60
        case .oneDayBefore: 24 * 60 * 60
        }
    }

    func fireDate(for eventStart: Date) -> Date {
        eventStart.addingTimeInterval(-leadTime)
    }

    func summaryLabel(relativeTo eventStart: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: fireDate(for: eventStart))
        return "\(title) · \(time)"
    }

    /// Migrate legacy minute values from older app versions.
    static func nearest(toMinutes minutes: Int) -> AlarmOffsetOption {
        let candidates: [(AlarmOffsetOption, Int)] = [
            (.atEventTime, 0),
            (.oneMinute, 1),
            (.fiveMinutes, 5),
            (.tenMinutes, 10),
            (.thirtyMinutes, 30),
            (.sixtyMinutes, 60),
            (.oneDayBefore, 24 * 60)
        ]
        return candidates.min(by: {
            abs($0.1 - minutes) < abs($1.1 - minutes)
        })?.0 ?? .tenMinutes
    }
}

enum SnoozeDurationOption: Int, CaseIterable, Identifiable, Codable {
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

struct ScheduledAlarm: Identifiable, Equatable {
    let offset: AlarmOffsetOption
    let fireDate: Date

    var id: String { offset.rawValue }
}
