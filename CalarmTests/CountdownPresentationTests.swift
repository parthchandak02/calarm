import XCTest

final class CountdownPresentationTests: XCTestCase {
    func testCompactWidthNarrowsWithRemainingTime() {
        XCTAssertEqual(AlarmSchedulingHelpers.compactCountdownWidth(remaining: 12 * 3_600 + 45 * 60 + 44), 58)
        XCTAssertEqual(AlarmSchedulingHelpers.compactCountdownWidth(remaining: 3_600), 58)
        XCTAssertEqual(AlarmSchedulingHelpers.compactCountdownWidth(remaining: 3_599), 38)
        XCTAssertEqual(AlarmSchedulingHelpers.compactCountdownWidth(remaining: 600), 38)
        XCTAssertEqual(AlarmSchedulingHelpers.compactCountdownWidth(remaining: 599), 28)
        XCTAssertEqual(AlarmSchedulingHelpers.compactCountdownWidth(remaining: 45), 28)
    }

    func testCountdownEndingAtOrBeforeStartIsNotSnooze() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(AlarmSchedulingHelpers.isSnoozeCountdown(countdownFireDate: start.addingTimeInterval(-60), eventStart: start))
        XCTAssertFalse(AlarmSchedulingHelpers.isSnoozeCountdown(countdownFireDate: start, eventStart: start))
        XCTAssertFalse(AlarmSchedulingHelpers.isSnoozeCountdown(countdownFireDate: start.addingTimeInterval(60), eventStart: nil))
    }

    func testCountdownPastStartIsSnooze() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(AlarmSchedulingHelpers.isSnoozeCountdown(countdownFireDate: start.addingTimeInterval(300), eventStart: start))
    }

    func testCountdownGraceOutlastsOneSnooze() {
        XCTAssertEqual(AlarmSchedulingHelpers.snoozeAwareCountdownGrace(snoozeSeconds: 300), 360)
        XCTAssertEqual(AlarmSchedulingHelpers.snoozeAwareCountdownGrace(snoozeSeconds: 0), 60)
    }

    func testProbePendingWithoutObservation() {
        let scheduled = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(AlarmTimingProbe.verdict(scheduledAt: scheduled, preAlert: 8, observedAt: nil), .pending)
    }

    func testProbeOnTimeWhenCountdownEndsAtFixedDate() {
        let scheduled = Date(timeIntervalSince1970: 1_800_000_000)
        let verdict = AlarmTimingProbe.verdict(scheduledAt: scheduled, preAlert: 8, observedAt: scheduled.addingTimeInterval(9))
        XCTAssertEqual(verdict, .onTime(seconds: 9))
    }

    func testProbeDetectsCountdownStartingAtFixedDate() {
        let scheduled = Date(timeIntervalSince1970: 1_800_000_000)
        let verdict = AlarmTimingProbe.verdict(scheduledAt: scheduled, preAlert: 8, observedAt: scheduled.addingTimeInterval(16.4))
        XCTAssertEqual(verdict, .countdownStartsAtFireDate(seconds: 16))
    }

    func testProbeReportsAnythingElse() {
        let scheduled = Date(timeIntervalSince1970: 1_800_000_000)
        let verdict = AlarmTimingProbe.verdict(scheduledAt: scheduled, preAlert: 8, observedAt: scheduled.addingTimeInterval(40))
        XCTAssertEqual(verdict, .other(seconds: 40))
    }
}
