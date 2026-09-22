//
//  EventOccurrenceID.swift
//  CalarmShared
//

import Foundation

/// Stable identity for one calendar event occurrence (recurring series instances are distinct).
///
/// `nonisolated` because this is a pure value type that identity-related code needs from
/// every context: the app, the widget extension, background decode of a network response,
/// and the test target. The target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would
/// otherwise isolate it to the main actor, which makes `rawValue` unreachable from a
/// nonisolated caller -- a warning today, an error under the Swift 6 language mode.
nonisolated struct EventOccurrenceID: Hashable, Codable, Sendable {
    let eventIdentifier: String
    let startTimestamp: TimeInterval

    var rawValue: String {
        "\(eventIdentifier)_\(startTimestamp)"
    }

    var startDate: Date {
        Date(timeIntervalSince1970: startTimestamp)
    }

    init(eventIdentifier: String, startDate: Date) {
        self.eventIdentifier = eventIdentifier
        self.startTimestamp = startDate.timeIntervalSince1970
    }

    init?(rawValue: String) {
        guard let separator = rawValue.lastIndex(of: "_") else {
            return nil
        }
        let identifier = String(rawValue[..<separator])
        let timestampString = String(rawValue[rawValue.index(after: separator)...])
        guard !identifier.isEmpty, let timestamp = TimeInterval(timestampString) else {
            return nil
        }
        self.eventIdentifier = identifier
        self.startTimestamp = timestamp
    }

    /// True when the string is a bare EventKit identifier (pre-occurrence migration).
    static func isLegacyBareIdentifier(_ key: String) -> Bool {
        EventOccurrenceID(rawValue: key) == nil && !key.isEmpty
    }
}
