//
//  AlarmSchedulingHelpers.swift
//  CalarmShared
//

import CryptoKit
import Foundation

enum AlarmSchedulingHelpers {
    static func stableAlarmID(occurrenceID: String, offsetRawValue: String) -> UUID {
        let digest = SHA256.hash(data: Data("calarm.\(occurrenceID).\(offsetRawValue)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func liveActivityKey(occurrenceID: String, offsetRawValue: String) -> String {
        "\(occurrenceID).\(offsetRawValue)"
    }

    /// Stagger alarms that share the same fire date by 2s per index (deterministic).
    static func staggeredFireDate(base: Date, collisionIndex: Int) -> Date {
        guard collisionIndex > 0 else { return base }
        return base.addingTimeInterval(TimeInterval(collisionIndex * 2))
    }

    /// Stable fingerprint of desired AlarmKit schedules (occurrence, offset, fire time, snooze).
    static func schedulingFingerprint(
        instances: [(occurrenceID: String, offsetRawValue: String, fireDate: Date)],
        nextLiveActivityKey: String?,
        snoozeRawValue: String
    ) -> String {
        let rows = instances.map {
            "\($0.occurrenceID).\($0.offsetRawValue).\(Int($0.fireDate.timeIntervalSince1970))"
        }.sorted()
        return (rows + ["la:\(nextLiveActivityKey ?? "none")", "snooze:\(snoozeRawValue)"]).joined(separator: "|")
    }

    static func collisionGroupsSortedByFireDate(
        instances: [(occurrenceID: String, offsetRawValue: String, fireDate: Date)]
    ) -> [(occurrenceID: String, offsetRawValue: String, fireDate: Date)] {
        let sorted = instances.sorted { $0.fireDate < $1.fireDate }
        var counts: [TimeInterval: Int] = [:]
        return sorted.map { item in
            let key = item.fireDate.timeIntervalSince1970
            let index = counts[key, default: 0]
            counts[key] = index + 1
            let adjusted = staggeredFireDate(base: item.fireDate, collisionIndex: index)
            return (item.occurrenceID, item.offsetRawValue, adjusted)
        }
    }
}
