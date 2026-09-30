import XCTest
@testable import Calarm

@MainActor
final class DefaultAlarmChangeTests: XCTestCase {
    private func event(_ id: String, startIn seconds: TimeInterval, offsets: [AlarmOffsetOption]) -> ScheduleEvent {
        let start = Date().addingTimeInterval(seconds)
        return ScheduleEvent(
            id: id,
            title: id,
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            location: nil,
            calendarTitle: "Personal",
            source: .google,
            calendarColorHex: nil,
            alarmOffsets: offsets
        )
    }

    func testOffersEveryUpcomingArmedEventOnAnotherTime() {
        let events = [
            event("ten", startIn: 7_200, offsets: [.tenMinutes]),
            event("two", startIn: 7_200, offsets: [.oneMinute, .thirtyMinutes]),
            event("same", startIn: 7_200, offsets: [.oneMinute]),
            event("off", startIn: 7_200, offsets: []),
            event("started", startIn: -60, offsets: [.tenMinutes]),
        ]
        XCTAssertEqual(DefaultAlarmChange.eventIDsToAlign(events, to: .oneMinute), ["ten", "two"])
    }

    func testNoAlarmDefaultNeverDisarms() {
        let events = [event("ten", startIn: 7_200, offsets: [.tenMinutes])]
        XCTAssertTrue(DefaultAlarmChange.eventIDsToAlign(events, to: .noAlarm).isEmpty)
    }
}
