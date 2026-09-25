//
//  GoogleCalendarService.swift
//  Calarm
//

import Combine
import Foundation
import UIKit

@MainActor
final class GoogleCalendarService: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var availableCalendars: [GoogleCalendarListEntry] = []
    @Published private(set) var lastSyncError: String?

    let authManager = GoogleAuthManager()
    private let api = GoogleCalendarAPIClient()
    private var preferences = GoogleCalendarPreferences()

    var isConnected: Bool { preferences.isConnected && authManager.isSignedIn }
    var connectedEmail: String? { preferences.connectedEmail ?? authManager.userEmail }

    init() {
        authManager.configure()
        if authManager.isSignedIn, preferences.connectedEmail == nil {
            preferences.connectedEmail = authManager.userEmail
        }
    }

    func connect(presenting viewController: UIViewController) async throws {
        try await authManager.signIn(presenting: viewController)
        preferences.connectedEmail = authManager.userEmail
        preferences.lastSyncCheck = nil
        preferences.clearSyncTokens()
        try await refreshCalendarList()
    }

    func disconnect() {
        authManager.signOut()
        preferences.disconnect()
        availableCalendars = []
        lastSyncError = nil
    }

    func clearLastSyncError() {
        lastSyncError = nil
    }

    func refreshCalendarList() async throws {
        guard authManager.isSignedIn else { throw GoogleCalendarAPIError.notSignedIn }
        isLoading = true
        defer { isLoading = false }

        let token = try await authManager.accessToken()
        availableCalendars = try await api.listCalendars(accessToken: token)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        preferences.migrateAllowListIfNeeded(allCalendarIDs: availableCalendars.map(\.id))
    }

    func setCalendarEnabled(_ calendarID: String, enabled: Bool) {
        preferences.setCalendarEnabled(calendarID, enabled: enabled)
    }

    func isCalendarEnabled(_ calendarID: String) -> Bool {
        preferences.isCalendarEnabled(calendarID)
    }

    /// Fetch upcoming events across enabled Google calendars for the alarm horizon.
    /// On failure, returns `cachedEvents` so callers can keep last-known-good schedule data.
    func fetchUpcomingEvents(
        days: Int,
        cachedEvents: [GoogleCalendarFetchedEvent] = []
    ) async -> [GoogleCalendarFetchedEvent] {
        guard isConnected else { return [] }

        isLoading = true
        defer { isLoading = false }

        do {
            if availableCalendars.isEmpty {
                try await refreshCalendarList()
            }
            let token = try await authManager.accessToken()
            let now = Date()
            let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now

            // Step 1: ask each calendar whether anything changed, as cheaply as possible.
            //
            // This used to do a full window fetch AND an incremental fetch on every
            // sync, which is strictly more work than either alone: the incremental
            // could only ever return what the full fetch had already returned. Now the
            // incremental is what it should be, a change detector, and the expensive
            // expanded fetch in step 2 runs only when it reports something.
            var needsWindowFetch = cachedEvents.isEmpty

            for calendar in enabledCalendars {
                guard let syncToken = preferences.syncToken(for: calendar.id) else {
                    // No token yet. Mint one from an unbounded, unordered request, which
                    // is the only shape whose parameters an incremental call can match.
                    let full = try await api.listFullSyncEvents(
                        calendarID: calendar.id,
                        accessToken: token,
                        timeMin: Self.syncFloor(from: now)
                    )
                    preferences.setSyncToken(full.nextSyncToken, for: calendar.id)
                    needsWindowFetch = true
                    continue
                }

                do {
                    let delta = try await api.listIncrementalEvents(
                        calendarID: calendar.id,
                        accessToken: token,
                        syncToken: syncToken
                    )
                    if let next = delta.nextSyncToken {
                        preferences.setSyncToken(next, for: calendar.id)
                    }
                    if !delta.events.isEmpty {
                        needsWindowFetch = true
                    }
                } catch GoogleCalendarAPIError.syncTokenExpired {
                    // 410. Google's instruction is to clear and full sync; dropping the
                    // token makes the next pass take the branch above.
                    preferences.setSyncToken(nil, for: calendar.id)
                    needsWindowFetch = true
                } catch {
                    // Fail open. An unknown delta state must not be read as "nothing
                    // changed", because the cost of that is an alarm for a meeting that
                    // moved.
                    SchedulerLog.warning("google incremental sync failed for \(calendar.id)")
                    needsWindowFetch = true
                }
            }

            preferences.lastSyncCheck = Date()

            guard needsWindowFetch else {
                // Steady state: one cheap request per calendar and no expansion work.
                lastSyncError = nil
                return cachedEvents
                    .filter { $0.startDate >= now && $0.startDate <= end }
                    .sorted { $0.startDate < $1.startDate }
            }

            // Step 2: the expanded, bounded query that actually feeds the UI and the
            // alarms. `singleEvents=true` and `orderBy=startTime` live here, where the
            // window is bounded and no sync token is involved.
            var merged: [String: GoogleCalendarFetchedEvent] = [:]
            for calendar in enabledCalendars {
                let page = try await api.listEvents(
                    calendarID: calendar.id,
                    accessToken: token,
                    timeMin: now,
                    timeMax: end
                )
                for event in page.events {
                    guard let mapped = mapEvent(event, calendar: calendar) else { continue }
                    merged[mapped.occurrenceID] = mapped
                }
            }

            lastSyncError = nil
            return merged.values
                .filter { $0.startDate >= now && $0.startDate <= end }
                .sorted { $0.startDate < $1.startDate }
        } catch {
            lastSyncError = error.localizedDescription
            SchedulerLog.error("google calendar sync failed")
            if cachedEvents.isEmpty {
                return []
            }
            let now = Date()
            let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
            return cachedEvents
                .filter { $0.startDate >= now && $0.startDate <= end }
                .sorted { $0.startDate < $1.startDate }
        }
    }

    private var enabledCalendars: [GoogleCalendarListEntry] {
        availableCalendars.filter { preferences.isCalendarEnabled($0.id) }
    }

    /// How far back the token-minting full sync reaches.
    ///
    /// `timeMin` is an absolute date baked into the token, so this is a floor that never
    /// moves until the token is replaced. A week of history is enough to catch an event
    /// that was edited today but started yesterday, without asking Google for years.
    private static func syncFloor(from now: Date) -> Date {
        now.addingTimeInterval(-7 * 24 * 60 * 60)
    }

    private func mapEvent(
        _ event: GoogleCalendarEvent,
        calendar: GoogleCalendarListEntry
    ) -> GoogleCalendarFetchedEvent? {
        guard !event.isCancelled else { return nil }
        guard !event.isAllDay else { return nil }
        // Focus blocks, out-of-office and working-location entries are not meetings.
        // The predecessor macOS app always filtered these; the Google path here never did.
        guard event.isAlertableEventType else { return nil }
        guard let googleEventID = event.id else { return nil }
        guard let dates = api.parseEventDates(event) else { return nil }

        let trimmed = event.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title: String
        if calendar.isBusyOnly && trimmed.isEmpty {
            title = "Busy"
        } else {
            title = trimmed.isEmpty ? "Untitled" : trimmed
        }

        return GoogleCalendarFetchedEvent(
            googleEventID: googleEventID,
            title: title,
            startDate: dates.start,
            endDate: dates.end,
            location: event.location,
            calendarID: calendar.id,
            calendarTitle: calendar.title,
            isBusyOnly: calendar.isBusyOnly,
            occurrenceID: GoogleCalendarFetchedEvent.occurrenceID(
                googleEventID: googleEventID,
                startDate: dates.start
            )
        )
    }
}
