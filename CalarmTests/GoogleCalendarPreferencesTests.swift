import XCTest
@testable import Calarm

@MainActor
final class GoogleCalendarPreferencesTests: XCTestCase {
    private let enabledKey = "calarm.google.enabledCalendarIDs"
    private let disabledKey = "calarm.google.disabledCalendarIDs"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: disabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: disabledKey)
        super.tearDown()
    }

    func testUnknownCalendarIsEnabled() {
        XCTAssertTrue(GoogleCalendarPreferences().isCalendarEnabled("new@group.calendar.google.com"))
    }

    func testSwitchingOffAndBackOn() {
        let preferences = GoogleCalendarPreferences()
        preferences.setCalendarEnabled("a", enabled: false)
        XCTAssertFalse(preferences.isCalendarEnabled("a"))
        XCTAssertTrue(preferences.isCalendarEnabled("b"))
        preferences.setCalendarEnabled("a", enabled: true)
        XCTAssertTrue(preferences.isCalendarEnabled("a"))
    }

    func testAllowListMigratesToDenyList() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(["a"]), forKey: enabledKey)
        let preferences = GoogleCalendarPreferences()
        preferences.migrateAllowListIfNeeded(allCalendarIDs: ["a", "b"])
        XCTAssertTrue(preferences.isCalendarEnabled("a"))
        XCTAssertFalse(preferences.isCalendarEnabled("b"))
        XCTAssertTrue(preferences.isCalendarEnabled("subscribed-later"))
        XCTAssertNil(UserDefaults.standard.object(forKey: enabledKey))
    }

    func testMigrationWaitsForARealCalendarList() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(["a"]), forKey: enabledKey)
        let preferences = GoogleCalendarPreferences()
        preferences.migrateAllowListIfNeeded(allCalendarIDs: [])
        XCTAssertTrue(preferences.isCalendarEnabled("b"))
        XCTAssertNotNil(UserDefaults.standard.object(forKey: enabledKey))
    }
}
