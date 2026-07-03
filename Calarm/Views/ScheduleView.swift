//
//  ScheduleView.swift
//  Calarm
//

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
        store.authorizationStatus == .fullAccess && !store.schedulableEvents.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScheduleHeaderBar(
                    theme: theme,
                    canManageAlarms: canManageAlarms,
                    allAlarmsEnabled: store.allAlarmsEnabled,
                    hasEnabledAlarms: store.schedulableEvents.contains(where: \.alarmEnabled),
                    canRefresh: store.authorizationStatus == .fullAccess,
                    onTurnAllOn: { store.setAllAlarmsEnabled(true) },
                    onTurnAllOff: { store.setAllAlarmsEnabled(false) },
                    onRefresh: { Task { await store.reload() } },
                    onSettings: { showingSettings = true }
                )

                ZStack {
                    theme.background.ignoresSafeArea()

                    Group {
                        if store.authorizationStatus != .fullAccess {
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
        }
        .font(CalarmFont.body)
    }

    private var scheduleList: some View {
        List {
            ForEach(store.groupedDays) { day in
                Section {
                    ForEach(day.events) { event in
                        EventRow(
                            event: event,
                            isNextAlarm: store.nextUpcomingAlarm?.id == event.id,
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

            Text(store.authorizationStatus == .denied ? "Calendar access is off" : "See your week at a glance")
                .font(CalarmFont.title3)
                .foregroundStyle(theme.textPrimary)

            Text(accessPromptMessage)
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if store.authorizationStatus == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            } else {
                Button("Allow Calendar Access") {
                    Task { await store.requestCalendarAccess() }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
        }
        .padding()
    }

    private var accessPromptMessage: String {
        if store.authorizationStatus == .denied {
            return "Enable calendar access in Settings to see your schedule and set event alarms."
        }
        return "CALarm shows upcoming calendar events for the next 7 days. Turn on an alarm per event when you want a reminder."
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(theme.accent.opacity(0.8))
            Text("No upcoming events")
                .font(CalarmFont.headline)
                .foregroundStyle(theme.textPrimary)
            Text("Nothing scheduled in the next 7 days.")
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)
        }
    }
}

private struct EventRow: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    let event: ScheduleEvent
    let isNextAlarm: Bool
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
