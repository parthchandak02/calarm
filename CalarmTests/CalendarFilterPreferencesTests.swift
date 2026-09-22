import XCTest
@testable import Calarm

final class CalendarFilterPreferencesTests: XCTestCase {
    @MainActor
    override func setUp() {
        super.setUp()
        CalarmPersistence.remove(forKey: CalarmPersistence.Key.enabledCalendarIDs)
        CalarmPersistence.remove(forKey: CalarmPersistence.Key.disabledCalendarIDs)
    }

    @MainActor
    override func tearDown() {
        CalarmPersistence.remove(forKey: CalarmPersistence.Key.enabledCalendarIDs)
        CalarmPersistence.remove(forKey: CalarmPersistence.Key.disabledCalendarIDs)
        super.tearDown()
    }

    @MainActor
    func testUnknownCalendarIsEnabledByDefault() {
        XCTAssertTrue(CalendarFilterPreferences.isEnabled(calendarID: "brand-new"))
    }

    @MainActor
    func testDisablingOnlyAffectsThatCalendar() {
        CalendarFilterPreferences.setEnabled(false, calendarID: "work")
        XCTAssertFalse(CalendarFilterPreferences.isEnabled(calendarID: "work"))
        XCTAssertTrue(CalendarFilterPreferences.isEnabled(calendarID: "home"))

        CalendarFilterPreferences.setEnabled(true, calendarID: "work")
        XCTAssertTrue(CalendarFilterPreferences.isEnabled(calendarID: "work"))
        XCTAssertTrue(CalendarFilterPreferences.disabledCalendarIDs.isEmpty)
    }

    @MainActor
    func testAllowListMigratesToTheComplementaryDenyList() {
        CalarmPersistence.encode(["a", "b"], forKey: CalarmPersistence.Key.enabledCalendarIDs)

        CalendarFilterPreferences.migrateAllowListIfNeeded(allCalendarIDs: ["a", "b", "c", "d"])

        XCTAssertEqual(CalendarFilterPreferences.disabledCalendarIDs, ["c", "d"])
        XCTAssertFalse(CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.enabledCalendarIDs))
    }

    @MainActor
    func testCalendarAddedAfterMigrationStaysVisible() {
        CalarmPersistence.encode(["a"], forKey: CalarmPersistence.Key.enabledCalendarIDs)
        CalendarFilterPreferences.migrateAllowListIfNeeded(allCalendarIDs: ["a", "b"])

        XCTAssertTrue(CalendarFilterPreferences.isEnabled(calendarID: "c"))
    }

    @MainActor
    func testMigrationWaitsForARealCalendarList() {
        CalarmPersistence.encode(["a"], forKey: CalarmPersistence.Key.enabledCalendarIDs)

        CalendarFilterPreferences.migrateAllowListIfNeeded(allCalendarIDs: [])

        XCTAssertTrue(CalendarFilterPreferences.disabledCalendarIDs.isEmpty)
        XCTAssertTrue(CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.enabledCalendarIDs))
    }

    @MainActor
    func testEmptyAllowListMeantEverythingAndMigratesToNothingDisabled() {
        CalarmPersistence.encode([String](), forKey: CalarmPersistence.Key.enabledCalendarIDs)

        CalendarFilterPreferences.migrateAllowListIfNeeded(allCalendarIDs: ["a", "b"])

        XCTAssertTrue(CalendarFilterPreferences.disabledCalendarIDs.isEmpty)
        XCTAssertFalse(CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.enabledCalendarIDs))
    }
}
