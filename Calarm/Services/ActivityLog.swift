//
//  ActivityLog.swift
//  Calarm
//

import Foundation

/// What CALarm did, in words, for Settings → Status: rescheduled, synced, rang, snoozed,
/// dismissed, Focus changes, failures. On this phone only, kept for seven days.
///
/// Separate from `AlarmJournalStore`, which records machine facts for timing
/// reconciliation and has no titles.
enum ActivityLog {
    nonisolated enum Kind: String, Codable, Sendable {
        case resched
        case sync
        case rang
        case snoozed
        case dismissed
        case focus
        case test
        case fail

        var label: String { rawValue.uppercased() }
    }

    nonisolated struct Entry: Codable, Equatable, Sendable {
        let date: Date
        let kind: Kind
        let text: String
    }

    nonisolated static let retention: TimeInterval = 7 * 86_400
    nonisolated static let entryLimit = 300
    /// A repeat of the newest entry this soon after it replaces it instead of stacking,
    /// so a reschedule on every foreground does not bury everything else.
    nonisolated static let collapseWindow: TimeInterval = 10 * 60

    nonisolated static func appending(_ entry: Entry, to entries: [Entry]) -> [Entry] {
        var result = entries.filter { entry.date.timeIntervalSince($0.date) < retention }
        if let last = result.last,
           last.kind == entry.kind,
           last.text == entry.text,
           entry.date.timeIntervalSince(last.date) < collapseWindow {
            result.removeLast()
        }
        result.append(entry)
        if result.count > entryLimit {
            result.removeFirst(result.count - entryLimit)
        }
        return result
    }

    nonisolated struct Day: Equatable {
        let title: String
        let entries: [Entry]
    }

    /// Newest first, grouped under TODAY, YESTERDAY, or a date.
    nonisolated static func days(_ entries: [Entry], now: Date, calendar: Calendar = .current) -> [Day] {
        let recent = entries.filter { now.timeIntervalSince($0.date) < retention }.sorted { $0.date > $1.date }
        var days: [Day] = []
        for entry in recent {
            let title: String
            if calendar.isDate(entry.date, inSameDayAs: now) {
                title = "Today"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                      calendar.isDate(entry.date, inSameDayAs: yesterday) {
                title = "Yesterday"
            } else {
                title = entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            if days.last?.title == title {
                days[days.count - 1] = Day(title: title, entries: days[days.count - 1].entries + [entry])
            } else {
                days.append(Day(title: title, entries: [entry]))
            }
        }
        return days
    }

    static func record(_ kind: Kind, _ text: String, at date: Date = Date()) {
        let entries = appending(Entry(date: date, kind: kind, text: text), to: load())
        CalarmPersistence.encode(entries, forKey: CalarmPersistence.Key.activityLog)
    }

    static func load() -> [Entry] {
        CalarmPersistence.decode([Entry].self, forKey: CalarmPersistence.Key.activityLog) ?? []
    }
}
