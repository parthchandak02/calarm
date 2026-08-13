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
}
