//
//  GoogleCalendarMappingTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

final class GoogleCalendarMappingTests: XCTestCase {
    func testOccurrenceIDUsesGooglePrefix() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let id = GoogleCalendarFetchedEvent.occurrenceID(
            googleEventID: "abc123_20260813T010000Z",
            startDate: start
        )
        XCTAssertTrue(id.hasPrefix("google.abc123_20260813T010000Z_"))
        XCTAssertNotNil(EventOccurrenceID(rawValue: id))
    }

    func testScheduleEventIncludesSource() {
        let event = ScheduleEvent(
            id: "google.test_0",
            title: "Standup",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            location: nil,
            calendarTitle: "Work",
            source: .google,
            alarmOffsets: [.tenMinutes]
        )
        XCTAssertEqual(event.source, .google)
        XCTAssertTrue(event.alarmEnabled)
    }
}
