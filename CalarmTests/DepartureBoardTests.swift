import XCTest
@testable import Calarm

final class DepartureBoardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func event(startIn seconds: TimeInterval, offsets: [AlarmOffsetOption]) -> ScheduleEvent {
        let start = Date().addingTimeInterval(seconds)
        return ScheduleEvent(
            id: "evt",
            title: "Standup",
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            location: nil,
            calendarTitle: "Work",
            source: .eventKit,
            calendarColorHex: nil,
            alarmOffsets: offsets
        )
    }

    func testCountdownUnderAnHourShowsMinutesAndSeconds() {
        let countdown = DepartureBoard.countdown(until: now.addingTimeInterval(42 * 60 + 10), now: now)
        XCTAssertEqual(countdown, .init(digits: "42:10", unit: "MIN"))
    }

    func testCountdownPastFireDateClampsToZero() {
        XCTAssertEqual(DepartureBoard.countdown(until: now.addingTimeInterval(-5), now: now).digits, "00:00")
    }

    func testCountdownInHoursShowsHoursAndMinutes() {
        let countdown = DepartureBoard.countdown(until: now.addingTimeInterval(3 * 3_600 + 7 * 60 + 59), now: now)
        XCTAssertEqual(countdown, .init(digits: "3:07", unit: "HRS"))
    }

    func testCountdownPastNinetyNineHoursShowsDays() {
        let countdown = DepartureBoard.countdown(until: now.addingTimeInterval(5 * 86_400), now: now)
        XCTAssertEqual(countdown, .init(digits: "5", unit: "DAYS"))
    }

    func testRowLabelListsUpcomingOffsetsSoonestFirst() {
        let item = event(startIn: 3_600, offsets: [.oneMinute, .tenMinutes])
        XCTAssertEqual(DepartureBoard.rowLabel(for: item, tooSoon: false), "−10m −1m")
    }

    func testRowLabelStates() {
        XCTAssertEqual(DepartureBoard.rowLabel(for: event(startIn: 3_600, offsets: []), tooSoon: false), "off")
        XCTAssertEqual(DepartureBoard.rowLabel(for: event(startIn: 60, offsets: [.tenMinutes]), tooSoon: false), "passed")
        XCTAssertEqual(DepartureBoard.rowLabel(for: event(startIn: -60, offsets: [.tenMinutes]), tooSoon: false), "past")
        XCTAssertEqual(DepartureBoard.rowLabel(for: event(startIn: 3_600, offsets: [.tenMinutes]), tooSoon: true), "too soon")
    }

    func testDayTitleNamesTodayAndTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        XCTAssertTrue(DepartureBoard.dayTitle(for: now, now: now, calendar: calendar, locale: locale).hasPrefix("TODAY · "))
        XCTAssertTrue(DepartureBoard.dayTitle(for: now.addingTimeInterval(86_400), now: now, calendar: calendar, locale: locale).hasPrefix("TOMORROW · "))
        XCTAssertFalse(DepartureBoard.dayTitle(for: now.addingTimeInterval(3 * 86_400), now: now, calendar: calendar, locale: locale).contains("·"))
    }
}
