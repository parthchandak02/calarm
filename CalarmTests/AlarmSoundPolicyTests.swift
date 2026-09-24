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

    func testFallbackRingsOneMinuteLater() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(AlarmSoundPolicy.fallbackFireDate(after: fire), fire.addingTimeInterval(60))
    }

    func testFallbackIDIsStableAndDistinct() {
        let id = AlarmSchedulingHelpers.stableAlarmID(occurrenceID: "evt", offsetRawValue: "oneMinute")
        XCTAssertEqual(AlarmSchedulingHelpers.fallbackAlarmID(for: id), AlarmSchedulingHelpers.fallbackAlarmID(for: id))
        XCTAssertNotEqual(AlarmSchedulingHelpers.fallbackAlarmID(for: id), id)
    }

    func testSilentSoundShipsInTheAppBundle() {
        XCTAssertNotNil(Bundle.main.url(forResource: AlarmSoundPolicy.silentSoundName, withExtension: nil))
    }

    func testFallbackSurvivesItsAlarmFiring() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        let now = fire.addingTimeInterval(10)
        XCTAssertEqual(
            AlarmSoundPolicy.fallbackFireDate(anchor: fire, upcomingFireDates: [], now: now),
            fire.addingTimeInterval(60)
        )
    }

    func testFallbackEndsOnceItsTimePasses() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(AlarmSoundPolicy.fallbackFireDate(anchor: fire, upcomingFireDates: [], now: fire.addingTimeInterval(61)))
    }

    func testFallbackYieldsToAnAlarmInItsMinute() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 60))
        let next = fire.addingTimeInterval(60)
        XCTAssertNil(AlarmSoundPolicy.fallbackFireDate(anchor: fire, upcomingFireDates: [next], now: fire.addingTimeInterval(-5)))
    }
}
