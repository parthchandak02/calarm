import XCTest
@testable import Calarm

final class FlapLayoutTests: XCTestCase {
    func testUnderAnHourIsMinutesAndSeconds() {
        XCTAssertEqual(FlapLayout.groups(remaining: 45 * 60 + 7).map(\.digits), [2, 2])
        XCTAssertEqual(FlapLayout.groups(remaining: 5 * 60 + 7).map(\.digits), [1, 2])
    }

    func testHoursAreNotZeroPadded() {
        XCTAssertEqual(FlapLayout.groups(remaining: 2 * 3_600 + 300).map(\.digits), [1, 2, 2])
        XCTAssertEqual(FlapLayout.groups(remaining: 14 * 3_600).map(\.digits), [2, 2, 2])
        XCTAssertEqual(FlapLayout.groups(remaining: 30 * 3_600).map(\.unit), ["HRS", "MIN", "SEC"])
    }

    func testCellsPutColonsBetweenGroups() {
        XCTAssertEqual(
            FlapLayout.cells(for: FlapLayout.groups(remaining: 3_700)),
            [.digit, .colon, .digit, .digit, .colon, .digit, .digit]
        )
    }
}
