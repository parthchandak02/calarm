//
//  AlarmJournal.swift
//  CalarmShared
//
//  A durable record of what alarms were asked to do and what they actually did.
//
//  Three facts force this design:
//    - `AlarmManager.alarmUpdates` is in-process, so nothing observes a fire on a phone
//      where the app has been dead since midnight. Reconciliation happens on next launch.
//    - `try? AlarmManager.shared.alarms` returns [] both when AlarmKit is broken and when
//      nothing is scheduled, so the app cannot use it as a source of truth about intent.
//    - AlarmKit silently deletes spent one-shot alarms, so a missing alarm is normal.
//
//  Entries therefore carry `systemUptime` and `processID` alongside wall clock: a process
//  change between schedule and fire means the app was killed, and uptime survives a user
//  changing the system clock (which is itself a documented AlarmKit failure trigger).
//

import Foundation

nonisolated enum AlarmJournalEvent: String, Codable, Sendable {
    case scheduled
    case alerting
    case stopped
    case snoozed
    case cancelled
}

nonisolated struct AlarmJournalEntry: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let event: AlarmJournalEvent
    let alarmID: String
    let occurrenceID: String?
    let intendedFire: Date?
    let wallClock: Date
    let systemUptime: TimeInterval
    let processID: Int32

    init(
        event: AlarmJournalEvent,
        alarmID: String,
        occurrenceID: String? = nil,
        intendedFire: Date? = nil,
        wallClock: Date = Date(),
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.schemaVersion = Self.schemaVersion
        self.event = event
        self.alarmID = alarmID
        self.occurrenceID = occurrenceID
        self.intendedFire = intendedFire
        self.wallClock = wallClock
        self.systemUptime = systemUptime
        self.processID = processID
    }
}

nonisolated enum AlarmFireStatus: String, Codable, Equatable, Sendable {
    case pending
    case onTime
    case late
    /// Rang well before its intended time: a window alarm on a device that follows Apple's
    /// documented `.fixed` + pre-alert timing.
    case early
    case unobserved
}

nonisolated struct AlarmFireOutcome: Equatable, Sendable {
    let alarmID: String
    let occurrenceID: String?
    let intendedFire: Date
    let observedAt: Date?
    let status: AlarmFireStatus
    let processChanged: Bool

    var latenessSeconds: TimeInterval? {
        guard let observedAt else { return nil }
        return observedAt.timeIntervalSince(intendedFire)
    }
}

/// The measurement nobody else computes: intended fire time versus what was observed.
nonisolated enum AlarmJournalReconciler {
    /// Observations this far before the intended fire belong to an earlier arming of the
    /// same alarm ID, not to this one.
    static let observationLookback: TimeInterval = 120

    /// How early a ring can still be this arming's: the longest Live Activity lead plus a
    /// minute. Only an `.alerting` observation after the arming counts, since a stop or
    /// snooze that far ahead is more likely an earlier arming's.
    static let earlyLookback: TimeInterval = 11 * 60

    static func reconcile(
        entries: [AlarmJournalEntry],
        now: Date,
        tolerance: TimeInterval = 60
    ) -> [AlarmFireOutcome] {
        var byAlarm: [String: [AlarmJournalEntry]] = [:]
        for entry in entries {
            byAlarm[entry.alarmID, default: []].append(entry)
        }

        return byAlarm.compactMap { alarmID, group -> AlarmFireOutcome? in
            let sorted = group.sorted { $0.wallClock < $1.wallClock }

            guard let armed = sorted.last(where: { $0.event == .scheduled && $0.intendedFire != nil }),
                  let intendedFire = armed.intendedFire else { return nil }

            if sorted.contains(where: { $0.event == .cancelled && $0.wallClock > armed.wallClock }) {
                return nil
            }

            let observation = sorted.first { entry in
                guard entry.event == .alerting || entry.event == .stopped || entry.event == .snoozed
                else { return false }
                return entry.wallClock >= intendedFire.addingTimeInterval(-observationLookback)
            }

            let earlyObservation = observation == nil ? sorted.first { entry in
                entry.event == .alerting
                    && entry.wallClock > armed.wallClock
                    && entry.wallClock >= intendedFire.addingTimeInterval(-earlyLookback)
                    && entry.wallClock < intendedFire.addingTimeInterval(-observationLookback)
            } : nil

            let status: AlarmFireStatus
            if earlyObservation != nil {
                status = .early
            } else if let observation {
                let lateness = observation.wallClock.timeIntervalSince(intendedFire)
                status = lateness > tolerance ? .late : .onTime
            } else if now < intendedFire.addingTimeInterval(tolerance) {
                status = .pending
            } else {
                status = .unobserved
            }

            return AlarmFireOutcome(
                alarmID: alarmID,
                occurrenceID: armed.occurrenceID,
                intendedFire: intendedFire,
                observedAt: (observation ?? earlyObservation)?.wallClock,
                status: status,
                processChanged: (observation ?? earlyObservation).map { $0.processID != armed.processID } ?? false
            )
        }
        .sorted { $0.intendedFire < $1.intendedFire }
    }

    static func summary(of outcomes: [AlarmFireOutcome]) -> String {
        let settled = outcomes.filter { $0.status != .pending }
        guard !settled.isEmpty else { return "no settled alarms yet" }

        let late = settled.filter { $0.status == .late }
        let early = settled.filter { $0.status == .early }
        let unobserved = settled.filter { $0.status == .unobserved }
        let worst = late.compactMap(\.latenessSeconds).max() ?? 0

        return "settled=\(settled.count) onTime=\(settled.count - late.count - early.count - unobserved.count)"
            + " late=\(late.count) early=\(early.count) unobserved=\(unobserved.count)"
            + " worstLatenessSec=\(Int(worst))"
    }
}
