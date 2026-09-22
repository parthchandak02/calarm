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
            calendarColorHex: nil,
            alarmOffsets: [.tenMinutes]
        )
        XCTAssertEqual(event.source, .google)
        XCTAssertTrue(event.alarmEnabled)
    }

    // MARK: - eventType filtering

    private func decode(eventType: String?) throws -> GoogleCalendarEvent {
        let typeField = eventType.map { "\"eventType\": \"\($0)\"," } ?? ""
        let json = """
        {
            "id": "abc123",
            "status": "confirmed",
            "summary": "Deep work",
            \(typeField)
            "start": { "dateTime": "2026-09-20T10:00:00Z" },
            "end": { "dateTime": "2026-09-20T11:00:00Z" }
        }
        """
        return try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(json.utf8))
    }

    /// The owner runs an Apps Script that converts every solo event into `focusTime`, so
    /// without this filter calarm would fire an AlarmKit alarm -- the loudest thing an
    /// iOS app can do -- for each block whose whole purpose is not being interrupted.
    func testFocusTimeIsNotAlertable() throws {
        let event = try decode(eventType: "focusTime")
        XCTAssertEqual(event.eventType, "focusTime")
        XCTAssertFalse(event.isAlertableEventType)
    }

    func testOutOfOfficeAndWorkingLocationAreNotAlertable() throws {
        XCTAssertFalse(try decode(eventType: "outOfOffice").isAlertableEventType)
        XCTAssertFalse(try decode(eventType: "workingLocation").isAlertableEventType)
        XCTAssertFalse(try decode(eventType: "birthday").isAlertableEventType)
    }

    func testDefaultEventTypeIsAlertable() throws {
        XCTAssertTrue(try decode(eventType: "default").isAlertableEventType)
    }

    /// A flight or booking Google extracted from mail is worth waking for.
    func testFromGmailIsAlertable() throws {
        XCTAssertTrue(try decode(eventType: "fromGmail").isAlertableEventType)
    }

    /// Fail open on both a missing field and an unknown value. Google adds event types
    /// over time, and swallowing a new one silently would mean a missed meeting, which is
    /// strictly worse than one extra alarm.
    func testAbsentOrUnknownEventTypeIsAlertable() throws {
        XCTAssertNil(try decode(eventType: nil).eventType)
        XCTAssertTrue(try decode(eventType: nil).isAlertableEventType)
        XCTAssertTrue(try decode(eventType: "someTypeGoogleAddsIn2027").isAlertableEventType)
    }

    /// Decoding must not break on the fields added alongside eventType.
    func testCreatedTimestampDecodes() throws {
        let json = """
        {
            "id": "abc",
            "created": "2026-09-18T12:00:00.000Z",
            "updated": "2026-09-18T12:30:00.000Z",
            "start": { "dateTime": "2026-09-20T10:00:00Z" },
            "end": { "dateTime": "2026-09-20T11:00:00Z" }
        }
        """
        let event = try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.created, "2026-09-18T12:00:00.000Z")
        XCTAssertEqual(event.updated, "2026-09-18T12:30:00.000Z")
    }
}
