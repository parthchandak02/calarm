//
//  GoogleCalendarModels.swift
//  Calarm
//

import Foundation

struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendarListEntry]?
    let nextSyncToken: String?
}

struct GoogleCalendarListEntry: Decodable, Identifiable, Equatable {
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

struct GoogleEventsListResponse: Decodable {
    let items: [GoogleCalendarEvent]?
    let nextPageToken: String?
    let nextSyncToken: String?
}

struct GoogleCalendarEvent: Decodable {
    let id: String?
    let status: String?
    let summary: String?
    let location: String?
    let updated: String?
    let start: GoogleEventDateTime?
    let end: GoogleEventDateTime?
    let recurringEventId: String?

    var isCancelled: Bool { status == "cancelled" }

    var isAllDay: Bool {
        guard let start else { return true }
        return start.dateTime == nil && start.date != nil
    }
}

struct GoogleEventDateTime: Decodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}

struct GoogleCalendarFetchedEvent: Equatable, Sendable {
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
        case .http(let status, let message):
            "Google Calendar error (\(status)): \(message)"
        case .syncTokenExpired:
            "Google Calendar sync token expired."
        }
    }
}
