//
//  GoogleCalendarAPIClient.swift
//  Calarm
//

import Foundation

struct GoogleCalendarEventsPage: Sendable {
    let events: [GoogleCalendarEvent]
    let nextSyncToken: String?
}

struct GoogleCalendarAPIClient: Sendable {
    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter
    private let dateOnlyFormatter: DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        self.dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
    }

    func listCalendars(accessToken: String) async throws -> [GoogleCalendarListEntry] {
        let response: GoogleCalendarListResponse = try await get(
            path: "/calendar/v3/users/me/calendarList",
            query: [],
            accessToken: accessToken
        )
        return response.items ?? []
    }

    /// Bounded window fetch for CALarm's alarm horizon.
    func listEvents(
        calendarID: String,
        accessToken: String,
        timeMin: Date,
        timeMax: Date
    ) async throws -> GoogleCalendarEventsPage {
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        var query = baseEventQuery(timeMin: timeMin, timeMax: timeMax)
        query.append(("singleEvents", "true"))
        query.append(("orderBy", "startTime"))

        return try await paginateEvents(
            path: "/calendar/v3/calendars/\(encodedCalendarID)/events",
            query: query,
            accessToken: accessToken
        )
    }

    /// Delta fetch since the last successful sync check.
    func listUpdatedEvents(
        calendarID: String,
        accessToken: String,
        updatedMin: Date,
        timeMin: Date,
        timeMax: Date
    ) async throws -> GoogleCalendarEventsPage {
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        var query = baseEventQuery(timeMin: timeMin, timeMax: timeMax)
        query.append(("singleEvents", "true"))
        query.append(("orderBy", "updated"))
        query.append(("updatedMin", rfc3339(updatedMin)))

        return try await paginateEvents(
            path: "/calendar/v3/calendars/\(encodedCalendarID)/events",
            query: query,
            accessToken: accessToken
        )
    }

    /// Incremental sync using a stored sync token (Tier 2 / reconnect path).
    func listIncrementalEvents(
        calendarID: String,
        accessToken: String,
        syncToken: String
    ) async throws -> (events: [GoogleCalendarEvent], nextSyncToken: String?) {
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        var query: [(String, String)] = [
            ("syncToken", syncToken),
            ("singleEvents", "true"),
        ]

        var allItems: [GoogleCalendarEvent] = []
        var nextSyncToken: String?
        var pageToken: String?

        repeat {
            var pageQuery = query
            if let pageToken {
                pageQuery.append(("pageToken", pageToken))
            }
            let response: GoogleEventsListResponse = try await get(
                path: "/calendar/v3/calendars/\(encodedCalendarID)/events",
                query: pageQuery,
                accessToken: accessToken
            )
            allItems.append(contentsOf: response.items ?? [])
            pageToken = response.nextPageToken
            nextSyncToken = response.nextSyncToken ?? nextSyncToken
        } while pageToken != nil

        return (allItems, nextSyncToken)
    }

    func parseEventDates(_ event: GoogleCalendarEvent) -> (start: Date, end: Date)? {
        guard let start = parseDateTime(event.start), let end = parseDateTime(event.end) else {
            return nil
        }
        return (start, end)
    }

    // MARK: - Private

    private func baseEventQuery(timeMin: Date, timeMax: Date) -> [(String, String)] {
        [
            ("timeMin", rfc3339(timeMin)),
            ("timeMax", rfc3339(timeMax)),
            ("maxResults", "250"),
            ("showDeleted", "true"),
        ]
    }

    private func paginateEvents(
        path: String,
        query: [(String, String)],
        accessToken: String
    ) async throws -> GoogleCalendarEventsPage {
        var allItems: [GoogleCalendarEvent] = []
        var pageToken: String?
        var pageCount = 0
        var nextSyncToken: String?

        repeat {
            var pageQuery = query
            if let pageToken {
                pageQuery.append(("pageToken", pageToken))
            }
            let response: GoogleEventsListResponse = try await get(
                path: path,
                query: pageQuery,
                accessToken: accessToken
            )
            allItems.append(contentsOf: response.items ?? [])
            pageToken = response.nextPageToken
            if let token = response.nextSyncToken {
                nextSyncToken = token
            }
            pageCount += 1
        } while pageToken != nil && pageCount < 20

        return GoogleCalendarEventsPage(events: allItems, nextSyncToken: nextSyncToken)
    }

    private func get<T: Decodable>(
        path: String,
        query: [(String, String)],
        accessToken: String
    ) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else { throw GoogleCalendarAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarAPIError.invalidResponse
        }

        if http.statusCode == 410 {
            throw GoogleCalendarAPIError.syncTokenExpired
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleCalendarAPIError.http(status: http.statusCode, message: message)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func rfc3339(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private func parseDateTime(_ value: GoogleEventDateTime?) -> Date? {
        guard let value else { return nil }
        if let dateTime = value.dateTime {
            if let parsed = isoFormatter.date(from: dateTime) { return parsed }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            return fallback.date(from: dateTime)
        }
        if let date = value.date {
            return dateOnlyFormatter.date(from: date)
        }
        return nil
    }
}
