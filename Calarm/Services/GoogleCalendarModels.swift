//
//  GoogleCalendarModels.swift
//  Calarm
//

import Foundation

// Every type in this file is `nonisolated`, and that is a correctness fix rather than
// tidying. The target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which isolates
// these DTOs -- and their `Decodable` conformances -- to the main actor. Decoding a
// network response is not main-actor work, and under the Swift 6 language mode the
// isolated conformance stops being a warning and becomes an error at every call site
// that decodes off the main thread.

nonisolated struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendarListEntry]?
    let nextSyncToken: String?
}

nonisolated struct GoogleCalendarListEntry: Decodable, Identifiable, Equatable {
    let id: String
    let summary: String?
    let primary: Bool?
    let accessRole: String?
    let selected: Bool?

    var title: String {
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }

    var isBusyOnly: Bool {
        accessRole == "freeBusyReader"
    }
}

nonisolated struct GoogleEventsListResponse: Decodable {
    let items: [GoogleCalendarEvent]?
    let nextPageToken: String?
    let nextSyncToken: String?
}

nonisolated struct GoogleCalendarEvent: Decodable {
    let id: String?
    let status: String?
    let summary: String?
    let location: String?
    let updated: String?
    let created: String?
    let start: GoogleEventDateTime?
    let end: GoogleEventDateTime?
    let recurringEventId: String?
    /// Google's own event category: `default`, `focusTime`, `outOfOffice`,
    /// `workingLocation`, `birthday` or `fromGmail`.
    ///
    /// Read-only and immutable after creation. EventKit has no equivalent, so this is
    /// the one classification signal the Google path gets and the EventKit path cannot.
    let eventType: String?

    var isCancelled: Bool { status == "cancelled" }

    var isAllDay: Bool {
        guard let start else { return true }
        return start.dateTime == nil && start.date != nil
    }

    /// Event categories that must never produce an alarm.
    ///
    /// A focus block exists to not be interrupted; alarming for one is the exact opposite
    /// of what the user asked for, and it is the loudest thing an iOS app can do. Out of
    /// office and working location are informational and have no start you need waking
    /// for. Birthdays are all-day and already filtered, but named here so the intent is
    /// explicit rather than incidental.
    ///
    /// This matters more here than it would in most calendars: the owner runs an Apps
    /// Script that converts every solo event into `focusTime`, so these are not rare.
    ///
    /// `fromGmail` is deliberately absent. A flight or restaurant booking auto-extracted
    /// from mail is exactly the kind of thing worth an alarm.
    static let nonAlertingEventTypes: Set<String> = [
        "focusTime",
        "outOfOffice",
        "workingLocation",
        "birthday"
    ]

    /// Unknown or absent `eventType` is treated as alertable.
    ///
    /// Deliberately fail-open. Google adds event types over time, and a new one being
    /// silently swallowed would mean a missed meeting, which is this app's worst outcome.
    /// An extra alarm is merely annoying.
    var isAlertableEventType: Bool {
        guard let eventType else { return true }
        return !Self.nonAlertingEventTypes.contains(eventType)
    }
}

nonisolated struct GoogleEventDateTime: Decodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}

nonisolated struct GoogleCalendarFetchedEvent: Equatable, Sendable {
    let googleEventID: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let calendarID: String
    let calendarTitle: String
    let isBusyOnly: Bool
    let occurrenceID: String

    static func occurrenceID(googleEventID: String, startDate: Date) -> String {
        EventOccurrenceID(eventIdentifier: "google.\(googleEventID)", startDate: startDate).rawValue
    }
}

enum GoogleCalendarAPIError: LocalizedError {
    case notConfigured
    case notSignedIn
    case invalidResponse
    case http(status: Int, message: String)
    case syncTokenExpired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Google Calendar is not configured. Add GoogleService-Info.plist."
        case .notSignedIn:
            "Sign in to Google Calendar first."
        case .invalidResponse:
            "Unexpected response from Google Calendar."
        case .http(let status, _):
            Self.userFacingMessage(forHTTPStatus: status)
        case .syncTokenExpired:
            "Google Calendar sync token expired."
        }
    }

    private static func userFacingMessage(forHTTPStatus status: Int) -> String {
        switch status {
        case 401:
            "Your Google sign-in expired. Sign in again."
        case 403:
            "Google Calendar access was denied. Check permissions and try again."
        case 404:
            "Google Calendar could not be found."
        case 408, 504:
            "Google Calendar took too long to respond. Try again."
        case 429:
            "Too many requests to Google Calendar. Try again later."
        case 500 ... 599:
            "Google Calendar is temporarily unavailable. Try again later."
        default:
            "Could not reach Google Calendar. Try again."
        }
    }
}
