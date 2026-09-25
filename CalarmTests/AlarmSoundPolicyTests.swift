//
//  AlarmSoundPolicyTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

final class AlarmSoundPolicyTests: XCTestCase {
    func testEitherSourceTurnsVibrationOn() {
        XCTAssertFalse(AlarmSoundPolicy.vibrates(manualSetting: false, focusActive: false))
        XCTAssertTrue(AlarmSoundPolicy.vibrates(manualSetting: true, focusActive: false))
        XCTAssertTrue(AlarmSoundPolicy.vibrates(manualSetting: false, focusActive: true))
    }

    func testFallbackIDIsStableAndDistinct() {
        let id = AlarmSchedulingHelpers.stableAlarmID(occurrenceID: "evt", offsetRawValue: "oneMinute")
        XCTAssertEqual(AlarmSchedulingHelpers.fallbackAlarmID(for: id), AlarmSchedulingHelpers.fallbackAlarmID(for: id))
        XCTAssertNotEqual(AlarmSchedulingHelpers.fallbackAlarmID(for: id), id)
    }

    func testSilentSoundShipsInTheAppBundle() {
        XCTAssertNotNil(Bundle.main.url(forResource: AlarmSoundPolicy.silentSoundName, withExtension: nil))
    }

    private func event(id: String, start: Date, offsets: [AlarmOffsetOption]) -> ScheduleEvent {
        ScheduleEvent(
            id: id,
            title: id,
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            location: nil,
            calendarTitle: "Work",
            source: .eventKit,
            calendarColorHex: nil,
            alarmOffsets: offsets
        )
    }

    @MainActor
    func testVibrateModeSchedulesOneInstancePerOffset() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = now.addingTimeInterval(3600)
        let events = [event(id: "standup", start: start, offsets: [.oneMinute])]

        let vibrating = AlarmScheduler.desiredInstances(events: events, vibrates: true, lead: .five, rangFireDates: [:], now: now)
        let ringing = AlarmScheduler.desiredInstances(events: events, vibrates: false, lead: .five, rangFireDates: [:], now: now)

        XCTAssertEqual(vibrating.count, 1)
        XCTAssertEqual(vibrating.map(\.fireDate), [start.addingTimeInterval(-60)])
        XCTAssertEqual(vibrating.map(\.alarmID), ringing.map(\.alarmID))
        XCTAssertTrue(vibrating.allSatisfy(\.vibrates))
    }

    @MainActor
    func testVibratingAlarmThatJustFiredLeavesNothingBehind() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [event(id: "standup", start: now.addingTimeInterval(50), offsets: [.oneMinute])]

        XCTAssertTrue(AlarmScheduler.desiredInstances(events: events, vibrates: true, lead: .five, rangFireDates: [:], now: now).isEmpty)
    }

    @MainActor
    func testAlarmThatAlreadyRangForItsFireDateIsNotRecreated() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = now.addingTimeInterval(240)
        let events = [event(id: "standup", start: start, offsets: [.atEventTime])]
        let id = AlarmSchedulingHelpers.stableAlarmID(occurrenceID: "standup", offsetRawValue: AlarmOffsetOption.atEventTime.rawValue)

        let rang = AlarmScheduler.desiredInstances(events: events, vibrates: false, lead: .five, rangFireDates: [id: start], now: now)
        let moved = AlarmScheduler.desiredInstances(events: events, vibrates: false, lead: .five, rangFireDates: [id: start.addingTimeInterval(-600)], now: now)

        XCTAssertTrue(rang.isEmpty)
        XCTAssertEqual(moved.count, 1)
    }
}
