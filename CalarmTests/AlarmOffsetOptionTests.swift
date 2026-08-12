import XCTest
@testable import Calarm

final class AlarmOffsetOptionTests: XCTestCase {
    func testEnablingFallbackFromNoAlarm() {
        XCTAssertEqual(AlarmOffsetOption.noAlarm.enablingFallback, .tenMinutes)
    }

    func testRecommendedFetchDaysAtLeastSeven() {
        XCTAssertGreaterThanOrEqual(AlarmOffsetOption.recommendedCalendarFetchDays, 7)
    }
}
