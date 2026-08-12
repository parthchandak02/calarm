import XCTest

final class EventOccurrenceIDTests: XCTestCase {
    func testRawValueRoundTrip() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let id = EventOccurrenceID(eventIdentifier: "ABC-123", startDate: start)
        XCTAssertEqual(id.rawValue, "ABC-123_1700000000.0")
        let parsed = EventOccurrenceID(rawValue: id.rawValue)
        XCTAssertEqual(parsed?.eventIdentifier, "ABC-123")
        XCTAssertEqual(parsed?.startTimestamp, start.timeIntervalSince1970)
    }

    func testLegacyBareIdentifierDetection() {
        XCTAssertTrue(EventOccurrenceID.isLegacyBareIdentifier("series-id-only"))
        XCTAssertFalse(EventOccurrenceID.isLegacyBareIdentifier("series-id-only_1700000000.0"))
    }
}
