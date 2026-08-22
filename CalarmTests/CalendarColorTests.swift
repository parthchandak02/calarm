import CoreGraphics
import XCTest
@testable import Calarm

final class CalendarColorTests: XCTestCase {
    func testHexStringFromRGBComponents() {
        let color = CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
        XCTAssertEqual(CalendarColor.hexString(from: color), "#FF8000")
    }

    func testColorFromHexRoundTrip() {
        let hex = "#3366CC"
        let swiftColor = CalendarColor.color(fromHex: hex)
        XCTAssertNotNil(swiftColor)
    }

    func testInvalidHexReturnsNil() {
        XCTAssertNil(CalendarColor.color(fromHex: "not-a-color"))
    }
}
