//
//  ScheduleStore.swift
//  Calarm
//

import AlarmKit
import Combine
import EventKit
import Foundation
import UIKit

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
    let googleCalendarService = GoogleCalendarService()
    private let preferences = EventAlarmPreferences()
    private let alarmScheduler = AlarmScheduler()
    private let rescheduleCoordinator = RescheduleCoordinator()
    private let alarmUpdatesObserver = AlarmUpdatesObserver()
    private var cancellables = Set<AnyCancellable>()
    private var reloadTask: Task<Void, Never>?
    private var authorizationObservationTask: Task<Void, Never>?
    private var pendingBulkEnableAfterConfirm = false
    private var lastScheduledFingerprint: String?

    var hasEventSource: Bool {
        ScheduleEventSourcePolicy.hasEventSource(
            eventKitFullAccess: authorizationStatus == .fullAccess,
            googleConnected: googleCalendarService.isConnected
        )
    }

    var googleSyncErrorMessage: String? {
        googleCalendarService.lastSyncError
    }

    var nextUpcomingAlarm: ScheduleEvent? {
        events
            .filter { $0.alarmEnabled && $0.isEventUpcoming }
            .min { lhs, rhs in
                let lhsDate = lhs.nextAlarmDate ?? lhs.startDate
                let rhsDate = rhs.nextAlarmDate ?? rhs.startDate
                return lhsDate < rhsDate
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
            .combineLatest(googleCalendarService.$isLoading)
            .map { $0 || $1 }
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        calendarService.onCalendarChanged { [weak self] in
            await self?.reload()
        }
        .store(in: &cancellables)

        alarmUpdatesObserver.onAlarmsChanged = { [weak self] _ in
            Task { @MainActor in
                await self?.handleAlarmKitUpdate()
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

        if googleCalendarService.isConnected {
            try? await googleCalendarService.refreshCalendarList()
        }

        if authorizationStatus == .fullAccess || googleCalendarService.isConnected {
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
        calendarService.refreshRemoteSourcesIfNeeded()
        alarmAuthorization = AlarmManager.shared.authorizationState
        // Reconcile before reload so missed/stuck AlarmKit alarms are cancelled even if
        // EventKit fetch hasn't run yet (AlarmKit does not wake the app — Apple docs).
        _ = await alarmScheduler.reconcileAlarmLifecycle(events: events)
        if hasEventSource {
            await reload()
        }
    }

    func handleSignificantTimeChange() {
        lastScheduledFingerprint = nil
        requestReschedule(force: true)
    }

    func connectGoogleCalendar(from viewController: UIViewController) async throws {
        try await googleCalendarService.connect(presenting: viewController)
        await reload()
    }

    func disconnectGoogleCalendar() {
        googleCalendarService.disconnect()
        Task { await reload() }
    }

    func reload() async {
        let canLoadEventKit = authorizationStatus == .fullAccess
        let canLoadGoogle = googleCalendarService.isConnected
        guard canLoadEventKit || canLoadGoogle else { return }

        reloadTask?.cancel()
        let task = Task {
            if canLoadEventKit {
                calendarService.refreshCalendarList()
            }

            let previousIDs = Set(events.map(\.id))
            let fetchDays = AlarmOffsetOption.recommendedCalendarFetchDays

            var mergedEvents: [ScheduleEvent] = []

            if canLoadEventKit {
                let ekEvents = await calendarService.fetchUpcomingEvents(days: fetchDays)
                guard !Task.isCancelled else { return }
                preferences.migrateLegacyKeys(for: ekEvents)
                let googleConnected = canLoadGoogle
                mergedEvents.append(contentsOf: ekEvents.compactMap { ekEvent in
                    guard let eventIdentifier = ekEvent.eventIdentifier else { return nil }
                    if googleConnected, calendarService.isGoogleMirroredCalendar(ekEvent.calendar) {
                        return nil
                    }
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
                        source: .eventKit,
                        calendarColorHex: CalendarColor.hexString(from: ekEvent.calendar.cgColor),
                        alarmOffsets: preferences.alarmOffsets(for: occurrence.rawValue)
                    )
                })
            }

            if canLoadGoogle {
                let cachedGoogle = events.filter { $0.source == .google }.map { event in
                    GoogleCalendarFetchedEvent(
                        googleEventID: googleEventID(from: event.id) ?? event.id,
                        title: event.title,
                        startDate: event.startDate,
                        endDate: event.endDate,
                        location: event.location,
                        calendarID: "",
                        calendarTitle: event.calendarTitle,
                        isBusyOnly: false,
                        occurrenceID: event.id
                    )
                }
                let googleEvents = await googleCalendarService.fetchUpcomingEvents(
                    days: fetchDays,
                    cachedEvents: cachedGoogle
                )
                guard !Task.isCancelled else { return }
                mergedEvents.append(contentsOf: googleEvents.map { googleEvent in
                    ScheduleEvent(
                        id: googleEvent.occurrenceID,
                        title: googleEvent.title,
                        startDate: googleEvent.startDate,
                        endDate: googleEvent.endDate,
                        location: googleEvent.location,
                        calendarTitle: googleEvent.calendarTitle,
                        source: .google,
                        calendarColorHex: nil,
                        alarmOffsets: preferences.alarmOffsets(for: googleEvent.occurrenceID)
                    )
                })
            }

            mergedEvents.sort { $0.startDate < $1.startDate }
            guard !Task.isCancelled else { return }
            events = mergedEvents
            refreshEventsIdentityToken()

            let currentIDs = Set(mergedEvents.map(\.id))
            let removedIDs = previousIDs.subtracting(currentIDs)
            await alarmScheduler.cancelRemoved(eventIDs: removedIDs)
            guard !Task.isCancelled else { return }
            await rescheduleCoordinator.requestRescheduleImmediate { [weak self] in
                await self?.rescheduleIfNeeded(force: false) ?? RescheduleSummary(
                    finishedAt: Date(),
                    scheduledCount: 0,
                    failureCount: 0,
                    skippedDuringAlerting: false
                )
            }
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
            if events[index].alarmOffsets.count > 1 {
                preferences.pauseAlarms(for: eventID)
            } else {
                preferences.setAlarmOffsets([], for: eventID)
            }
            events[index].alarmOffsets = []
        } else {
            if alarmAuthorization == .notDetermined {
                Task { await requestAlarmAuthorizationIfNeeded() }
            }
            if preferences.hasPausedAlarms(for: eventID) {
                preferences.resumeAlarms(for: eventID, defaultOffset: defaultAlarmOffset)
            } else {
                preferences.addAlarmOffset(defaultAlarmOffset.enablingFallback, for: eventID)
            }
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
        for index in events.indices {
            events[index].alarmOffsets = preferences.alarmOffsets(for: events[index].id)
        }
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
        guard let route = pendingDeepLinkRoute else {
            // fallback if only ID set
            guard let pendingID = pendingEventDeepLinkID else { return }
            if event(with: pendingID) != nil { return }
            if !isLoading, hasEventSource {
                deepLinkFailureMessage = "This event isn’t on your calendar anymore."
                acknowledgeEventDeepLink()
            }
            return
        }
        if event(matching: route) != nil { return }
        if !isLoading, hasEventSource {
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

    func clearGoogleSyncError() {
        googleCalendarService.clearLastSyncError()
    }

    func refreshAfterThemeChange() {
        lastScheduledFingerprint = nil
        requestReschedule(force: true)
    }

    private func handleAlarmKitUpdate() async {
        objectWillChange.send()
        let cleaned = await alarmScheduler.reconcileAlarmLifecycle(events: events)
        let fingerprint = alarmScheduler.schedulingFingerprint(
            for: events,
            snoozeSeconds: defaultSnooze.seconds
        )
        if cleaned > 0 || fingerprint != lastScheduledFingerprint {
            if cleaned > 0 {
                lastScheduledFingerprint = nil
            }
            requestReschedule(force: true)
        }
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
        var shouldForce = force
        let cleaned = await alarmScheduler.reconcileAlarmLifecycle(events: events)
        if cleaned > 0 {
            lastScheduledFingerprint = nil
            shouldForce = true
        }

        let fingerprint = alarmScheduler.schedulingFingerprint(
            for: events,
            snoozeSeconds: defaultSnooze.seconds
        )

        if !shouldForce, fingerprint == lastScheduledFingerprint {
            SchedulerLog.info("reschedule skipped - schedule unchanged")
            return lastRescheduleSummary ?? RescheduleSummary(
                finishedAt: Date(),
                scheduledCount: 0,
                failureCount: 0,
                skippedDuringAlerting: false
            )
        }

        return await performReschedule(force: shouldForce, fingerprint: fingerprint)
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
        if authorizationStatus == .fullAccess {
            lastScheduledFingerprint = nil
            await performReschedule(force: true)
        }
        CalarmPersistence.setBool(true, forKey: CalarmPersistence.Key.occurrenceMetadataMigrationDone)
    }

    private func googleEventID(from occurrenceID: String) -> String? {
        guard occurrenceID.hasPrefix("google.") else { return nil }
        let withoutPrefix = String(occurrenceID.dropFirst("google.".count))
        guard let separator = withoutPrefix.lastIndex(of: "_") else { return nil }
        return String(withoutPrefix[..<separator])
    }
}
