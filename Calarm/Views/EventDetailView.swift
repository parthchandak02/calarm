//
//  EventDetailView.swift
//  Calarm
//

import SwiftUI

struct EventDetailView: View {
    @EnvironmentObject private var store: ScheduleStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let eventID: String

    @State private var showingAddAlarm = false

    private var theme: CalarmTheme {
        themeStore.theme(colorScheme: colorScheme)
    }

    private var event: ScheduleEvent? {
        store.event(with: eventID)
    }

    private var availableOffsets: [AlarmOffsetOption] {
        store.availableAlarmOffsets(for: eventID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let event {
                    header(for: event)
                    alarmsSection(for: event)
                } else {
                    ContentUnavailableView("Event not found", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .padding(20)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .calarmToolbarChrome(theme: theme)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(CalarmFont.bodyMedium)
                    .foregroundStyle(theme.accent)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showingAddAlarm) {
            if let event {
                AlarmOffsetSelectionSheet(
                    title: "Add alarm",
                    options: availableOffsets,
                    theme: theme
                ) { offset in
                    store.addAlarmOffset(offset, for: eventID)
                }
                .environmentObject(themeStore)
            }
        }
        .font(CalarmFont.body)
        .calarmNavigationStyle(theme: theme)
        .id(themeStore.themeToken)
        .accessibilityIdentifier("event.detail")
        .onAppear {
            if ScreenshotMode.isEnabled, ScreenshotMode.scene == .addAlarm, eventID == ScreenshotDemoData.featuredEventID {
                showingAddAlarm = true
            }
        }
    }

    @ViewBuilder
    private func header(for event: ScheduleEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.title)
                .font(CalarmFont.title2)
                .foregroundStyle(theme.textPrimary)

            Label(eventTimeRange(for: event), systemImage: "calendar")
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)

            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(CalarmFont.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }

            Text(event.calendarTitle)
                .font(CalarmFont.captionSemibold)
                .foregroundStyle(theme.accentMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.accent.opacity(0.15), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func alarmsSection(for event: ScheduleEvent) -> some View {
        let sortedOffsets = event.alarmOffsets.sorted {
            $0.fireDate(for: event.startDate) < $1.fireDate(for: event.startDate)
        }

        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Alarms", theme: theme)

            if sortedOffsets.isEmpty {
                Text("No alarms for this event. Add one to get reminded before it starts.")
                    .font(CalarmFont.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SettingsOptionList(theme: theme) {
                    ForEach(Array(sortedOffsets.enumerated()), id: \.element.id) { index, offset in
                        alarmRow(offset: offset, event: event)

                        if index < sortedOffsets.count - 1 {
                            Divider().overlay(theme.surfaceStroke)
                        }
                    }
                }
            }

            if !availableOffsets.isEmpty {
                Button {
                    showingAddAlarm = true
                } label: {
                    Label("Add alarm", systemImage: "plus.circle.fill")
                        .font(CalarmFont.subheadlineSemibold)
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func alarmRow(offset: AlarmOffsetOption, event: ScheduleEvent) -> some View {
        let fireDate = offset.fireDate(for: event.startDate)
        let isPast = fireDate <= Date()

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(offset.title)
                    .font(CalarmFont.bodyMedium)
                    .foregroundStyle(theme.textPrimary)

                Text(alarmTimeLabel(for: fireDate, isPast: isPast))
                    .font(CalarmFont.caption)
                    .foregroundStyle(isPast ? .red.opacity(0.75) : theme.textSecondary)
            }

            Spacer()

            Button {
                store.removeAlarmOffset(offset, for: eventID)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(offset.title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
    }

    private func eventTimeRange(for event: ScheduleEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate)
    }

    private func alarmTimeLabel(for fireDate: Date, isPast: Bool) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: fireDate)
        if isPast {
            return "Passed · was \(time)"
        }
        return "Rings at \(time)"
    }
}
