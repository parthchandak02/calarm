//
//  ScheduleView.swift
//  Calarm
//

import AlarmKit
import EventKit
import SwiftUI
import UIKit

private struct EventRoute: Hashable {
    let id: String
}

struct ScheduleView: View {
    @EnvironmentObject private var store: ScheduleStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.calarmTheme) private var theme

    @State private var showingSettings = false
    @State private var navigationPath = NavigationPath()

    private var canManageAlarms: Bool {
        store.hasEventSource && !store.schedulableEvents.isEmpty
    }

    private var showsCalendarAccessPrompt: Bool {
        !store.hasEventSource
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                ScheduleHeaderBar(
                    theme: theme,
                    canManageAlarms: canManageAlarms,
                    allAlarmsEnabled: store.allAlarmsEnabled,
                    hasEnabledAlarms: store.schedulableEvents.contains(where: \.alarmEnabled),
                    canRefresh: store.hasEventSource,
                    isRefreshing: store.isLoading,
                    onTurnAllOn: { store.setAllAlarmsEnabled(true) },
                    onTurnAllOff: { store.setAllAlarmsEnabled(false) },
                    onRefresh: { Task { await store.reload() } },
                    onSettings: { showingSettings = true }
                )

                statusBanners

                if !showsCalendarAccessPrompt {
                    let next = store.nextUpcomingAlarm
                    NextAlarmBoard(event: next, fireDate: next?.nextAlarmDate) {
                        if let next {
                            navigationPath.append(EventRoute(id: next.id))
                        }
                    }
                }

                ZStack {
                    theme.background.ignoresSafeArea()

                    Group {
                        if showsCalendarAccessPrompt {
                            accessPrompt
                        } else if store.events.isEmpty && !store.isLoading {
                            emptyState
                        } else {
                            scheduleList
                        }
                    }
                }
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsSheet()
                .environmentObject(store)
                .environmentObject(themeStore)
            }
            .navigationDestination(for: EventRoute.self) { route in
                EventDetailView(eventID: route.id)
                    .environmentObject(store)
                    .environmentObject(themeStore)
            }
            .overlay {
                if store.isLoading && store.events.isEmpty {
                    ProgressView()
                        .tint(theme.accent)
                }
            }
            .confirmationDialog(
                "Turn on all alarms?",
                isPresented: $store.showBulkEnableConfirmation,
                titleVisibility: .visible
            ) {
                Button("Use 10 minutes before") {
                    store.confirmBulkEnableWithFallback()
                }
                Button("Cancel", role: .cancel) {
                    store.cancelBulkEnableConfirmation()
                }
            } message: {
                Text("Your default is “No alarm.” Turn on all upcoming events with a 10-minute reminder?")
            }
            .alert(
                "Event unavailable",
                isPresented: Binding(
                    get: { store.deepLinkFailureMessage != nil },
                    set: { if !$0 { store.acknowledgeEventDeepLink() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    store.acknowledgeEventDeepLink()
                }
            } message: {
                Text(store.deepLinkFailureMessage ?? "")
            }
        }
        .font(CalarmFont.body)
        .accessibilityIdentifier("schedule.screen")
        .onAppear {
            applyScreenshotSceneIfNeeded()
            presentPendingEventDeepLinkIfNeeded()
        }
        .onChange(of: store.pendingEventDeepLinkID) { _, _ in
            presentPendingEventDeepLinkIfNeeded()
        }
        .onChange(of: store.eventsIdentityToken) { _, _ in
            presentPendingEventDeepLinkIfNeeded()
            store.resolveDeepLinkIfNeeded()
        }
        .onChange(of: store.isLoading) { _, isLoading in
            if !isLoading {
                store.resolveDeepLinkIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var statusBanners: some View {
        VStack(spacing: 0) {
            if store.alarmAuthorization == .denied {
                permissionBanner(
                    title: "Alarm permission is off",
                    message: "Enable Alarms for CALarm in Settings to schedule countdown alarms.",
                    actionTitle: "Open Settings"
                ) {
                    openSettings()
                }
            }

            if let syncError = store.googleSyncErrorMessage {
                permissionBanner(
                    title: "Google Calendar sync failed",
                    message: syncError,
                    actionTitle: "Dismiss"
                ) {
                    store.clearGoogleSyncError()
                }
            }

            if !store.scheduleFailures.isEmpty {
                let failure = store.scheduleFailures.first!
                let title = store.scheduleFailures.count > 1
                    ? "Couldn’t schedule \(store.scheduleFailures.count) alarms"
                    : "Couldn’t schedule an alarm"
                permissionBanner(
                    title: title,
                    message: "\(failure.eventTitle): \(failure.message)",
                    actionTitle: "Dismiss"
                ) {
                    store.clearScheduleFailures()
                }
            }
        }
    }

    private func permissionBanner(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CalarmFont.captionSemibold)
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(CalarmFont.caption)
                .foregroundStyle(theme.textSecondary)
            Button(actionTitle, action: action)
                .font(CalarmFont.captionSemibold)
                .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CalarmTheme.rowPaddingH)
        .padding(.vertical, 10)
        .background(theme.surfaceStroke.opacity(0.35))
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func presentPendingEventDeepLinkIfNeeded() {
        guard let pendingID = store.pendingEventDeepLinkID else { return }
        let resolved: ScheduleEvent? = {
            if let route = store.pendingDeepLinkRoute {
                return store.event(matching: route)
            }
            return store.event(with: pendingID)
        }()
        guard let event = resolved else { return }
        navigationPath.append(EventRoute(id: event.id))
        store.acknowledgeEventDeepLink()
    }

    private func applyScreenshotSceneIfNeeded() {
        guard ScreenshotMode.isEnabled else { return }
        switch ScreenshotMode.scene {
        case .schedule:
            break
        case .settings:
            showingSettings = true
        case .eventDetail, .addAlarm:
            navigationPath.append(EventRoute(id: ScreenshotDemoData.featuredEventID))
        }
    }

    private var scheduleList: some View {
        List {
            ForEach(store.groupedDays) { day in
                Section {
                    ForEach(day.events) { event in
                        EventRow(
                            event: event,
                            isNextAlarm: store.nextUpcomingAlarm?.id == event.id,
                            hasTooSoonWarning: store.tooSoonWarnings.contains(event.id),
                            onOpen: { navigationPath.append(EventRoute(id: event.id)) },
                            onToggle: { store.toggleAlarm(for: event.id) }
                        )
                        .listRowInsets(rowInsets)
                        .listRowSeparatorTint(theme.surfaceStroke.opacity(0.6))
                    }
                } header: {
                    BoardSectionLabel(title: DepartureBoard.dayTitle(for: day.date, now: .now))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.reload()
        }
        .accessibilityIdentifier("schedule.list")
        .id(themeStore.themeToken)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: CalarmTheme.rowPaddingH, bottom: 0, trailing: CalarmTheme.rowPaddingH - 12)
    }

    private var accessPrompt: some View {
        ContentUnavailableView {
            Label(accessPromptTitle, systemImage: accessPromptSymbol)
        } description: {
            Text(accessPromptMessage)
        } actions: {
            if store.authorizationStatus == .denied {
                Button("Open Settings", action: openSettings)
                    .font(CalarmFont.bodyMedium)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            } else {
                Button("Allow Calendar Access") {
                    Task { await store.requestCalendarAccess() }
                }
                .font(CalarmFont.bodyMedium)
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)

                Button("Connect Google Calendar in Settings") {
                    showingSettings = true
                }
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.accent)
            }
        }
        .padding()
    }

    private var accessPromptSymbol: String {
        store.authorizationStatus == .denied ? "calendar.badge.exclamationmark" : "calendar"
    }

    private var accessPromptTitle: String {
        if store.authorizationStatus == .denied {
            return "Calendar access is off"
        }
        return "See your week at a glance"
    }

    private var accessPromptMessage: String {
        if store.authorizationStatus == .denied {
            return "Enable calendar access in Settings to see your schedule and set event alarms."
        }
        return "CALarm shows upcoming calendar events. Turn on an alarm per event when you want a reminder."
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No upcoming events", systemImage: "calendar.badge.clock")
        } description: {
            Text("Nothing scheduled in the selected calendar window.")
        } actions: {
            Button("Refresh") {
                Task { await store.reload() }
            }
            .font(CalarmFont.bodyMedium)
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)

            Button("Choose calendars in Settings") {
                showingSettings = true
            }
            .font(CalarmFont.subheadline)
            .foregroundStyle(theme.accent)
        }
    }
}

private struct EventRow: View {
    @Environment(\.calarmTheme) private var theme

    let event: ScheduleEvent
    let isNextAlarm: Bool
    let hasTooSoonWarning: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void

    private var label: String {
        DepartureBoard.rowLabel(for: event, tooSoon: hasTooSoonWarning)
    }

    private var labelColor: Color {
        if hasTooSoonWarning || event.isReminderPassed { return theme.warning }
        if event.canScheduleAlarm { return theme.accent }
        return theme.textSecondary
    }

    private var rowColor: Color {
        isNextAlarm ? theme.accent : theme.textPrimary
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Text(CalarmTheme.eventTimeString(event.startDate))
                        .font(CalarmFont.time)
                        .foregroundStyle(rowColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: CalarmTheme.timeColumnWidth, alignment: .leading)

                    Text(event.title)
                        .font(CalarmFont.boardTitle)
                        .foregroundStyle(rowColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(label)
                        .font(CalarmFont.boardDetail)
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(event.title), \(CalarmTheme.eventTimeString(event.startDate)), \(event.alarmSummary)")
            }
            .buttonStyle(.plain)

            ArmSquareToggle(isOn: event.alarmEnabled, label: "Alarm for \(event.title)", onToggle: onToggle)
        }
        .opacity(event.isEventUpcoming ? 1 : 0.4)
        .listRowBackground(Color.clear)
    }
}
