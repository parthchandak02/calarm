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
    @Published private(set) var pendingEventDeepLinkID: String?
    @Published private(set) var pendingDeepLinkRoute: CalarmDeepLink.EventRoute?
    @Published private(set) var scheduleFailures: [ScheduleFailure] = []
    @Published private(set) var tooSoonWarnings: Set<String> = []
    @Published private(set) var lastRescheduleSummary: RescheduleSummary?
    @Published private(set) var deepLinkFailureMessage: String?
    @Published var showBulkEnableConfirmation = false
    @Published private(set) var eventsIdentityToken: String = ""

    let calendarService = CalendarService()
    private let preferences = EventAlarmPreferences()
    private let alarmScheduler = AlarmScheduler()
    private let rescheduleCoordinator = RescheduleCoordinator()
    private let alarmUpdatesObserver = AlarmUpdatesObserver()
    private var cancellables = Set<AnyCancellable>()
    private var reloadTask: Task<Void, Never>?
    private var authorizationObservationTask: Task<Void, Never>?
    private var pendingBulkEnableAfterConfirm = false
    private var lastScheduledFingerprint: String?

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

        alarmUpdatesObserver.onAlarmsChanged = { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
    }

    func bootstrap() async {
        if ScreenshotMode.isEnabled {
            authorizationStatus = .fullAccess
            alarmAuthorization = .authorized
            events = ScreenshotDemoData.events()
            refreshEventsIdentityToken()
            return
        }

        alarmUpdatesObserver.start()
        startAuthorizationUpdatesObservation()
        MorningSyncScheduler.register { [weak self] in
            await self?.reload()
        }
        MorningSyncScheduler.scheduleNext()
        await requestAlarmAuthorizationIfNeeded()
        await runMetadataMigrationIfNeeded()

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

        reloadTask?.cancel()
        let task = Task {
            calendarService.refreshCalendarList()
            let previousIDs = Set(events.map(\.id))
            let fetchDays = AlarmOffsetOption.recommendedCalendarFetchDays
            let ekEvents = await calendarService.fetchUpcomingEvents(days: fetchDays)
            preferences.migrateLegacyKeys(for: ekEvents)
            let currentIDs = Set(ekEvents.compactMap { ekEvent -> String? in
                guard let eventIdentifier = ekEvent.eventIdentifier else { return nil }
                return EventOccurrenceID(eventIdentifier: eventIdentifier, startDate: ekEvent.startDate).rawValue
            })

            events = ekEvents.compactMap { ekEvent in
                guard let eventIdentifier = ekEvent.eventIdentifier else { return nil }
                let occurrence = EventOccurrenceID(eventIdentifier: eventIdentifier, startDate: ekEvent.startDate)
                let trimmed = ekEvent.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = trimmed.isEmpty ? "Untitled" : trimmed
                return ScheduleEvent(
                    id: occurrence.rawValue,
                    title: title,
                    startDate: ekEvent.startDate,
                    endDate: ekEvent.endDate,
                    location: ekEvent.location,
                    calendarTitle: ekEvent.calendar.title,
                    alarmOffsets: preferences.alarmOffsets(for: occurrence.rawValue)
                )
            }
            refreshEventsIdentityToken()

            for removedID in previousIDs.subtracting(currentIDs) {
                preferences.removeOverride(for: removedID)
            }

            await alarmScheduler.cancelRemoved(eventIDs: previousIDs.subtracting(currentIDs))
            await rescheduleIfNeeded(force: false)
        }
        reloadTask = task
        await task.value
    }

    func toggleAlarm(for eventID: String) {
        guard alarmAuthorization == .authorized else {
            scheduleFailures = [ScheduleFailure(
                occurrenceID: eventID,
                eventTitle: event(with: eventID)?.title ?? "Event",
                offsetTitle: "",
                message: "Alarm permission is required. Enable alarms for CALarm in Settings."
            )]
            return
        }

        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }

        if events[index].alarmEnabled {
            preferences.setAlarmOffsets([], for: eventID)
            events[index].alarmOffsets = []
        } else {
            if alarmAuthorization == .notDetermined {
                Task { await requestAlarmAuthorizationIfNeeded() }
            }
            preferences.addAlarmOffset(defaultAlarmOffset.enablingFallback, for: eventID)
            events[index].alarmOffsets = preferences.alarmOffsets(for: eventID)
        }

        requestReschedule()
    }

    func addAlarmOffset(_ offset: AlarmOffsetOption, for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !events[index].alarmOffsets.contains(offset) else { return }

        preferences.addAlarmOffset(offset, for: eventID)
        events[index].alarmOffsets = preferences.alarmOffsets(for: eventID)
        requestReschedule()
    }

    func removeAlarmOffset(_ offset: AlarmOffsetOption, for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }

        preferences.removeAlarmOffset(offset, for: eventID)
        events[index].alarmOffsets = preferences.alarmOffsets(for: eventID)
        requestReschedule()
    }

    func availableAlarmOffsets(for eventID: String) -> [AlarmOffsetOption] {
        guard let event = event(with: eventID) else { return AlarmOffsetOption.schedulableOffsets }
        let configured = Set(event.alarmOffsets)
        return AlarmOffsetOption.schedulableOffsets.filter { !configured.contains($0) }
    }

    func updateDefaultAlarmOffset(_ offset: AlarmOffsetOption) {
        defaultAlarmOffset = offset
        preferences.defaultAlarmOffset = offset
        requestReschedule()
    }

    func updateDefaultSnooze(_ snooze: SnoozeDurationOption) {
        defaultSnooze = snooze
        preferences.defaultSnooze = snooze
        requestReschedule()
    }

    func event(with id: String) -> ScheduleEvent? {
        events.first { $0.id == id }
    }

    func event(matching route: CalarmDeepLink.EventRoute) -> ScheduleEvent? {
        if let exact = events.first(where: { $0.id == route.occurrenceID }) {
            return exact
        }
        if let startTimestamp = route.startTimestamp, let legacy = route.legacyEventIdentifier {
            let target = EventOccurrenceID(
                eventIdentifier: legacy,
                startDate: Date(timeIntervalSince1970: startTimestamp)
            ).rawValue
            return events.first { $0.id == target }
        }
        if let legacy = route.legacyEventIdentifier {
            return events.first { $0.id.hasPrefix("\(legacy)_") }
        }
        return nil
    }

    func handleIncomingURL(_ url: URL) {
        guard let route = CalarmDeepLink.eventRoute(from: url) else { return }
        pendingDeepLinkRoute = route
        pendingEventDeepLinkID = route.occurrenceID
        deepLinkFailureMessage = nil
    }

    func acknowledgeEventDeepLink() {
        pendingEventDeepLinkID = nil
        pendingDeepLinkRoute = nil
        deepLinkFailureMessage = nil
    }

    func resolveDeepLinkIfNeeded() {
        guard let pendingID = pendingEventDeepLinkID else { return }
        if event(with: pendingID) != nil {
            return
        }
        if !isLoading, authorizationStatus == .fullAccess {
            deepLinkFailureMessage = "This event isn’t on your calendar anymore."
            acknowledgeEventDeepLink()
        }
    }

    var schedulableEvents: [ScheduleEvent] {
        events.filter { !$0.isAlarmInPast }
    }

    var allAlarmsEnabled: Bool {
        let candidates = schedulableEvents
        return !candidates.isEmpty && candidates.allSatisfy(\.alarmEnabled)
    }

    func setAllAlarmsEnabled(_ enabled: Bool) {
        if enabled, defaultAlarmOffset == .noAlarm {
            showBulkEnableConfirmation = true
            pendingBulkEnableAfterConfirm = true
            return
        }
        applySetAllAlarmsEnabled(enabled, offset: defaultAlarmOffset.enablingFallback)
    }

    func confirmBulkEnableWithFallback() {
        showBulkEnableConfirmation = false
        guard pendingBulkEnableAfterConfirm else { return }
        pendingBulkEnableAfterConfirm = false
        applySetAllAlarmsEnabled(true, offset: AlarmOffsetOption.tenMinutes.enablingFallback)
    }

    func cancelBulkEnableConfirmation() {
        showBulkEnableConfirmation = false
        pendingBulkEnableAfterConfirm = false
    }

    func scheduleTestAlarm() async -> String? {
        guard alarmAuthorization == .authorized else {
            return "Enable alarm permission for CALarm in Settings first."
        }
        return await alarmScheduler.scheduleTestAlarm(snoozeSeconds: defaultSnooze.seconds)
    }

    func clearScheduleFailures() {
        scheduleFailures = []
    }

    func refreshAfterThemeChange() {
        lastScheduledFingerprint = nil
        requestReschedule(force: true)
    }

    private func applySetAllAlarmsEnabled(_ enabled: Bool, offset: AlarmOffsetOption) {
        var changed = false

        if enabled {
            for index in events.indices where !events[index].isAlarmInPast && events[index].alarmOffsets.isEmpty {
                preferences.addAlarmOffset(offset, for: events[index].id)
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
        requestReschedule()
    }

    private func requestReschedule(force: Bool = true) {
        rescheduleCoordinator.requestReschedule { [weak self] in
            await self?.rescheduleIfNeeded(force: force) ?? RescheduleSummary(
                finishedAt: Date(),
                scheduledCount: 0,
                failureCount: 0,
                skippedDuringAlerting: false
            )
        }
    }

    @discardableResult
    private func rescheduleIfNeeded(force: Bool) async -> RescheduleSummary {
        let fingerprint = alarmScheduler.schedulingFingerprint(
            for: events,
            snoozeSeconds: defaultSnooze.seconds
        )

        if !force, fingerprint == lastScheduledFingerprint {
            SchedulerLog.info("reschedule skipped — schedule unchanged")
            return lastRescheduleSummary ?? RescheduleSummary(
                finishedAt: Date(),
                scheduledCount: 0,
                failureCount: 0,
                skippedDuringAlerting: false
            )
        }

        if !force, alarmScheduler.hasActiveCountdown() {
            SchedulerLog.info("deferring reschedule during active countdown")
            return lastRescheduleSummary ?? RescheduleSummary(
                finishedAt: Date(),
                scheduledCount: 0,
                failureCount: 0,
                skippedDuringAlerting: false
            )
        }

        return await performReschedule(force: force, fingerprint: fingerprint)
    }

    @discardableResult
    private func performReschedule(force: Bool, fingerprint: String? = nil) async -> RescheduleSummary {
        let result = await alarmScheduler.reschedule(
            events: events,
            snoozeSeconds: defaultSnooze.seconds,
            force: force
        )
        scheduleFailures = result.failures
        tooSoonWarnings = Set(result.skippedTooSoon.map(\.occurrenceID))
        let summary = RescheduleSummary(
            finishedAt: Date(),
            scheduledCount: result.scheduledCount,
            failureCount: result.failures.count,
            skippedDuringAlerting: result.skippedDuringAlerting
        )
        lastRescheduleSummary = summary
        if !result.skippedDuringAlerting, result.failures.isEmpty {
            lastScheduledFingerprint = fingerprint ?? alarmScheduler.schedulingFingerprint(
                for: events,
                snoozeSeconds: defaultSnooze.seconds
            )
        }
        return summary
    }

    private func refreshEventsIdentityToken() {
        eventsIdentityToken = events.map(\.id).joined(separator: "|")
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

    private func startAuthorizationUpdatesObservation() {
        authorizationObservationTask?.cancel()
        authorizationObservationTask = Task {
            for await state in AlarmManager.shared.authorizationUpdates {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.alarmAuthorization = state
                }
            }
        }
    }

    private func runMetadataMigrationIfNeeded() async {
        guard !CalarmPersistence.bool(forKey: CalarmPersistence.Key.occurrenceMetadataMigrationDone) else { return }
        CalarmPersistence.setBool(true, forKey: CalarmPersistence.Key.occurrenceMetadataMigrationDone)
        if authorizationStatus == .fullAccess {
            lastScheduledFingerprint = nil
            await performReschedule(force: true)
        }
    }
}
