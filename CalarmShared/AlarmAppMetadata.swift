//
//  AlarmAppMetadata.swift
//  CalarmShared
//

import AlarmKit
import Foundation

nonisolated struct AlarmAppMetadata: AlarmMetadata, Sendable, Codable {
    let title: String
    let offsetLabel: String?
    /// Full occurrence ID (`eventIdentifier_startTimestamp`) for deep links.
    let eventID: String?
    let accentRawValue: String?

    nonisolated init(
        title: String = "Alarm",
        offsetLabel: String? = nil,
        eventID: String? = nil,
        accentRawValue: String? = nil
    ) {
        self.title = title
        self.offsetLabel = offsetLabel
        self.eventID = eventID
        self.accentRawValue = accentRawValue
    }
}
