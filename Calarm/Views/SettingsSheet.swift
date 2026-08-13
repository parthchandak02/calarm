//
//  SettingsSheet.swift
//  Calarm
//

import AlarmKit
import EventKit
import SwiftUI
import UIKit

private enum SettingsTab: String, SettingsTabItem {
    case calendars
    case alarms
    case look
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendars: "Calendar"
        case .alarms: "Alarms"
        case .look: "Look"
        case .status: "Status"
        }
    }

    var systemImage: String {
        switch self {
        case .calendars: "calendar"
        case .alarms: "bell"
        case .look: "paintbrush"
        case .status: "waveform.path.ecg"
        }
    }

    var accessibilityIdentifier: String {
        "settings.tab.\(rawValue)"
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var defaultAlarmOffset: AlarmOffsetOption
    @State private var defaultSnooze: SnoozeDurationOption
    @State private var testAlarmMessage: String?
    @State private var isSchedulingTestAlarm = false
    @State private var googleConnectError: String?
    @State private var isConnectingGoogle = false
    @State private var selectedTab: SettingsTab = .calendars

    private let onDefaultAlarmOffsetChange: (AlarmOffsetOption) -> Void
    private let onDefaultSnoozeChange: (SnoozeDurationOption) -> Void

    init(
        defaultAlarmOffset: AlarmOffsetOption,
        defaultSnooze: SnoozeDurationOption,
        onDefaultAlarmOffsetChange: @escaping (AlarmOffsetOption) -> Void,
        onDefaultSnoozeChange: @escaping (SnoozeDurationOption) -> Void
    ) {
        _defaultAlarmOffset = State(initialValue: defaultAlarmOffset)
        _defaultSnooze = State(initialValue: defaultSnooze)
        self.onDefaultAlarmOffsetChange = onDefaultAlarmOffsetChange
        self.onDefaultSnoozeChange = onDefaultSnoozeChange
    }

    private var theme: CalarmTheme {
        themeStore.theme(colorScheme: colorScheme)
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SettingsTabBar(selection: $selectedTab, theme: theme)
                    .padding(.horizontal, CalarmTheme.screenPaddingH)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView {
                    tabContent
                        .padding(.horizontal, CalarmTheme.screenPaddingH)
                        .padding(.bottom, 8)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                developerInfoBar
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
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
        }
        .font(CalarmFont.body)
        .calarmNavigationStyle(theme: theme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.background)
        .accessibilityIdentifier("settings.sheet")
        .alert("Test alarm", isPresented: Binding(
            get: { testAlarmMessage != nil },
            set: { if !$0 { testAlarmMessage = nil } }
        )) {
            Button("OK", role: .cancel) { testAlarmMessage = nil }
        } message: {
            Text(testAlarmMessage ?? "")
        }
        .alert("Google Calendar", isPresented: Binding(
            get: { googleConnectError != nil },
            set: { if !$0 { googleConnectError = nil } }
        )) {
            Button("OK", role: .cancel) { googleConnectError = nil }
        } message: {
            Text(googleConnectError ?? "")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .calendars:
            VStack(alignment: .leading, spacing: 28) {
                googleCalendarSection
                calendarsSection
            }
            .accessibilityIdentifier("settings.panel.calendars")
        case .alarms:
            VStack(alignment: .leading, spacing: 28) {
                defaultAlarmSection
                snoozeSection
            }
            .accessibilityIdentifier("settings.panel.alarms")
        case .look:
            VStack(alignment: .leading, spacing: 28) {
                appearanceSection
                accentSection
            }
            .accessibilityIdentifier("settings.panel.look")
        case .status:
            diagnosticsSection
                .accessibilityIdentifier("settings.panel.status")
        }
    }

    private var googleCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Google Calendar", theme: theme)

            Text("Connect Google for faster updates than iOS Calendar sync. iCloud and other calendars still use EventKit.")
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsOptionList(theme: theme) {
                if store.googleCalendarService.isConnected {
                    SettingsInfoRow(
                        title: "Account",
                        value: store.googleCalendarService.connectedEmail ?? "Connected",
                        theme: theme
                    )

                    Divider().overlay(theme.surfaceStroke)

                    if store.googleCalendarService.availableCalendars.isEmpty {
                        Text("Loading Google calendars…")
                            .font(CalarmFont.caption)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, CalarmTheme.rowPaddingH)
                            .frame(height: CalarmTheme.settingsRowHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.surface)
                    } else {
                        ForEach(Array(store.googleCalendarService.availableCalendars.enumerated()), id: \.element.id) { index, calendar in
                            SettingsToggleRow(
                                isOn: Binding(
                                    get: { store.googleCalendarService.isCalendarEnabled(calendar.id) },
                                    set: { enabled in
                                        store.googleCalendarService.setCalendarEnabled(calendar.id, enabled: enabled)
                                        Task { await store.reload() }
                                    }
                                ),
                                theme: theme
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(calendar.title)
                                        .font(CalarmFont.bodyMedium)
                                        .foregroundStyle(theme.textPrimary)
                                    if calendar.isBusyOnly {
                                        Text("Busy blocks only")
                                            .font(CalarmFont.caption)
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                }
                            }

                            if index < store.googleCalendarService.availableCalendars.count - 1 {
                                Divider().overlay(theme.surfaceStroke)
                            }
                        }
                    }

                    Divider().overlay(theme.surfaceStroke)

                    SettingsActionRow(
                        title: "Disconnect Google",
                        theme: theme,
                        titleColor: theme.destructive
                    ) {
                        store.disconnectGoogleCalendar()
                    }
                } else if GoogleOAuthConfig.isConfigured {
                    SettingsActionRow(
                        title: isConnectingGoogle ? "Connecting…" : "Connect Google Calendar",
                        theme: theme,
                        systemImage: "person.crop.circle.badge.plus",
                        isDisabled: isConnectingGoogle
                    ) {
                        guard let presenter = UIApplication.shared.calarmTopViewController else {
                            googleConnectError = "Could not present Google sign-in."
                            return
                        }
                        isConnectingGoogle = true
                        Task {
                            do {
                                try await store.connectGoogleCalendar(from: presenter)
                            } catch {
                                googleConnectError = error.localizedDescription
                            }
                            isConnectingGoogle = false
                        }
                    }
                } else {
                    Text("Add GoogleService-Info.plist to enable Google Calendar. See scripts/setup-google-oauth.sh.")
                        .font(CalarmFont.caption)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, CalarmTheme.rowPaddingH)
                        .frame(minHeight: CalarmTheme.settingsRowHeight, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface)
                }
            }

            if store.googleCalendarService.isConnected {
                Text("Google events refresh whenever you open CALarm. iOS may still delay EventKit copies of the same calendars.")
                    .font(CalarmFont.caption)
                    .foregroundStyle(theme.textSecondary)
            } else {
                Text("Without Google connect, calendars added in iOS Settings sync on Apple's schedule — often minutes behind. Open the Calendar app to force a refresh.")
                    .font(CalarmFont.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Calendars", theme: theme)

            Text("Choose which calendars CALarm reads for upcoming events.")
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)

            if store.calendarService.availableCalendars.isEmpty {
                Text(store.authorizationStatus == .fullAccess ? "No calendars found." : "Grant calendar access to choose calendars.")
                    .font(CalarmFont.caption)
                    .foregroundStyle(theme.textSecondary)
            } else {
                SettingsOptionList(theme: theme) {
                    ForEach(Array(store.calendarService.availableCalendars.enumerated()), id: \.element.id) { index, calendar in
                        SettingsToggleRow(
                            isOn: Binding(
                                get: { calendar.isEnabled },
                                set: { enabled in
                                    store.calendarService.setCalendarEnabled(calendar.id, enabled: enabled)
                                    Task { await store.reload() }
                                }
                            ),
                            theme: theme
                        ) {
                            Text(calendar.title)
                                .font(CalarmFont.bodyMedium)
                                .foregroundStyle(theme.textPrimary)
                        }

                        if index < store.calendarService.availableCalendars.count - 1 {
                            Divider().overlay(theme.surfaceStroke)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Diagnostics", theme: theme)

            SettingsOptionList(theme: theme) {
                SettingsInfoRow(title: "Calendar", value: calendarStatusLabel, theme: theme)
                Divider().overlay(theme.surfaceStroke)
                SettingsInfoRow(title: "Alarms", value: alarmStatusLabel, theme: theme)
                Divider().overlay(theme.surfaceStroke)
                SettingsInfoRow(title: "Next ring", value: nextRingLabel, theme: theme)
                Divider().overlay(theme.surfaceStroke)
                SettingsInfoRow(title: "Last reschedule", value: lastRescheduleLabel, theme: theme)

                Divider().overlay(theme.surfaceStroke)

                SettingsActionRow(
                    title: isSchedulingTestAlarm ? "Scheduling…" : "Test alarm (8 seconds)",
                    theme: theme,
                    systemImage: "bell.badge",
                    isDisabled: isSchedulingTestAlarm
                ) {
                    guard !isSimulator else {
                        testAlarmMessage = "Test alarms must be run on a physical iPhone — the Simulator cannot ring."
                        return
                    }
                    isSchedulingTestAlarm = true
                    Task {
                        testAlarmMessage = await store.scheduleTestAlarm()
                            ?? "Test alarm scheduled — it should ring in about 8 seconds."
                        isSchedulingTestAlarm = false
                    }
                }
                .accessibilityIdentifier("settings.testAlarm")
            }

            if isSimulator {
                Text("Alarm sound and AlarmKit behavior require a physical device.")
                    .font(CalarmFont.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var calendarStatusLabel: String {
        switch store.authorizationStatus {
        case .fullAccess: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .writeOnly: "Write only"
        @unknown default: "Unknown"
        }
    }

    private var alarmStatusLabel: String {
        switch store.alarmAuthorization {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .notDetermined: "Not asked"
        @unknown default: "Unknown"
        }
    }

    private var nextRingLabel: String {
        guard let next = store.nextUpcomingAlarm, let fire = next.nextAlarmDate else {
            return "None scheduled"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(next.title) · \(formatter.string(from: fire))"
    }

    private var lastRescheduleLabel: String {
        guard let summary = store.lastRescheduleSummary else { return "—" }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return "\(formatter.string(from: summary.finishedAt)) · \(summary.scheduledCount) ok"
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Appearance", theme: theme)

            SettingsOptionList(theme: theme) {
                ForEach(Array(CalarmAppearance.allCases.enumerated()), id: \.element.id) { index, mode in
                    SettingsOptionRow(
                        title: mode.title,
                        isSelected: themeStore.appearance == mode,
                        theme: theme
                    ) {
                        themeStore.appearance = mode
                    }

                    if index < CalarmAppearance.allCases.count - 1 {
                        Divider().overlay(theme.surfaceStroke)
                    }
                }
            }
        }
    }

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Accent color", theme: theme)

            SettingsOptionList(theme: theme) {
                ForEach(Array(CalarmAccent.allCases.enumerated()), id: \.element.id) { index, choice in
                    SettingsOptionRow(
                        title: choice.title,
                        isSelected: themeStore.accent == choice,
                        theme: theme,
                        leading: {
                            AnyView(AccentColorDot(accent: choice, theme: theme))
                        }
                    ) {
                        themeStore.accent = choice
                    }

                    if index < CalarmAccent.allCases.count - 1 {
                        Divider().overlay(theme.surfaceStroke)
                    }
                }
            }
        }
    }

    private var defaultAlarmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Default alarm", theme: theme)

            Text("New calendar events use this setting automatically. Choose “No alarm” to leave them off until you turn an alarm on.")
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AlarmOffsetListPicker(
                options: AlarmOffsetOption.defaultPreferenceOptions,
                selected: defaultAlarmOffset,
                theme: theme
            ) { offset in
                defaultAlarmOffset = offset
                onDefaultAlarmOffsetChange(offset)
            }
        }
    }

    private var developerInfoBar: some View {
        VStack(spacing: 4) {
            Divider().overlay(theme.surfaceStroke)

            Text(AppBuildInfo.appName)
                .font(CalarmFont.captionSemibold)
                .foregroundStyle(theme.textSecondary)

            Text("Version \(AppBuildInfo.marketingVersion) · Build \(AppBuildInfo.formattedBuildStamp)")
                .font(CalarmFont.caption)
                .foregroundStyle(theme.textSecondary.opacity(0.9))
                .monospacedDigit()

            Text("\(AppBuildInfo.developerName) · © \(AppBuildInfo.copyrightYear)")
                .font(CalarmFont.caption)
                .foregroundStyle(theme.textSecondary.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.horizontal, CalarmTheme.screenPaddingH)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(theme.background)
        .accessibilityIdentifier("settings.developerInfo")
    }

    private var snoozeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Snooze duration", theme: theme)

            Text("How long to wait when you snooze an alarm from the lock screen.")
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsOptionList(theme: theme) {
                ForEach(Array(SnoozeDurationOption.allCases.enumerated()), id: \.element.id) { index, option in
                    SettingsOptionRow(
                        title: option.title,
                        isSelected: defaultSnooze == option,
                        theme: theme
                    ) {
                        defaultSnooze = option
                        onDefaultSnoozeChange(option)
                    }

                    if index < SnoozeDurationOption.allCases.count - 1 {
                        Divider().overlay(theme.surfaceStroke)
                    }
                }
            }
        }
    }
}
