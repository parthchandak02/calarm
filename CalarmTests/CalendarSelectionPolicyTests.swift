//
//  CalendarSelectionPolicyTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

final class CalendarSelectionPolicyTests: XCTestCase {
    func testNoCalendarsOffersNoBulkAction() {
        XCTAssertNil(CalendarSelectionPolicy.bulkAction(enabledStates: []))
    }

    func testAllOnOffersTurnAllOff() {
        XCTAssertEqual(CalendarSelectionPolicy.bulkAction(enabledStates: [true, true]), .turnAllOff)
    }

    func testAnyOffOffersTurnAllOn() {
        XCTAssertEqual(CalendarSelectionPolicy.bulkAction(enabledStates: [true, false]), .turnAllOn)
        XCTAssertEqual(CalendarSelectionPolicy.bulkAction(enabledStates: [false, false]), .turnAllOn)
    }

    func testBulkActionTitlesAndDirection() {
        XCTAssertEqual(CalendarBulkAction.turnAllOn.title, "Turn all on")
        XCTAssertEqual(CalendarBulkAction.turnAllOff.title, "Turn all off")
        XCTAssertTrue(CalendarBulkAction.turnAllOn.enables)
        XCTAssertFalse(CalendarBulkAction.turnAllOff.enables)
    }

    func testDisabledIDs() {
        XCTAssertEqual(CalendarSelectionPolicy.disabledIDs(allCalendarIDs: ["a", "b"], enabled: false), ["a", "b"])
        XCTAssertEqual(CalendarSelectionPolicy.disabledIDs(allCalendarIDs: ["a", "b"], enabled: true), [])
    }

    @MainActor
    func testUpcomingCountSkipsStartedEventsAndOtherCalendars() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let events = [
            event("started", start: now.addingTimeInterval(-600), calendar: "Home", source: .eventKit),
            event("soon", start: now.addingTimeInterval(600), calendar: "Home", source: .eventKit),
            event("now", start: now, calendar: "Home", source: .eventKit),
            event("other", start: now.addingTimeInterval(600), calendar: "Work", source: .eventKit),
            event("google", start: now.addingTimeInterval(600), calendar: "Home", source: .google),
        ]
        XCTAssertEqual(
            CalendarSelectionPolicy.upcomingCount(in: events, source: .eventKit, calendarTitle: "Home", now: now),
            2
        )
    }

    func testFootnoteNamesTheFetchHorizon() {
        XCTAssertEqual(
            CalendarSelectionPolicy.countsFootnote(fetchDays: 8),
            "All-day events are always skipped. Numbers are upcoming events in the next 8 days."
        )
        XCTAssertTrue(CalendarSelectionPolicy.countsFootnote(fetchDays: 1).hasSuffix("next 1 day."))
    }

    @MainActor
    private func event(_ id: String, start: Date, calendar: String, source: CalendarSource) -> ScheduleEvent {
        ScheduleEvent(
            id: id,
            title: id,
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            location: nil,
            calendarTitle: calendar,
            source: source,
            calendarColorHex: nil,
            alarmOffsets: []
        )
    }
}
