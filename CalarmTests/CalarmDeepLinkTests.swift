import XCTest

final class CalarmDeepLinkTests: XCTestCase {
    func testOccurrenceURLWithStart() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try XCTUnwrap(CalarmDeepLink.eventURL(eventIdentifier: "evt1", startDate: start))
        let route = try XCTUnwrap(CalarmDeepLink.eventRoute(from: url))
        XCTAssertEqual(route.legacyEventIdentifier, "evt1")
        XCTAssertEqual(route.startTimestamp, start.timeIntervalSince1970)
        XCTAssertTrue(route.occurrenceID.hasPrefix("evt1_"))
    }

    func testLegacyIDOnlyURL() throws {
        let url = try XCTUnwrap(URL(string: "calarm://event?id=legacy-only"))
        let route = try XCTUnwrap(CalarmDeepLink.eventRoute(from: url))
        XCTAssertEqual(route.occurrenceID, "legacy-only")
    }
}
