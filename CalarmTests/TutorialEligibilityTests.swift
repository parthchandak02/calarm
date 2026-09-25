import XCTest
@testable import Calarm

final class TutorialEligibilityTests: XCTestCase {
    private let fresh = TutorialEligibility.Signals(
        alarmPermissionAsked: false,
        calendarPermissionAsked: false,
        googleConnected: false,
        hasSavedPreferences: false
    )

    func testFreshInstallIsNew() {
        XCTAssertFalse(TutorialEligibility.isReturningUser(fresh))
    }

    func testAnySignalMarksReturningUser() {
        var alarm = fresh
        alarm.alarmPermissionAsked = true
        var calendar = fresh
        calendar.calendarPermissionAsked = true
        var google = fresh
        google.googleConnected = true
        var prefs = fresh
        prefs.hasSavedPreferences = true

        for signals in [alarm, calendar, google, prefs] {
            XCTAssertTrue(TutorialEligibility.isReturningUser(signals), "\(signals)")
        }
    }
}
