import XCTest
@testable import Calarm

final class ScheduleEventTests: XCTestCase {
    private func event(
        startOffset: TimeInterval,
        offsets: [AlarmOffsetOption] = [.tenMinutes]
    ) -> ScheduleEvent {
        let start = Date().addingTimeInterval(startOffset)
        return ScheduleEvent(
            id: "evt_\(startOffset)",
            title: "Test",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            location: nil,
            calendarTitle: "Work",
            source: .eventKit,
            calendarColorHex: nil,
            alarmOffsets: offsets
        )
    }

    func testReminderPassedBeforeEventStart() {
        // Event in 1 minute; 10-minute alarm fire time already passed.
        let item = event(startOffset: 60, offsets: [.tenMinutes])
        XCTAssertTrue(item.isReminderPassed)
        XCTAssertFalse(item.isAlarmInPast)
        XCTAssertEqual(item.alarmSummary, "Reminder passed")
        XCTAssertEqual(item.nextAlarmDate, item.startDate)
    }

    func testPastAfterEventStart() {
        let item = event(startOffset: -600, offsets: [.tenMinutes])
        XCTAssertFalse(item.isReminderPassed)
        XCTAssertTrue(item.isAlarmInPast)
        XCTAssertEqual(item.alarmSummary, "All alarms passed")
        XCTAssertNil(item.nextAlarmDate)
    }

    func testUpcomingAlarmStillSchedulable() {
        let item = event(startOffset: 7200, offsets: [.sixtyMinutes])
        XCTAssertFalse(item.isReminderPassed)
        XCTAssertFalse(item.isAlarmInPast)
        XCTAssertTrue(item.canScheduleAlarm)
        XCTAssertNotNil(item.nextAlarmDate)
    }
}
