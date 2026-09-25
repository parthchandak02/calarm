import XCTest

final class AlarmSchedulingHelpersTests: XCTestCase {
    func testStableAlarmIDIsDeterministic() {
        let a = AlarmSchedulingHelpers.stableAlarmID(occurrenceID: "evt_1", offsetRawValue: "tenMinutes")
        let b = AlarmSchedulingHelpers.stableAlarmID(occurrenceID: "evt_1", offsetRawValue: "tenMinutes")
        XCTAssertEqual(a, b)
    }

    func testSchedulingFingerprintIncludesLiveActivityKey() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let instances = [
            (occurrenceID: "a", offsetRawValue: "tenMinutes", fireDate: base)
        ]
        let first = AlarmSchedulingHelpers.schedulingFingerprint(
            instances: instances,
            nextLiveActivityKey: "a.tenMinutes",
            snoozeRawValue: "540",
            accentRawValue: "coral",
            liveActivityLeadMinutes: 5
        )
        let second = AlarmSchedulingHelpers.schedulingFingerprint(
            instances: instances,
            nextLiveActivityKey: nil,
            snoozeRawValue: "540",
            accentRawValue: "coral",
            liveActivityLeadMinutes: 5
        )
        XCTAssertNotEqual(first, second)
    }

    func testSchedulingFingerprintIncludesAccent() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let instances = [
            (occurrenceID: "a", offsetRawValue: "tenMinutes", fireDate: base)
        ]
        let coral = AlarmSchedulingHelpers.schedulingFingerprint(
            instances: instances,
            nextLiveActivityKey: "a.tenMinutes",
            snoozeRawValue: "540",
            accentRawValue: "coral",
            liveActivityLeadMinutes: 5
        )
        let violet = AlarmSchedulingHelpers.schedulingFingerprint(
            instances: instances,
            nextLiveActivityKey: "a.tenMinutes",
            snoozeRawValue: "540",
            accentRawValue: "violet",
            liveActivityLeadMinutes: 5
        )
        XCTAssertNotEqual(coral, violet)
    }

    func testSchedulingFingerprintIncludesLiveActivityLead() {
        let instances = [(occurrenceID: "a", offsetRawValue: "tenMinutes", fireDate: Date(timeIntervalSince1970: 1_800_000_000))]
        let fingerprint = { (lead: Int) in
            AlarmSchedulingHelpers.schedulingFingerprint(
                instances: instances,
                nextLiveActivityKey: "a.tenMinutes",
                snoozeRawValue: "540",
                accentRawValue: "coral",
                liveActivityLeadMinutes: lead
            )
        }
        XCTAssertNotEqual(fingerprint(5), fingerprint(0))
        XCTAssertTrue(fingerprint(10).contains("lead:10"))
    }

    func testSnoozeHoldWithoutRecordWithinSnoozePlusGrace() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(AlarmSchedulingHelpers.isSnoozeHold(isCountingDown: true, fireDate: fire, now: fire.addingTimeInterval(30), snoozeSeconds: 300))
        XCTAssertFalse(AlarmSchedulingHelpers.isSnoozeHold(isCountingDown: true, fireDate: fire, now: fire.addingTimeInterval(361), snoozeSeconds: 300))
    }

    func testSecondSnoozeIsHeldByItsOwnEnd() {
        // Ring 9:00, snooze at 9:00:30, re-ring 9:05:30, snooze again at 9:06:15.
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        let snoozedUntil = fire.addingTimeInterval(375 + 300)
        let now = fire.addingTimeInterval(400)
        XCTAssertTrue(AlarmSchedulingHelpers.isSnoozeHold(isCountingDown: true, fireDate: fire, snoozedUntil: snoozedUntil, now: now, snoozeSeconds: 300))
        XCTAssertFalse(AlarmSchedulingHelpers.isSnoozeHold(isCountingDown: true, fireDate: fire, snoozedUntil: snoozedUntil, now: snoozedUntil.addingTimeInterval(61), snoozeSeconds: 300))
        XCTAssertEqual(
            AlarmSchedulingHelpers.snoozeHoldDeadline(fireDate: fire, snoozedUntil: snoozedUntil, snoozeSeconds: 300),
            snoozedUntil.addingTimeInterval(60)
        )
    }

    func testSnoozeHoldNeedsAPastFireAndACountdown() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(AlarmSchedulingHelpers.isSnoozeHold(isCountingDown: true, fireDate: fire, now: fire.addingTimeInterval(-30), snoozeSeconds: 300))
        XCTAssertFalse(AlarmSchedulingHelpers.isSnoozeHold(isCountingDown: false, fireDate: fire, now: fire.addingTimeInterval(30), snoozeSeconds: 300))
        XCTAssertFalse(AlarmSchedulingHelpers.isSnoozeHold(isCountingDown: true, fireDate: nil, now: fire, snoozeSeconds: 300))
    }

    func testAlertingDeadlineFollowsTheRecordedSnooze() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        let snoozedUntil = fire.addingTimeInterval(900)
        XCTAssertEqual(AlarmSchedulingHelpers.alertingDeadline(fireDate: fire, snoozedUntil: snoozedUntil, snoozeSeconds: 300), snoozedUntil.addingTimeInterval(300))
        XCTAssertEqual(AlarmSchedulingHelpers.alertingDeadline(fireDate: fire, snoozedUntil: nil, snoozeSeconds: 300), fire.addingTimeInterval(600))
    }

    func testShortEventDoesNotEndItsSnooze() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(AlarmSchedulingHelpers.shouldEndWithEvent(endDate: end, holdUntil: end.addingTimeInterval(120), now: end.addingTimeInterval(60)))
        XCTAssertTrue(AlarmSchedulingHelpers.shouldEndWithEvent(endDate: end, holdUntil: end.addingTimeInterval(120), now: end.addingTimeInterval(120)))
        XCTAssertTrue(AlarmSchedulingHelpers.shouldEndWithEvent(endDate: end, holdUntil: nil, now: end))
        XCTAssertFalse(AlarmSchedulingHelpers.shouldEndWithEvent(endDate: end, holdUntil: end.addingTimeInterval(-60), now: end.addingTimeInterval(-1)))
    }

    func testAlreadyRangMatchesTheSameFireDateOnly() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(AlarmSchedulingHelpers.alreadyRang(fireDate: fire, rangFireDate: fire.addingTimeInterval(0.5)))
        XCTAssertFalse(AlarmSchedulingHelpers.alreadyRang(fireDate: fire, rangFireDate: fire.addingTimeInterval(-300)))
        XCTAssertFalse(AlarmSchedulingHelpers.alreadyRang(fireDate: fire, rangFireDate: nil))
    }

    func testAlertingGraceOutlastsOneSnooze() {
        XCTAssertEqual(AlarmSchedulingHelpers.snoozeAwareAlertingGrace(snoozeSeconds: 540), 840)
        XCTAssertEqual(AlarmSchedulingHelpers.snoozeAwareAlertingGrace(snoozeSeconds: 0), 300)
    }

    func testStaleAlarmDetection() {
        let past = Date().addingTimeInterval(-60)
        let future = Date().addingTimeInterval(300)
        XCTAssertTrue(AlarmSchedulingHelpers.isStaleAlarm(fireDate: past))
        XCTAssertFalse(AlarmSchedulingHelpers.isStaleAlarm(fireDate: future))
    }

    func testStaleAlarmGracePeriod() {
        let fire = Date(timeIntervalSince1970: 1_000_000)
        let beforeGrace = fire.addingTimeInterval(AlarmSchedulingHelpers.countdownCleanupGrace - 1)
        let afterGrace = fire.addingTimeInterval(AlarmSchedulingHelpers.countdownCleanupGrace + 1)
        XCTAssertFalse(AlarmSchedulingHelpers.isStaleAlarm(fireDate: fire, now: beforeGrace, graceAfterFire: AlarmSchedulingHelpers.countdownCleanupGrace))
        XCTAssertTrue(AlarmSchedulingHelpers.isStaleAlarm(fireDate: fire, now: afterGrace, graceAfterFire: AlarmSchedulingHelpers.countdownCleanupGrace))
    }

    func testUpcomingFireDateDetection() {
        let past = Date().addingTimeInterval(-60)
        let future = Date().addingTimeInterval(300)
        XCTAssertFalse(AlarmSchedulingHelpers.hasUpcomingFireDate(past))
        XCTAssertTrue(AlarmSchedulingHelpers.hasUpcomingFireDate(future))
    }

    func testEventEndedDetection() {
        let ended = Date().addingTimeInterval(-60)
        let ongoing = Date().addingTimeInterval(300)
        XCTAssertTrue(AlarmSchedulingHelpers.isEventEnded(endDate: ended))
        XCTAssertFalse(AlarmSchedulingHelpers.isEventEnded(endDate: ongoing))
    }

    func testOrphanOnTopOfManagedAlarmIsDuplicate() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(AlarmSchedulingHelpers.isDuplicateFire(base, of: [base]))
        XCTAssertTrue(AlarmSchedulingHelpers.isDuplicateFire(base, of: [base.addingTimeInterval(2)]))
    }

    func testOrphanAtItsOwnTimeIsKept() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(AlarmSchedulingHelpers.isDuplicateFire(base, of: []))
        XCTAssertFalse(AlarmSchedulingHelpers.isDuplicateFire(base, of: [base.addingTimeInterval(60)]))
    }
}
