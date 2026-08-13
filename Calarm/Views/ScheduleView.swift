//
//  ScheduleView.swift
//  Calarm
//

import AlarmKit
import EventKit
import SwiftUI
import UIKit

struct ScheduleView: View {
    @EnvironmentObject private var store: ScheduleStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.calarmTheme) private var theme

    @State private var showingSettings = false
    @State private var selectedEvent: EventRoute?

    private struct EventRoute: Identifiable, Hashable {
        let id: String
    }

    private var canManageAlarms: Bool {
        store.hasEventSource && !store.schedulableEvents.isEmpty
    }

    private var showsCalendarAccessPrompt: Bool {
        !store.hasEventSource
    }

    var body: some View {
        NavigationStack {
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

                if let next = store.nextUpcomingAlarm, let fire = next.nextAlarmDate {
                    nextAlarmBanner(event: next, fireDate: fire)
                }

                statusBanners

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
                SettingsSheet(
                    defaultAlarmOffset: store.defaultAlarmOffset,
                    defaultSnooze: store.defaultSnooze,
                    onDefaultAlarmOffsetChange: { store.updateDefaultAlarmOffset($0) },
                    onDefaultSnoozeChange: { store.updateDefaultSnooze($0) }
                )
                .environmentObject(store)
                .environmentObject(themeStore)
            }
            .navigationDestination(item: $selectedEvent) { route in
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

    private func nextAlarmBanner(event: ScheduleEvent, fireDate: Date) -> some View {
        Button {
            selectedEvent = EventRoute(id: event.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "alarm.fill")
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                Text("Next: \(event.title)")
                    .font(CalarmFont.captionSemibold)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(theme.textSecondary)
                if fireDate.timeIntervalSinceNow > 0 {
                    Text(timerInterval: Date.now...fireDate, countsDown: true, showsHours: fireDate.timeIntervalSinceNow >= 3_600)
                        .font(CalarmFont.caption)
                        .foregroundStyle(theme.textSecondary)
                        .monospacedDigit()
                } else {
                    Text("passed")
                        .font(CalarmFont.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .padding(.vertical, 8)
            .background(theme.accent.opacity(0.08))
        }
        .buttonStyle(.plain)
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
        selectedEvent = EventRoute(id: event.id)
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
            selectedEvent = EventRoute(id: ScreenshotDemoData.featuredEventID)
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
                            onToggle: { store.toggleAlarm(for: event.id) },
                            onTap: { selectedEvent = EventRoute(id: event.id) }
                        )
                        .listRowInsets(rowInsets)
                        .listRowSeparatorTint(theme.surfaceStroke)
                    }
                } header: {
                    Text(day.title.uppercased())
                        .font(CalarmFont.sectionHeader)
                        .tracking(CalarmTheme.sectionHeaderTracking)
                        .foregroundStyle(theme.textPrimary.opacity(0.72))
                        .padding(.top, 8)
                        .padding(.bottom, 6)
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
        EdgeInsets(top: 10, leading: CalarmTheme.rowPaddingH, bottom: 10, trailing: CalarmTheme.rowPaddingH)
    }

    private var accessPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: store.authorizationStatus == .denied ? "calendar.badge.exclamationmark" : "calendar")
                .font(.system(size: 48))
                .foregroundStyle(theme.accent)

            Text(accessPromptTitle)
                .font(CalarmFont.title3)
                .foregroundStyle(theme.textPrimary)

            Text(accessPromptMessage)
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if store.authorizationStatus == .denied {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            } else {
                Button("Allow Calendar Access") {
                    Task { await store.requestCalendarAccess() }
                }
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
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(theme.accent.opacity(0.8))
            Text("No upcoming events")
                .font(CalarmFont.headline)
                .foregroundStyle(theme.textPrimary)
            Text("Nothing scheduled in the selected calendar window.")
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)

            Button("Refresh") {
                Task { await store.reload() }
            }
            .buttonStyle(.bordered)
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
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    let event: ScheduleEvent
    let isNextAlarm: Bool
    let hasTooSoonWarning: Bool
    let onToggle: () -> Void
    let onTap: () -> Void

    private var theme: CalarmTheme {
        themeStore.theme(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(CalarmTheme.eventTimeString(event.startDate))
                    .font(CalarmFont.time)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if isNextAlarm {
                    Text("NEXT")
                        .font(CalarmFont.captionSemibold)
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accent, in: Capsule())
                }
            }
            .frame(width: CalarmTheme.timeColumnWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(CalarmFont.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if event.alarmEnabled {
                        Text(event.alarmSummary)
                            .font(CalarmFont.caption)
                            .foregroundStyle(theme.accentMuted)
                    } else {
                        Text("Alarm off")
                            .font(CalarmFont.caption)
                            .foregroundStyle(theme.textSecondary)
                    }

                    if event.isAlarmInPast {
                        Text("Past")
                            .font(CalarmFont.captionSemibold)
                            .foregroundStyle(.red.opacity(0.75))
                    }

                    if hasTooSoonWarning {
                        Text("Too soon to schedule")
                            .font(CalarmFont.captionSemibold)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            Button(action: onToggle) {
                Image(systemName: event.alarmEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(event.alarmEnabled ? theme.accent : theme.textSecondary)
                    .frame(width: CalarmTheme.bellTapSize, height: CalarmTheme.bellTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(event.alarmEnabled ? "Turn alarm off" : "Turn alarm on")
        }
        .listRowBackground(
            isNextAlarm
                ? theme.accent.opacity(0.08)
                : Color.clear
        )
    }
}
