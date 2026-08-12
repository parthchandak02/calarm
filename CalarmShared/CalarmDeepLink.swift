//
//  CalarmDeepLink.swift
//  CalarmShared
//

import Foundation

enum CalarmDeepLink {
    static let scheme = "calarm"
    static let eventHost = "event"
    static let eventIDQueryItem = "id"
    static let startQueryItem = "start"

    struct EventRoute: Equatable {
        let occurrenceID: String
        let legacyEventIdentifier: String?
        let startTimestamp: TimeInterval?

        init(occurrenceID: String, legacyEventIdentifier: String? = nil, startTimestamp: TimeInterval? = nil) {
            self.occurrenceID = occurrenceID
            self.legacyEventIdentifier = legacyEventIdentifier
            self.startTimestamp = startTimestamp
        }
    }

    static func eventURL(occurrenceID: String) -> URL? {
        guard !occurrenceID.isEmpty else { return nil }
        if let parsed = EventOccurrenceID(rawValue: occurrenceID) {
            return eventURL(eventIdentifier: parsed.eventIdentifier, startDate: parsed.startDate)
        }
        return eventURL(eventIdentifier: occurrenceID, startDate: nil)
    }

    static func eventURL(eventIdentifier: String, startDate: Date?) -> URL? {
        guard !eventIdentifier.isEmpty else { return nil }
        var items = [URLQueryItem(name: eventIDQueryItem, value: eventIdentifier)]
        if let startDate {
            items.append(URLQueryItem(name: startQueryItem, value: String(startDate.timeIntervalSince1970)))
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = eventHost
        components.queryItems = items
        return components.url
    }

    static func eventRoute(from url: URL) -> EventRoute? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == eventHost else {
            return nil
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let eventIdentifier = queryItems.first(where: { $0.name == eventIDQueryItem })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let startValue = queryItems.first(where: { $0.name == startQueryItem })?.value
        let startTimestamp = startValue.flatMap(TimeInterval.init)

        if let eventIdentifier, !eventIdentifier.isEmpty {
            if let startTimestamp {
                let occurrence = EventOccurrenceID(eventIdentifier: eventIdentifier, startDate: Date(timeIntervalSince1970: startTimestamp))
                return EventRoute(occurrenceID: occurrence.rawValue, legacyEventIdentifier: eventIdentifier, startTimestamp: startTimestamp)
            }
            if let parsed = EventOccurrenceID(rawValue: eventIdentifier) {
                return EventRoute(occurrenceID: parsed.rawValue, legacyEventIdentifier: parsed.eventIdentifier, startTimestamp: parsed.startTimestamp)
            }
            return EventRoute(occurrenceID: eventIdentifier, legacyEventIdentifier: eventIdentifier, startTimestamp: nil)
        }

        let pathID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !pathID.isEmpty else { return nil }
        return EventRoute(occurrenceID: pathID, legacyEventIdentifier: pathID, startTimestamp: nil)
    }

    /// Backward-compatible single-string ID for pending deep link storage.
    static func occurrenceID(from url: URL) -> String? {
        eventRoute(from: url)?.occurrenceID
    }
}
