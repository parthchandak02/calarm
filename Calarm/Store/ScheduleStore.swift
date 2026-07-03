//
//  ScheduleStore.swift
//  Calarm
//

import AlarmKit
import Combine
import EventKit
import Foundation

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var events: [ScheduleEvent] = []
    @Published var defaultAlarmOffset: AlarmOffsetOption
    @Published var defaultSnooze: SnoozeDurationOption
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published private(set) var alarmAuthorization: AlarmManager.AuthorizationState = .notDetermined

    let calendarService = CalendarService()
    private let preferences = EventAlarmPreferences()
    private let alarmScheduler = AlarmScheduler()
    private var cancellables = Set<AnyCancellable>()

    var nextUpcomingAlarm: ScheduleEvent? {
        events
            .filter(\.canScheduleAlarm)
            .min { lhs, rhs in
                (lhs.nextAlarmDate ?? .distantFuture) < (rhs.nextAlarmDate ?? .distantFuture)
            }
    }

    var groupedDays: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startDate)
        }

        return grouped.keys.sorted().map { day in
            DaySection(
                id: String(day.timeIntervalSince1970),
                title: dayHeader(for: day),
                date: day,
                events: (grouped[day] ?? []).sorted { $0.startDate < $1.startDate }
            )
        }
    }

    init() {
        defaultAlarmOffset = preferences.defaultAlarmOffset
        defaultSnooze = preferences.defaultSnooze
        authorizationStatus = calendarService.authorizationStatus

        calendarService.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$authorizationStatus)

        calendarService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        calendarService.onCalendarChanged { [weak self] in
            await self?.reload()
        }
        .store(in: &cancellables)
    }

    func bootstrap() async {
        await requestAlarmAuthorizationIfNeeded()

        if authorizationStatus == .fullAccess {
            await reload()
        }
    }

    func requestCalendarAccess() async {
        let granted = await calendarService.requestCalendarAccess()
        if granted {
            await reload()
        }
    }

    func refreshOnForeground() async {
        calendarService.checkAuthorizationStatus()
        alarmAuthorization = AlarmManager.shared.authorizationState
        if authorizationStatus == .fullAccess {
            await reload()
        }
    }

    func reload() async {
        guard authorizationStatus == .fullAccess else { return }

        let previousIDs = Set(events.map(\.id))
        let ekEvents = await calendarService.fetchUpcomingEvents()
        let currentIDs = Set(ekEvents.compactMap(\.eventIdentifier))

        events = ekEvents.compactMap { ekEvent in
            guard let eventID = ekEvent.eventIdentifier else { return nil }
            let trimmed = ekEvent.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = trimmed.isEmpty ? "Untitled" : trimmed
            return ScheduleEvent(
                id: eventID,
                title: title,
                startDate: ekEvent.startDate,
                endDate: ekEvent.endDate,
                location: ekEvent.location,
                calendarTitle: ekEvent.calendar.title,
                alarmOffsets: preferences.alarmOffsets(for: eventID)
            )
        }

        for removedID in previousIDs.subtracting(currentIDs) {
            preferences.removeOverride(for: removedID)
        }

        await alarmScheduler.reschedule(
            events: events,
            snoozeSeconds: defaultSnooze.seconds,
            force: false
        )
    }

    func toggleAlarm(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }

        if events[index].alarmEnabled {
            preferences.setAlarmOffsets([], for: eventID)
            events[index].alarmOffsets = []
        } else {
            preferences.addAlarmOffset(defaultAlarmOffset, for: eventID)
            events[index].alarmOffsets = preferences.alarmOffsets(for: eventID)
        }

        Task {
            await alarmScheduler.reschedule(
                event: events[index],
                among: events,
                snoozeSeconds: defaultSnooze.seconds
            )
        }
    }

    func addAlarmOffset(_ offset: AlarmOffsetOption, for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !events[index].alarmOffsets.contains(offset) else { return }

        preferences.addAlarmOffset(offset, for: eventID)
        events[index].alarmOffsets = preferences.alarmOffsets(for: eventID)

        Task {
            await alarmScheduler.reschedule(
                event: events[index],
                among: events,
                snoozeSeconds: defaultSnooze.seconds
            )
        }
    }

    func removeAlarmOffset(_ offset: AlarmOffsetOption, for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }

        preferences.removeAlarmOffset(offset, for: eventID)
        events[index].alarmOffsets = preferences.alarmOffsets(for: eventID)

        Task {
            await alarmScheduler.reschedule(
                event: events[index],
                among: events,
                snoozeSeconds: defaultSnooze.seconds
            )
        }
    }

    func availableAlarmOffsets(for eventID: String) -> [AlarmOffsetOption] {
        guard let event = event(with: eventID) else { return AlarmOffsetOption.allCases }
        let configured = Set(event.alarmOffsets)
        return AlarmOffsetOption.allCases.filter { !configured.contains($0) }
    }

    func updateDefaultAlarmOffset(_ offset: AlarmOffsetOption) {
        defaultAlarmOffset = offset
        preferences.defaultAlarmOffset = offset
    }

    func updateDefaultSnooze(_ snooze: SnoozeDurationOption) {
        defaultSnooze = snooze
        preferences.defaultSnooze = snooze

        Task {
            await alarmScheduler.reschedule(
                events: events,
                snoozeSeconds: snooze.seconds,
                force: true
            )
        }
    }

    func event(with id: String) -> ScheduleEvent? {
        events.first { $0.id == id }
    }

    var schedulableEvents: [ScheduleEvent] {
        events.filter { !$0.isAlarmInPast }
    }

    var allAlarmsEnabled: Bool {
        let candidates = schedulableEvents
        return !candidates.isEmpty && candidates.allSatisfy(\.alarmEnabled)
    }

    func setAllAlarmsEnabled(_ enabled: Bool) {
        var changed = false

        if enabled {
            for index in events.indices where !events[index].isAlarmInPast && events[index].alarmOffsets.isEmpty {
                preferences.addAlarmOffset(defaultAlarmOffset, for: events[index].id)
                events[index].alarmOffsets = preferences.alarmOffsets(for: events[index].id)
                changed = true
            }
        } else {
            for index in events.indices where events[index].alarmEnabled {
                preferences.setAlarmOffsets([], for: events[index].id)
                events[index].alarmOffsets = []
                changed = true
            }
        }

        guard changed else { return }
        Task {
            await alarmScheduler.reschedule(
                events: events,
                snoozeSeconds: defaultSnooze.seconds,
                force: true
            )
        }
    }

    private func dayHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func requestAlarmAuthorizationIfNeeded() async {
        alarmAuthorization = AlarmManager.shared.authorizationState
        switch alarmAuthorization {
        case .notDetermined:
            if let state = try? await AlarmManager.shared.requestAuthorization() {
                alarmAuthorization = state
            }
        default:
            break
        }
    }
}
