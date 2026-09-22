//
//  ScheduleEventSourcePolicyTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

final class ScheduleEventSourcePolicyTests: XCTestCase {
    func testHasEventSourceWhenEventKitAuthorized() {
        XCTAssertTrue(
            ScheduleEventSourcePolicy.hasEventSource(
                eventKitFullAccess: true,
                googleConnected: false
            )
        )
    }

    func testHasEventSourceWhenGoogleConnected() {
        XCTAssertTrue(
            ScheduleEventSourcePolicy.hasEventSource(
                eventKitFullAccess: false,
                googleConnected: true
            )
        )
    }

    func testHasEventSourceWhenBothAvailable() {
        XCTAssertTrue(
            ScheduleEventSourcePolicy.hasEventSource(
                eventKitFullAccess: true,
                googleConnected: true
            )
        )
    }

    func testHasNoEventSourceWhenNeitherAvailable() {
        XCTAssertFalse(
            ScheduleEventSourcePolicy.hasEventSource(
                eventKitFullAccess: false,
                googleConnected: false
            )
        )
    }

    // MARK: - merge

    private func event(
        id: String,
        title: String,
        start: Date,
        source: CalendarSource
    ) -> ScheduleEvent {
        ScheduleEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            location: nil,
            calendarTitle: source == .google ? "Work (Google)" : "Work",
            source: source,
            calendarColorHex: nil,
            alarmOffsets: [.tenMinutes]
        )
    }

    /// The double-booking regression. A Google account added to iOS as a generic CalDAV
    /// entry escapes `isGoogleMirroredCalendar`'s name match, so the same meeting arrives
    /// through both sources with different identifiers. Without a title-and-time dedup
    /// that is two alarms and two bell toggles for one meeting.
    func testSameMeetingFromBothSourcesCollapsesToOne() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let merged = ScheduleEventSourcePolicy.merge(
            eventKit: [event(id: "ek_1", title: "Design review", start: start, source: .eventKit)],
            google: [event(id: "google.abc_1", title: "Design review", start: start, source: .google)]
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.source, .google, "Google is the fresher source and must win")
        XCTAssertEqual(merged.first?.id, "google.abc_1")
    }

    /// Sub-second skew between the two sources must not defeat the dedup, which is why
    /// the key is minute resolution rather than exact `Date` equality.
    func testSubSecondSkewStillCollapses() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let merged = ScheduleEventSourcePolicy.merge(
            eventKit: [event(id: "ek_1", title: "Standup", start: start.addingTimeInterval(0.4), source: .eventKit)],
            google: [event(id: "google.x_1", title: "Standup", start: start, source: .google)]
        )
        XCTAssertEqual(merged.count, 1)
    }

    func testTitleCaseAndWhitespaceDifferencesStillCollapse() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let merged = ScheduleEventSourcePolicy.merge(
            eventKit: [event(id: "ek_1", title: "  Weekly   Sync ", start: start, source: .eventKit)],
            google: [event(id: "google.y_1", title: "weekly sync", start: start, source: .google)]
        )
        XCTAssertEqual(merged.count, 1)
    }

    /// The dedup must not be so eager that it eats real back-to-back meetings.
    func testSameTitleAtDifferentTimesBothSurvive() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let merged = ScheduleEventSourcePolicy.merge(
            eventKit: [],
            google: [
                event(id: "google.a_1", title: "1:1", start: start, source: .google),
                event(id: "google.b_1", title: "1:1", start: start.addingTimeInterval(3600), source: .google)
            ]
        )
        XCTAssertEqual(merged.count, 2)
    }

    func testDifferentMeetingsAtTheSameTimeBothSurvive() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let merged = ScheduleEventSourcePolicy.merge(
            eventKit: [event(id: "ek_1", title: "Dentist", start: start, source: .eventKit)],
            google: [event(id: "google.c_1", title: "Design review", start: start, source: .google)]
        )
        XCTAssertEqual(merged.count, 2, "Overlapping but distinct meetings are not duplicates")
    }

    func testMergeIsSortedByStartDate() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let merged = ScheduleEventSourcePolicy.merge(
            eventKit: [event(id: "ek_1", title: "Later", start: start.addingTimeInterval(7200), source: .eventKit)],
            google: [event(id: "google.d_1", title: "Sooner", start: start, source: .google)]
        )
        XCTAssertEqual(merged.map(\.title), ["Sooner", "Later"])
    }

    func testEventKitOnlyPassesThroughUntouched() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let merged = ScheduleEventSourcePolicy.merge(
            eventKit: [event(id: "ek_1", title: "Solo", start: start, source: .eventKit)],
            google: []
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.source, .eventKit)
    }
}
