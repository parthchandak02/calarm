//
//  GoogleSyncPolicyTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

final class GoogleSyncPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var horizon: Date { now.addingTimeInterval(8 * 86_400) }

    func testMeetingInProgressStaysInTheWindow() {
        XCTAssertTrue(GoogleSyncPolicy.isInWindow(
            startDate: now.addingTimeInterval(-60),
            endDate: now.addingTimeInterval(1740),
            now: now,
            horizonEnd: horizon
        ))
    }

    func testEndedMeetingLeavesTheWindow() {
        XCTAssertFalse(GoogleSyncPolicy.isInWindow(
            startDate: now.addingTimeInterval(-1800),
            endDate: now,
            now: now,
            horizonEnd: horizon
        ))
    }

    func testMeetingBeyondTheHorizonIsOutside() {
        XCTAssertFalse(GoogleSyncPolicy.isInWindow(
            startDate: horizon.addingTimeInterval(60),
            endDate: horizon.addingTimeInterval(1860),
            now: now,
            horizonEnd: horizon
        ))
    }

    func testWindowIsStaleWithoutAFetchOrAfterAnHour() {
        XCTAssertTrue(GoogleSyncPolicy.isWindowStale(lastWindowFetch: nil, now: now))
        XCTAssertTrue(GoogleSyncPolicy.isWindowStale(lastWindowFetch: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(GoogleSyncPolicy.isWindowStale(lastWindowFetch: now.addingTimeInterval(-600), now: now))
    }

    func testClockMovedBackMakesTheWindowStale() {
        XCTAssertTrue(GoogleSyncPolicy.isWindowStale(lastWindowFetch: now.addingTimeInterval(600), now: now))
    }
}
