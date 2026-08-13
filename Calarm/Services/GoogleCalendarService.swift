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
    func fetchUpcomingEvents(days: Int) async -> [GoogleCalendarFetchedEvent] {
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
                let windowEvents = try await api.listEvents(
                    calendarID: calendar.id,
                    accessToken: token,
                    timeMin: now,
                    timeMax: end
                )
                for event in windowEvents {
                    guard let mapped = mapEvent(event, calendar: calendar) else { continue }
                    merged[mapped.occurrenceID] = mapped
                }

                if let syncToken = preferences.syncToken(for: calendar.id) {
                    do {
                        let incremental = try await api.listIncrementalEvents(
                            calendarID: calendar.id,
                            accessToken: token,
                            syncToken: syncToken
                        )
                        if let next = incremental.nextSyncToken {
                            preferences.setSyncToken(next, for: calendar.id)
                        }
                    } catch GoogleCalendarAPIError.syncTokenExpired {
                        preferences.setSyncToken(nil, for: calendar.id)
                    } catch {
                        // Bounded fetch is the primary path; sync token is best-effort.
                    }
                }
            }

            preferences.lastSyncCheck = Date()
            lastSyncError = nil
            return merged.values
                .filter { $0.startDate >= now }
                .sorted { $0.startDate < $1.startDate }
        } catch {
            lastSyncError = error.localizedDescription
            SchedulerLog.error("google calendar sync failed: \(error.localizedDescription)")
            return []
        }
    }

    private var enabledCalendars: [GoogleCalendarListEntry] {
        availableCalendars.filter { preferences.isCalendarEnabled($0.id) }
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
