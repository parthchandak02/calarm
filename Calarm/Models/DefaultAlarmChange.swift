//
//  DefaultAlarmChange.swift
//  Calarm
//

import Foundation

/// The offer made after the default alarm changes: events armed earlier keep their own
/// time, so a new default alone left meetings ringing at an old one.
enum DefaultAlarmChange {
    struct Offer: Equatable {
        let offset: AlarmOffsetOption
        let eventCount: Int
    }

    /// Upcoming armed events whose alarms are not already just `offset`. Nothing for "No
    /// alarm": the offer only ever changes when an event rings, never whether it does.
    static func eventIDsToAlign(_ events: [ScheduleEvent], to offset: AlarmOffsetOption) -> Set<String> {
        guard offset.isSchedulable else { return [] }
        return Set(events.filter { $0.alarmEnabled && $0.isEventUpcoming && $0.alarmOffsets != [offset] }.map(\.id))
    }
}
