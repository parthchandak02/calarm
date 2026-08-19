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

        let ids = availableCalendars.map(\.id)
        if preferences.enabledCalendarIDs.isEmpty {
            preferences.enabledCalendarIDs = Set(ids.filter { $0 == "primary" || ($0.contains("@") && $0.contains(".com")) })
            if preferences.enabledCalendarIDs.isEmpty {
                preferences.enabledCalendarIDs = Set(ids)
            }
        }
    }

    func setCalendarEnabled(_ calendarID: String, enabled: Bool) {
        preferences.setCalendarEnabled(
            calendarID,
            enabled: enabled,
            allCalendarIDs: availableCalendars.map(\.id)
        )
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

            var merged: [String: GoogleCalendarFetchedEvent] = [:]

            for calendar in enabledCalendars {
                let pageResult = try await api.listEvents(
                    calendarID: calendar.id,
                    accessToken: token,
                    timeMin: now,
                    timeMax: end
                )
                for event in pageResult.events {
                    guard let mapped = mapEvent(event, calendar: calendar) else { continue }
                    merged[mapped.occurrenceID] = mapped
                }

                if preferences.syncToken(for: calendar.id) == nil,
                   let bootstrapToken = pageResult.nextSyncToken {
                    preferences.setSyncToken(bootstrapToken, for: calendar.id)
                }

                if let syncToken = preferences.syncToken(for: calendar.id) {
                    do {
                        let incremental = try await api.listIncrementalEvents(
                            calendarID: calendar.id,
                            accessToken: token,
                            syncToken: syncToken
                        )
                        applyIncrementalEvents(
                            incremental.events,
                            calendar: calendar,
                            merged: &merged
                        )
                        if let next = incremental.nextSyncToken {
                            preferences.setSyncToken(next, for: calendar.id)
                        }
                    } catch GoogleCalendarAPIError.syncTokenExpired {
                        preferences.setSyncToken(nil, for: calendar.id)
                    } catch {
                        SchedulerLog.warning("google incremental sync failed for \(calendar.id)")
                    }
                }
            }

            preferences.lastSyncCheck = Date()
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

    private func applyIncrementalEvents(
        _ events: [GoogleCalendarEvent],
        calendar: GoogleCalendarListEntry,
        merged: inout [String: GoogleCalendarFetchedEvent]
    ) {
        for event in events {
            if event.isCancelled {
                if let occurrenceID = occurrenceID(for: event, calendar: calendar) {
                    merged.removeValue(forKey: occurrenceID)
                }
                continue
            }
            guard let mapped = mapEvent(event, calendar: calendar) else { continue }
            merged[mapped.occurrenceID] = mapped
        }
    }

    private func occurrenceID(
        for event: GoogleCalendarEvent,
        calendar: GoogleCalendarListEntry
    ) -> String? {
        guard let googleEventID = event.id else { return nil }
        guard let dates = api.parseEventDates(event) else { return nil }
        return GoogleCalendarFetchedEvent.occurrenceID(
            googleEventID: googleEventID,
            startDate: dates.start
        )
    }

    private func mapEvent(
        _ event: GoogleCalendarEvent,
        calendar: GoogleCalendarListEntry
    ) -> GoogleCalendarFetchedEvent? {
        guard !event.isCancelled else { return nil }
        guard !event.isAllDay else { return nil }
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
