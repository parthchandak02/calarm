//
//  LiveActivityWindowTests.swift
//  CalarmTests
//

import XCTest

final class LiveActivityWindowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ value: Double) -> Date {
        now.addingTimeInterval(value * 60)
    }

    func testAlwaysCountsDownTheNextAlarmOnly() {
        let plans = LiveActivityWindow.plans(fireDates: [minutes(60), minutes(120)], lead: .always, now: now)
        XCTAssertEqual(plans, [.countdownNow(preAlert: 3600), .alertOnly])
    }

    func testEveryDistantAlarmGetsItsOwnWindow() {
        let plans = LiveActivityWindow.plans(fireDates: [minutes(60), minutes(120)], lead: .five, now: now)
        XCTAssertEqual(plans, [
            .fixedWindow(start: minutes(55), preAlert: 300),
            .fixedWindow(start: minutes(115), preAlert: 300),
        ])
    }

    func testWindowIsClippedToThePreviousRing() {
        let plans = LiveActivityWindow.plans(fireDates: [minutes(60), minutes(62)], lead: .five, now: now)
        XCTAssertEqual(plans[1], .fixedWindow(start: minutes(60), preAlert: 120))
    }

    func testFirstAlarmInsideItsWindowCountsDownNow() {
        let plans = LiveActivityWindow.plans(fireDates: [minutes(3)], lead: .five, now: now)
        XCTAssertEqual(plans, [.countdownNow(preAlert: 180)])
    }

    func testFirstAlarmWithinTheMarginCountsDownNow() {
        let plans = LiveActivityWindow.plans(fireDates: [minutes(5).addingTimeInterval(5)], lead: .five, now: now)
        XCTAssertEqual(plans, [.countdownNow(preAlert: 305)])
    }

    func testLaterAlarmWhoseWindowIsDueGoesAlertOnly() {
        let plans = LiveActivityWindow.plans(fireDates: [minutes(0.1), minutes(2)], lead: .five, now: now)
        XCTAssertEqual(plans[1], .alertOnly)
    }

    func testAlarmsInTheSameSecondShareNoWindow() {
        let plans = LiveActivityWindow.plans(fireDates: [minutes(60), minutes(60)], lead: .ten, now: now)
        XCTAssertEqual(plans[1], .alertOnly)
    }

    func testRunningCountdownSatisfiesCountdownNow() {
        XCTAssertTrue(LiveActivityWindow.existingSatisfies(
            plan: .countdownNow(preAlert: 170),
            fireDate: minutes(3),
            existingFixedDate: nil,
            existingPreAlert: 180,
            storedTarget: minutes(3)
        ))
    }

    func testStartedWindowSatisfiesCountdownNow() {
        XCTAssertTrue(LiveActivityWindow.existingSatisfies(
            plan: .countdownNow(preAlert: 170),
            fireDate: minutes(3),
            existingFixedDate: minutes(-2),
            existingPreAlert: 300,
            storedTarget: minutes(3),
            now: now
        ))
    }

    func testCountdownToAnotherTimeDoesNotSatisfy() {
        XCTAssertFalse(LiveActivityWindow.existingSatisfies(
            plan: .countdownNow(preAlert: 170),
            fireDate: minutes(3),
            existingFixedDate: nil,
            existingPreAlert: 180,
            storedTarget: minutes(4)
        ))
    }

    func testWindowMustMatchWithinHalfASecond() {
        let plan = LiveActivityPlan.fixedWindow(start: minutes(55), preAlert: 300)
        XCTAssertTrue(LiveActivityWindow.existingSatisfies(
            plan: plan, fireDate: minutes(60),
            existingFixedDate: minutes(55).addingTimeInterval(0.4), existingPreAlert: 300, storedTarget: minutes(60)
        ))
        XCTAssertFalse(LiveActivityWindow.existingSatisfies(
            plan: plan, fireDate: minutes(60),
            existingFixedDate: minutes(55).addingTimeInterval(1), existingPreAlert: 300, storedTarget: minutes(60)
        ))
        XCTAssertFalse(LiveActivityWindow.existingSatisfies(
            plan: plan, fireDate: minutes(60),
            existingFixedDate: minutes(55), existingPreAlert: 600, storedTarget: minutes(60)
        ))
    }

    func testCountdownDoesNotSatisfyAWindowNotYetDue() {
        XCTAssertFalse(LiveActivityWindow.existingSatisfies(
            plan: .fixedWindow(start: minutes(55), preAlert: 300),
            fireDate: minutes(60),
            existingFixedDate: nil,
            existingPreAlert: 3600,
            storedTarget: minutes(60)
        ))
    }

    func testAlertOnlyNeedsNoCountdown() {
        XCTAssertTrue(LiveActivityWindow.existingSatisfies(
            plan: .alertOnly, fireDate: minutes(60),
            existingFixedDate: minutes(60), existingPreAlert: 1, storedTarget: nil
        ))
        XCTAssertFalse(LiveActivityWindow.existingSatisfies(
            plan: .alertOnly, fireDate: minutes(60),
            existingFixedDate: minutes(55), existingPreAlert: 300, storedTarget: minutes(60)
        ))
    }

    func testStoredTargetWinsOverFixedDate() {
        XCTAssertEqual(LiveActivityWindow.resolvedFireDate(fixedDate: minutes(55), preAlert: 300, storedTarget: minutes(60)), minutes(60))
        XCTAssertNil(LiveActivityWindow.resolvedFireDate(fixedDate: nil, preAlert: 300, storedTarget: nil))
    }

    func testMissingTargetReadsAWindowAsFixedDatePlusPreAlert() {
        XCTAssertEqual(LiveActivityWindow.resolvedFireDate(fixedDate: minutes(55), preAlert: 300, storedTarget: nil), minutes(60))
        XCTAssertEqual(LiveActivityWindow.resolvedFireDate(fixedDate: minutes(60), preAlert: 1, storedTarget: nil), minutes(60))
        XCTAssertEqual(LiveActivityWindow.resolvedFireDate(fixedDate: minutes(60), preAlert: nil, storedTarget: nil), minutes(60))
    }

    func testWindowNotYetStartedDoesNotSatisfyCountdownNow() {
        XCTAssertFalse(LiveActivityWindow.existingSatisfies(
            plan: .countdownNow(preAlert: 170),
            fireDate: minutes(3),
            existingFixedDate: minutes(1),
            existingPreAlert: 120,
            storedTarget: minutes(3),
            now: now
        ))
        XCTAssertTrue(LiveActivityWindow.existingSatisfies(
            plan: .countdownNow(preAlert: 170),
            fireDate: minutes(3),
            existingFixedDate: now.addingTimeInterval(5),
            existingPreAlert: 175,
            storedTarget: minutes(3),
            now: now
        ))
    }

    func testLeadOrderAndDefault() {
        XCTAssertEqual(LiveActivityLead.allCases, [.always, .ten, .five, .two])
        XCTAssertEqual(LiveActivityLead.defaultLead, .five)
        XCTAssertNil(LiveActivityLead.always.seconds)
        XCTAssertEqual(LiveActivityLead.two.seconds, 120)
    }
}
