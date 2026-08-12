import XCTest

final class AlarmSchedulingHelpersTests: XCTestCase {
    func testStableAlarmIDIsDeterministic() {
        let a = AlarmSchedulingHelpers.stableAlarmID(occurrenceID: "evt_1", offsetRawValue: "tenMinutes")
        let b = AlarmSchedulingHelpers.stableAlarmID(occurrenceID: "evt_1", offsetRawValue: "tenMinutes")
        XCTAssertEqual(a, b)
    }

    func testStaggerCollidingFireDates() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let instances = [
            (occurrenceID: "a", offsetRawValue: "tenMinutes", fireDate: base),
            (occurrenceID: "b", offsetRawValue: "fiveMinutes", fireDate: base)
        ]
        let staggered = AlarmSchedulingHelpers.collisionGroupsSortedByFireDate(instances: instances)
        XCTAssertEqual(staggered.count, 2)
        XCTAssertEqual(staggered[0].fireDate, base)
        XCTAssertEqual(staggered[1].fireDate, base.addingTimeInterval(2))
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
            accentRawValue: "coral"
        )
        let second = AlarmSchedulingHelpers.schedulingFingerprint(
            instances: instances,
            nextLiveActivityKey: nil,
            snoozeRawValue: "540",
            accentRawValue: "coral"
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
            accentRawValue: "coral"
        )
        let violet = AlarmSchedulingHelpers.schedulingFingerprint(
            instances: instances,
            nextLiveActivityKey: "a.tenMinutes",
            snoozeRawValue: "540",
            accentRawValue: "violet"
        )
        XCTAssertNotEqual(coral, violet)
    }

    func testStaleAlarmDetection() {
        let past = Date().addingTimeInterval(-60)
        let future = Date().addingTimeInterval(300)
        XCTAssertTrue(AlarmSchedulingHelpers.isStaleAlarm(fireDate: past))
        XCTAssertFalse(AlarmSchedulingHelpers.isStaleAlarm(fireDate: future))
    }

    func testUpcomingFireDateDetection() {
        let past = Date().addingTimeInterval(-60)
        let future = Date().addingTimeInterval(300)
        XCTAssertFalse(AlarmSchedulingHelpers.hasUpcomingFireDate(past))
        XCTAssertTrue(AlarmSchedulingHelpers.hasUpcomingFireDate(future))
    }
}
