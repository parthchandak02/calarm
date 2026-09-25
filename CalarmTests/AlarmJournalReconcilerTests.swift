//
//  AlarmJournalReconcilerTests.swift
//  CalarmTests
//

import XCTest

final class AlarmJournalReconcilerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func armed(
        _ alarmID: String,
        fire: Date,
        at: Date? = nil,
        pid: Int32 = 100
    ) -> AlarmJournalEntry {
        AlarmJournalEntry(
            event: .scheduled,
            alarmID: alarmID,
            occurrenceID: "occ-\(alarmID)",
            intendedFire: fire,
            wallClock: at ?? fire.addingTimeInterval(-3600),
            systemUptime: 10,
            processID: pid
        )
    }

    private func observed(
        _ alarmID: String,
        event: AlarmJournalEvent,
        at: Date,
        pid: Int32 = 100
    ) -> AlarmJournalEntry {
        AlarmJournalEntry(
            event: event,
            alarmID: alarmID,
            wallClock: at,
            systemUptime: 20,
            processID: pid
        )
    }

    func testAlarmObservedAtItsIntendedTimeIsOnTime() {
        let fire = base
        let entries = [
            armed("a", fire: fire),
            observed("a", event: .alerting, at: fire.addingTimeInterval(2))
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: fire.addingTimeInterval(600))

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].status, .onTime)
        XCTAssertEqual(outcomes[0].latenessSeconds, 2)
    }

    func testAlarmObservedWellAfterIntendedTimeIsLate() {
        let fire = base
        let entries = [
            armed("a", fire: fire),
            observed("a", event: .stopped, at: fire.addingTimeInterval(13 * 60))
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: fire.addingTimeInterval(3600))

        XCTAssertEqual(outcomes[0].status, .late)
        XCTAssertEqual(outcomes[0].latenessSeconds, 780)
    }

    func testAlarmPastItsTimeWithNoObservationIsUnobserved() {
        let entries = [armed("a", fire: base)]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: base.addingTimeInterval(3600))

        XCTAssertEqual(outcomes[0].status, .unobserved)
        XCTAssertNil(outcomes[0].latenessSeconds)
    }

    func testFutureAlarmIsPendingRatherThanMissed() {
        let fire = base.addingTimeInterval(3600)
        let entries = [armed("a", fire: fire)]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: base)

        XCTAssertEqual(outcomes[0].status, .pending)
    }

    func testCancelledAlarmIsNotCountedAsMissed() {
        let entries = [
            armed("a", fire: base),
            AlarmJournalEntry(
                event: .cancelled,
                alarmID: "a",
                wallClock: base.addingTimeInterval(-60),
                systemUptime: 5,
                processID: 100
            )
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: base.addingTimeInterval(3600))

        XCTAssertTrue(outcomes.isEmpty)
    }

    func testObservationBeforeTheLookbackWindowBelongsToAnEarlierArming() {
        let fire = base
        let entries = [
            armed("a", fire: fire),
            observed("a", event: .stopped, at: fire.addingTimeInterval(-600))
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: fire.addingTimeInterval(3600))

        XCTAssertEqual(outcomes[0].status, .unobserved)
    }

    func testProcessChangeBetweenArmingAndFireIsFlagged() {
        let fire = base
        let entries = [
            armed("a", fire: fire, pid: 100),
            observed("a", event: .stopped, at: fire.addingTimeInterval(5), pid: 777)
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: fire.addingTimeInterval(600))

        XCTAssertTrue(outcomes[0].processChanged)
    }

    func testRearmingAnAlarmIDUsesTheLatestIntendedTime() {
        let first = base
        let moved = base.addingTimeInterval(1800)
        let entries = [
            armed("a", fire: first, at: base.addingTimeInterval(-7200)),
            armed("a", fire: moved, at: base.addingTimeInterval(-60)),
            observed("a", event: .alerting, at: moved.addingTimeInterval(3))
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: moved.addingTimeInterval(600))

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].intendedFire, moved)
        XCTAssertEqual(outcomes[0].status, .onTime)
    }

    func testMultipleAlarmsAreReportedInIntendedFireOrder() {
        let entries = [
            armed("late", fire: base.addingTimeInterval(600)),
            armed("early", fire: base)
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: base.addingTimeInterval(7200))

        XCTAssertEqual(outcomes.map(\.alarmID), ["early", "late"])
    }

    func testSummaryCountsSettledOutcomesOnly() {
        let entries = [
            armed("ontime", fire: base),
            observed("ontime", event: .alerting, at: base.addingTimeInterval(1)),
            armed("late", fire: base),
            observed("late", event: .stopped, at: base.addingTimeInterval(900)),
            armed("missed", fire: base),
            armed("future", fire: base.addingTimeInterval(86_400))
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: base.addingTimeInterval(3600))
        let summary = AlarmJournalReconciler.summary(of: outcomes)

        XCTAssertTrue(summary.contains("settled=3"), summary)
        XCTAssertTrue(summary.contains("onTime=1"), summary)
        XCTAssertTrue(summary.contains("late=1"), summary)
        XCTAssertTrue(summary.contains("unobserved=1"), summary)
        XCTAssertTrue(summary.contains("worstLatenessSec=900"), summary)
    }

    func testRingMinutesBeforeAWindowAlarmIsEarly() {
        let fire = base
        let entries = [
            armed("a", fire: fire),
            observed("a", event: .alerting, at: fire.addingTimeInterval(-300))
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: fire.addingTimeInterval(3600))

        XCTAssertEqual(outcomes[0].status, .early)
        XCTAssertEqual(outcomes[0].latenessSeconds, -300)
    }

    func testRingBeforeTheArmingIsNotEarly() {
        let fire = base
        let entries = [
            armed("a", fire: fire, at: fire.addingTimeInterval(-200)),
            observed("a", event: .alerting, at: fire.addingTimeInterval(-300))
        ]

        let outcomes = AlarmJournalReconciler.reconcile(entries: entries, now: fire.addingTimeInterval(3600))

        XCTAssertEqual(outcomes[0].status, .unobserved)
    }
}
