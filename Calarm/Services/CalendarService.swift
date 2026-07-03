//
//  CalendarService.swift
//  Calarm
//

import Combine
import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isLoading = false

    private let eventStore = EKEventStore()
    private var reloadTask: Task<Void, Never>?

    init() {
        checkAuthorizationStatus()
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
            return granted
        } catch {
            authorizationStatus = .denied
            return false
        }
    }

    func fetchUpcomingEvents(days: Int = 7) async -> [EKEvent] {
        guard authorizationStatus == .fullAccess else { return [] }

        isLoading = true
        defer { isLoading = false }

        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)

        return eventStore
            .events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
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
