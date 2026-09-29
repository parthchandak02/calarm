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

    func testCountdownIsDaysHoursMinutesSeconds() {
        let fire = now.addingTimeInterval(2 * 86_400 + 3 * 3_600 + 7 * 60 + 9)
        XCTAssertEqual(DepartureBoard.countdownGroups(until: fire, now: now), ["02", "03", "07", "09"])
    }

    func testCountdownPastFireDateClampsToZero() {
        XCTAssertEqual(DepartureBoard.countdownGroups(until: now.addingTimeInterval(-5), now: now), ["00", "00", "00", "00"])
    }

    func testNextRingMovesOnOnceAnAlarmRings() {
        let today = DepartureBoard.Ring(eventID: "meet", title: "Meet", fireDate: now.addingTimeInterval(40))
        let tomorrow = DepartureBoard.Ring(eventID: "1on1", title: "1:1", fireDate: now.addingTimeInterval(67_140))
        XCTAssertEqual(DepartureBoard.nextRing([tomorrow, today], now: now), today)
        // After the ring, the next alarm is tomorrow's, not the meeting's start ten minutes on.
        XCTAssertEqual(DepartureBoard.nextRing([tomorrow, today], now: now.addingTimeInterval(41)), tomorrow)
        XCTAssertNil(DepartureBoard.nextRing([today], now: now.addingTimeInterval(41)))
    }

    func testCountdownDaysCapAtNinetyNine() {
        XCTAssertEqual(DepartureBoard.countdownGroups(until: now.addingTimeInterval(200 * 86_400), now: now).first, "99")
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
        XCTAssertEqual(DepartureBoard.rowLabel(for: event(startIn: -60, offsets: [.tenMinutes]), tooSoon: false, missed: true), "missed")
    }

    func testDayTitleNamesTodayAndTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        XCTAssertTrue(DepartureBoard.dayTitle(for: now, now: now, calendar: calendar, locale: locale).hasPrefix("TODAY · "))
        XCTAssertTrue(DepartureBoard.dayTitle(for: now.addingTimeInterval(86_400), now: now, calendar: calendar, locale: locale).hasPrefix("TOMORROW · "))
        XCTAssertFalse(DepartureBoard.dayTitle(for: now.addingTimeInterval(3 * 86_400), now: now, calendar: calendar, locale: locale).contains("·"))
    }

    func testDayPartsSplitsRelativeDayFromDateTiles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let today = DepartureBoard.dayParts(for: now, now: now, calendar: calendar, locale: locale)
        XCTAssertEqual(today.relative, "TODAY")
        XCTAssertEqual(today.tiles.count, 2)
        let tomorrow = DepartureBoard.dayParts(for: now.addingTimeInterval(86_400), now: now, calendar: calendar, locale: locale)
        XCTAssertEqual(tomorrow.relative, "TOMORROW")
        let later = DepartureBoard.dayParts(for: now.addingTimeInterval(3 * 86_400), now: now, calendar: calendar, locale: locale)
        XCTAssertNil(later.relative)
        XCTAssertEqual(later.tiles.count, 3)
        XCTAssertTrue(later.tiles.allSatisfy { $0 == $0.uppercased() && !$0.isEmpty })
    }
}
