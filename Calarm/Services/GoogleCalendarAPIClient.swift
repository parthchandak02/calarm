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

    /// The one call that mints a `syncToken`, and the only one whose parameters the
    /// incremental call can match.
    ///
    /// Three of these choices are load-bearing and were wrong before:
    ///
    /// - **No `timeMax`.** `timeMax` is forbidden on a request carrying a `syncToken`,
    ///   and Google requires every other parameter to match the initial sync. A token
    ///   minted from a bounded window can therefore never be used, and worse, the window
    ///   is an absolute date: deltas would never mention an event scheduled past it.
    /// - **No `orderBy`.** Also forbidden alongside `syncToken`, same consequence.
    /// - **`singleEvents=false`.** With `true` and no `timeMax`, Google expands every
    ///   recurrence for all time, so one daily standup becomes thousands of rows. Parents
    ///   only here; expansion happens in `listEvents` where the window is bounded.
    ///
    /// `timeMin` *is* allowed and does not suppress the token. Google's own sync guide
    /// passes it. The token is only ever omitted when `nextPageToken` is present, which
    /// `paginateEvents` handles by following to the last page.
    func listFullSyncEvents(
        calendarID: String,
        accessToken: String,
        timeMin: Date
    ) async throws -> GoogleCalendarEventsPage {
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        return try await paginateEvents(
            path: "/calendar/v3/calendars/\(encodedCalendarID)/events",
            query: Self.syncParameters,
            accessToken: accessToken,
            extraQuery: [("timeMin", rfc3339(timeMin))]
        )
    }

    /// Incremental sync using a stored sync token (Tier 2 / reconnect path).
    func listIncrementalEvents(
        calendarID: String,
        accessToken: String,
        syncToken: String
    ) async throws -> (events: [GoogleCalendarEvent], nextSyncToken: String?) {
        let encodedCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        // Same parameter set as listFullSyncEvents, minus timeMin. Google: "All other
        // query parameters should be the same as for the initial synchronization to
        // avoid undefined behavior." A mismatch here is not an error you will see, it is
        // a delta you quietly cannot trust.
        let query: [(String, String)] = [("syncToken", syncToken)] + Self.syncParameters

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

    /// The parameter set shared by the full sync and every incremental sync after it.
    /// Deliberately excludes anything forbidden alongside `syncToken`.
    private static let syncParameters: [(String, String)] = [
        ("singleEvents", "false"),
        ("showDeleted", "true"),
        ("maxResults", "2500"),
    ]

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
        accessToken: String,
        extraQuery: [(String, String)] = []
    ) async throws -> GoogleCalendarEventsPage {
        let query = query + extraQuery
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
        // `percentEncodedPath`, not `path`. Callers percent-encode the calendar ID
        // before interpolating it, and the `path` setter then escapes the `%` itself, so
        // `team%20room` went out as `team%2520room` and asked Google for a calendar that
        // does not exist. It only bites IDs containing characters outside
        // `.urlPathAllowed` -- which includes every Google holiday calendar, since those
        // are named like `en.usa#holiday@group.v.calendar.google.com`.
        components.percentEncodedPath = path
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
