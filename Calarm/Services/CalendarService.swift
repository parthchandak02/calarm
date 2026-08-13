//
//  CalendarService.swift
//  Calarm
//

import Combine
import EventKit
import Foundation

struct CalendarSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let colorHex: String
    var isEnabled: Bool
}

@MainActor
final class CalendarService: ObservableObject {
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published private(set) var availableCalendars: [CalendarSummary] = []

    private let eventStore = EKEventStore()
    private var reloadTask: Task<Void, Never>?

    init() {
        checkAuthorizationStatus()
        refreshCalendarList()
    }

    deinit {
        reloadTask?.cancel()
    }

    func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = granted ? .fullAccess : .denied
            if granted {
                refreshCalendarList()
            }
            return granted
        } catch {
            authorizationStatus = .denied
            return false
        }
    }

    func refreshCalendarList() {
        guard authorizationStatus == .fullAccess else {
            availableCalendars = []
            return
        }
        availableCalendars = eventStore.calendars(for: .event)
            .map { calendar in
                CalendarSummary(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    colorHex: calendar.cgColor?.components?.description ?? "",
                    isEnabled: CalendarFilterPreferences.isEnabled(calendarID: calendar.calendarIdentifier)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func setCalendarEnabled(_ calendarID: String, enabled: Bool) {
        let allIDs = eventStore.calendars(for: .event).map(\.calendarIdentifier)
        CalendarFilterPreferences.setEnabled(enabled, calendarID: calendarID, allCalendarIDs: allIDs)
        refreshCalendarList()
    }

    func fetchUpcomingEvents(days: Int = 7) async -> [EKEvent] {
        guard authorizationStatus == .fullAccess else { return [] }

        isLoading = true
        defer { isLoading = false }

        refreshRemoteSourcesIfNeeded()

        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let calendars = filteredCalendars()
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)

        return eventStore
            .events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Ask iOS to refresh external calendar sources (Google, Exchange) before reading EventKit.
    func refreshRemoteSourcesIfNeeded() {
        guard authorizationStatus == .fullAccess else { return }
        eventStore.refreshSourcesIfNecessary()
    }

    /// EventKit calendars that mirror a Google account — skipped when Google direct sync is active.
    func isGoogleMirroredCalendar(_ calendar: EKCalendar) -> Bool {
        let sourceTitle = calendar.source.title.lowercased()
        if sourceTitle.contains("google") || sourceTitle.contains("gmail") {
            return true
        }
        if calendar.source.sourceType == .calDAV,
           calendar.calendarIdentifier.lowercased().contains("google") {
            return true
        }
        return false
    }

    private func filteredCalendars() -> [EKCalendar]? {
        let enabled = CalendarFilterPreferences.enabledCalendarIDs
        if enabled.isEmpty { return nil }
        let calendars = eventStore.calendars(for: .event).filter { enabled.contains($0.calendarIdentifier) }
        return calendars.isEmpty ? nil : calendars
    }

    func onCalendarChanged(_ handler: @escaping () async -> Void) -> AnyCancellable {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadTask?.cancel()
                self?.reloadTask = Task {
                    await handler()
                }
            }
    }
}
