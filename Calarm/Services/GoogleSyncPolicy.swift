//
//  GoogleSyncPolicy.swift
//  Calarm
//

import Foundation

nonisolated enum GoogleSyncPolicy {
    /// How long the cached window may stand in for a fresh one. The incremental check only
    /// reports edits, so without this an event rolling into the horizon never appears while
    /// the process stays alive.
    static let windowMaxAge: TimeInterval = 60 * 60

    /// Started-but-not-ended events stay, as EventKit's overlap predicate keeps them. Dropping
    /// a meeting at its start cancelled its snoozed or ringing alarm.
    static func isInWindow(startDate: Date, endDate: Date, now: Date, horizonEnd: Date) -> Bool {
        endDate > now && startDate <= horizonEnd
    }

    static func isWindowStale(lastWindowFetch: Date?, now: Date) -> Bool {
        guard let lastWindowFetch else { return true }
        return now.timeIntervalSince(lastWindowFetch) >= windowMaxAge || now < lastWindowFetch
    }
}
