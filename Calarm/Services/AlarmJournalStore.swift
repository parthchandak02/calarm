//
//  AlarmJournalStore.swift
//  Calarm
//
//  Writes journal entries to two sinks, deliberately.
//
//  `os.Logger` is the ground truth: it is process-agnostic, survives the app being killed,
//  and can be pulled off the device afterwards without the app cooperating. UserDefaults is
//  the convenience copy so the app can show its own history without a sysdiagnose.
//

import Foundation
import os

nonisolated enum AlarmJournalStore {
    static let entriesKey = "alarmJournalEntries"
    static let entryLimit = 500
    static let testProbeKey = "calarm.alarm.testAlarmProbe"

    private static let log = Logger(subsystem: "com.calarmapp.calarm", category: "alarmjournal")
    private static let lock = NSLock()

    static func record(_ entry: AlarmJournalEntry) {
        logEntry(entry)

        lock.lock()
        defer { lock.unlock() }

        var entries = load()
        entries.append(entry)
        if entries.count > entryLimit {
            entries.removeFirst(entries.count - entryLimit)
        }
        save(entries)
    }

    static func record(
        _ event: AlarmJournalEvent,
        alarmID: String,
        occurrenceID: String? = nil,
        intendedFire: Date? = nil
    ) {
        record(
            AlarmJournalEntry(
                event: event,
                alarmID: alarmID,
                occurrenceID: occurrenceID,
                intendedFire: intendedFire
            )
        )
    }

    /// `alarmUpdates` re-emits for the whole duration of a ring, so only the first
    /// observation is kept. The reconciler uses the earliest one anyway.
    static func recordAlertingOnce(alarmID: String) {
        lock.lock()
        var entries = load()
        let alreadySeen = entries.last { $0.alarmID == alarmID }?.event == .alerting
        if alreadySeen {
            lock.unlock()
            return
        }
        let entry = AlarmJournalEntry(event: .alerting, alarmID: alarmID)
        entries.append(entry)
        if entries.count > entryLimit {
            entries.removeFirst(entries.count - entryLimit)
        }
        save(entries)
        lock.unlock()

        logEntry(entry)
    }

    static func load() -> [AlarmJournalEntry] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey) else { return [] }
        return (try? JSONDecoder().decode([AlarmJournalEntry].self, from: data)) ?? []
    }

    static func outcomes(now: Date = Date()) -> [AlarmFireOutcome] {
        AlarmJournalReconciler.reconcile(entries: load(), now: now)
    }

    /// Called once per launch. `alarmUpdates` dies with the process, so this is the only
    /// place a fire that happened while the app was dead can be classified.
    static func reconcileOnLaunch(now: Date = Date()) {
        let results = outcomes(now: now)
        log.info("reconcile \(AlarmJournalReconciler.summary(of: results), privacy: .public)")

        for outcome in results where outcome.status == .late || outcome.status == .unobserved {
            let lateness = outcome.latenessSeconds.map { String(Int($0)) } ?? "n/a"
            log.warning(
                """
                \(outcome.status.rawValue, privacy: .public) \
                alarm=\(outcome.alarmID, privacy: .public) \
                intended=\(outcome.intendedFire.timeIntervalSince1970, privacy: .public) \
                latenessSec=\(lateness, privacy: .public) \
                processChanged=\(outcome.processChanged, privacy: .public)
                """
            )
        }
    }

    private nonisolated struct TestProbe: Codable {
        let alarmID: String
        let scheduledAt: Date
        let preAlert: TimeInterval
    }

    static func recordTestProbe(alarmID: String, scheduledAt: Date, preAlert: TimeInterval) {
        let probe = TestProbe(alarmID: alarmID, scheduledAt: scheduledAt, preAlert: preAlert)
        guard let data = try? JSONEncoder().encode(probe) else { return }
        UserDefaults.standard.set(data, forKey: testProbeKey)
    }

    /// Nil until a test alarm has been scheduled. The ring is only observed while the app is
    /// running, so it stays `.pending` if the app was closed when it rang.
    static func testProbeVerdict() -> AlarmTimingProbe.Verdict? {
        guard let data = UserDefaults.standard.data(forKey: testProbeKey),
              let probe = try? JSONDecoder().decode(TestProbe.self, from: data) else { return nil }
        let observed = load().first { entry in
            entry.alarmID == probe.alarmID && entry.event == .alerting && entry.wallClock >= probe.scheduledAt
        }
        return AlarmTimingProbe.verdict(
            scheduledAt: probe.scheduledAt,
            preAlert: probe.preAlert,
            observedAt: observed?.wallClock
        )
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: entriesKey)
    }

    private static func save(_ entries: [AlarmJournalEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
    }

    private static func logEntry(_ entry: AlarmJournalEntry) {
        let intended = entry.intendedFire.map { String($0.timeIntervalSince1970) } ?? "nil"
        log.info(
            """
            \(entry.event.rawValue, privacy: .public) \
            alarm=\(entry.alarmID, privacy: .public) \
            intended=\(intended, privacy: .public) \
            wall=\(entry.wallClock.timeIntervalSince1970, privacy: .public) \
            uptime=\(Int(entry.systemUptime), privacy: .public) \
            pid=\(entry.processID, privacy: .public)
            """
        )
    }
}
