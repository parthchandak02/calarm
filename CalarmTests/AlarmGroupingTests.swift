//
//  AlarmGroupingTests.swift
//  CalarmTests
//

import XCTest
@testable import Calarm

final class AlarmGroupingTests: XCTestCase {
    private let nine = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 60))

    private func member(_ id: String, _ title: String, fire: Date, busy: Bool = false, offset: String = "oneMinute") -> AlarmGrouping.Member {
        AlarmGrouping.Member(
            occurrenceID: id,
            offsetRawValue: offset,
            fireDate: fire,
            title: title,
            startDate: fire.addingTimeInterval(60),
            isBusyOnly: busy
        )
    }

    func testSameMinuteRingsOnce() {
        let groups = AlarmGrouping.groups([
            member("busy", "Busy", fire: nine, busy: true),
            member("ai", "AI Assembly", fire: nine)
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].primary.occurrenceID, "ai")
        XCTAssertEqual(groups[0].title, "AI Assembly + 1 more")
    }

    func testDifferentMinutesRingSeparately() {
        let groups = AlarmGrouping.groups([
            member("flight", "Flight", fire: nine.addingTimeInterval(180)),
            member("drill", "Drilling", fire: nine)
        ])
        XCTAssertEqual(groups.map(\.primary.occurrenceID), ["drill", "flight"])
        XCTAssertEqual(groups.map(\.title), ["Drilling", "Flight"])
    }

    func testTwoOffsetsOfOneEventCountOnce() {
        let groups = AlarmGrouping.groups([
            member("a", "Standup", fire: nine, offset: "oneMinute"),
            member("a", "Standup", fire: nine, offset: "atEventTime")
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Standup")
    }

    func testPrimaryIsDeterministic() {
        let members = [member("b", "Beta", fire: nine), member("a", "Alpha", fire: nine)]
        XCTAssertEqual(AlarmGrouping.groups(members), AlarmGrouping.groups(members.reversed()))
    }
}
