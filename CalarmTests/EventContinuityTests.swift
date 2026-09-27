//
//  EventContinuityTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

final class EventContinuityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func occurrence(_ base: String, title: String = "Standup", start: TimeInterval, length: TimeInterval = 1800) -> EventContinuity.Occurrence {
        let startDate = now.addingTimeInterval(start)
        return EventContinuity.Occurrence(
            id: EventOccurrenceID(eventIdentifier: base, startDate: startDate).rawValue,
            title: title,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(length)
        )
    }

    private func carried(removed: [EventContinuity.Occurrence], added: [EventContinuity.Occurrence]) -> [String: String] {
        EventContinuity.carriedSettings(removed: removed, added: added, unconfigured: added, now: now)
    }

    func testMovedMeetingKeepsItsSetting() {
        let old = occurrence("google.abc", start: 3600)
        let moved = occurrence("google.abc", start: 7200)

        let moves = carried(removed: [old], added: [moved])

        XCTAssertEqual(moves, [old.id: moved.id])
    }

    func testRecreatedEventWithNewIDKeepsItsSettingBySameTitleAndStart() {
        let old = occurrence("google.abc", start: 3600)
        let recreated = occurrence("google.xyz", start: 3600)

        let moves = carried(removed: [old], added: [recreated])

        XCTAssertEqual(moves, [old.id: recreated.id])
    }

    func testEventKitCopyReplacedByGoogleTwinKeepsItsSetting() {
        let old = occurrence("EK-1", start: 3600)
        let twin = occurrence("google.abc", start: 3600)

        XCTAssertEqual(carried(removed: [old], added: [twin]), [old.id: twin.id])
    }

    func testEndedEventIsNotCarriedToTheNextOccurrence() {
        let ended = occurrence("EK-series", start: -3600, length: 1800)
        let nextWeek = occurrence("EK-series", start: 7 * 86_400)

        XCTAssertTrue(carried(removed: [ended], added: [nextWeek]).isEmpty)
    }

    func testRecurringSeriesPicksTheNearestOccurrence() {
        let old = occurrence("EK-series", start: 3600)
        let near = occurrence("EK-series", start: 5400)
        let far = occurrence("EK-series", start: 86_400 + 3600)

        XCTAssertEqual(carried(removed: [old], added: [far, near]), [old.id: near.id])
    }

    func testEachNewOccurrenceReceivesAtMostOneSetting() {
        let first = occurrence("google.a", title: "Sync", start: 3600)
        let second = occurrence("google.b", title: "Sync", start: 3600)
        let only = occurrence("google.c", title: "Sync", start: 3600)

        let moves = carried(removed: [first, second], added: [only])

        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(Set(moves.values), [only.id])
    }

    func testUnrelatedNewEventReceivesNothing() {
        let old = occurrence("google.abc", title: "Standup", start: 3600)
        let other = occurrence("google.xyz", title: "Lunch", start: 7200)

        XCTAssertTrue(carried(removed: [old], added: [other]).isEmpty)
    }

    func testSeriesOccurrenceMoreThanADayAwayIsNotTheSameMeeting() {
        let deleted = occurrence("EK-series", start: 3600)
        let nextWeek = occurrence("EK-series", start: 7 * 86_400 + 3600)

        XCTAssertTrue(carried(removed: [deleted], added: [nextWeek]).isEmpty)
    }

    func testTwinWhoseStartDiffersBySubsecondsStillMatches() {
        let old = occurrence("EK-1", start: 3600)
        let twinStart = old.startDate.addingTimeInterval(0.4)
        let twin = EventContinuity.Occurrence(
            id: EventOccurrenceID(eventIdentifier: "google.abc", startDate: twinStart).rawValue,
            title: old.title,
            startDate: twinStart,
            endDate: old.endDate
        )

        XCTAssertEqual(carried(removed: [old], added: [twin]), [old.id: twin.id])
    }

    func testCopyInsertedASyncBeforeTheOriginalWasRemovedStillMatches() {
        let original = occurrence("google.abc", start: 3600)
        let copy = occurrence("google.xyz", start: 3600)

        let moves = EventContinuity.carriedSettings(removed: [original], added: [], unconfigured: [copy], now: now)

        XCTAssertEqual(moves, [original.id: copy.id])
    }

    func testOlderOccurrenceIsOnlyMatchedBySameTitleAndStart() {
        let old = occurrence("EK-series", start: 3600)
        let alreadyListed = occurrence("EK-series", start: 5400)

        XCTAssertTrue(EventContinuity.carriedSettings(removed: [old], added: [], unconfigured: [alreadyListed], now: now).isEmpty)
    }

    @MainActor
    func testMoveOverridesTransfersTheSettingAndKeepsAnExistingTarget() {
        let prefs = EventAlarmPreferences()
        let from = "test.continuity_1"
        let to = "test.continuity_2"
        let kept = "test.continuity_3"
        let keptTarget = "test.continuity_4"
        defer { [from, to, kept, keptTarget].forEach(prefs.removeOverride) }

        prefs.setAlarmOffsets([.tenMinutes], for: from)
        prefs.setAlarmOffsets([.fiveMinutes], for: kept)
        prefs.setAlarmOffsets([], for: keptTarget)
        prefs.moveOverrides([from: to, kept: keptTarget])

        XCTAssertFalse(prefs.hasOverride(for: from))
        XCTAssertEqual(prefs.alarmOffsets(for: to), [.tenMinutes])
        XCTAssertEqual(prefs.alarmOffsets(for: keptTarget), [])
        XCTAssertEqual(prefs.alarmOffsets(for: kept), [.fiveMinutes])
    }
}
