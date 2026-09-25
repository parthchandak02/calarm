import XCTest
@testable import Calarm

final class ActivityLogTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func entry(_ kind: ActivityLog.Kind, _ text: String, ago seconds: TimeInterval) -> ActivityLog.Entry {
        ActivityLog.Entry(date: now.addingTimeInterval(-seconds), kind: kind, text: text)
    }

    func testRepeatWithinWindowReplacesNewestEntry() {
        let first = entry(.resched, "11 alarms", ago: 300)
        let repeatEntry = entry(.resched, "11 alarms", ago: 0)
        XCTAssertEqual(ActivityLog.appending(repeatEntry, to: [first]), [repeatEntry])
    }

    func testDifferentTextStacks() {
        let first = entry(.resched, "11 alarms", ago: 300)
        let second = entry(.resched, "12 alarms", ago: 0)
        XCTAssertEqual(ActivityLog.appending(second, to: [first]).count, 2)
    }

    func testEntriesOlderThanSevenDaysArePruned() {
        let old = entry(.sync, "google 3", ago: 8 * 86_400)
        let fresh = entry(.rang, "Standup", ago: 0)
        XCTAssertEqual(ActivityLog.appending(fresh, to: [old]), [fresh])
    }

    func testDaysAreNewestFirstAndGrouped() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let entries = [
            entry(.rang, "Yesterday alarm", ago: 86_400),
            entry(.sync, "older today", ago: 60),
            entry(.rang, "newest", ago: 0),
        ]
        let days = ActivityLog.days(entries, now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.title), ["Today", "Yesterday"])
        XCTAssertEqual(days.first?.entries.map(\.text), ["newest", "older today"])
    }
}
