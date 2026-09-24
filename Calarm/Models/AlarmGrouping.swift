//
//  AlarmGrouping.swift
//  Calarm
//

import Foundation

/// Alarms that fire in the same minute ring once. The same meeting often arrives through
/// several calendars under different titles ("Busy" from a free/busy share, a flight from
/// both Flighty and Gmail), which no title match can pair up; one ring per minute makes
/// that harmless without hiding any event.
nonisolated enum AlarmGrouping {
    struct Member: Equatable {
        let occurrenceID: String
        let offsetRawValue: String
        let fireDate: Date
        let title: String
        let startDate: Date
        let isBusyOnly: Bool
    }

    struct Group: Equatable {
        /// The member whose alarm ID carries the group; titled events lead busy blocks.
        let primary: Member
        let members: [Member]
        let fireDate: Date
        let title: String
    }

    static func groups(_ members: [Member]) -> [Group] {
        Dictionary(grouping: members) { Int(($0.fireDate.timeIntervalSince1970 / 60).rounded(.down)) }
            .values
            .map { bucket in
                let ordered = bucket.sorted(by: leads)
                return Group(
                    primary: ordered[0],
                    members: ordered,
                    fireDate: bucket.map(\.fireDate).min() ?? ordered[0].fireDate,
                    title: title(for: ordered)
                )
            }
            .sorted { $0.fireDate < $1.fireDate }
    }

    static func title(for ordered: [Member]) -> String {
        guard let first = ordered.first else { return "" }
        let others = Set(ordered.map(\.occurrenceID)).subtracting([first.occurrenceID]).count
        return others == 0 ? first.title : "\(first.title) + \(others) more"
    }

    private static func leads(_ lhs: Member, _ rhs: Member) -> Bool {
        if lhs.isBusyOnly != rhs.isBusyOnly { return !lhs.isBusyOnly }
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        if lhs.occurrenceID != rhs.occurrenceID { return lhs.occurrenceID < rhs.occurrenceID }
        return lhs.offsetRawValue < rhs.offsetRawValue
    }
}
