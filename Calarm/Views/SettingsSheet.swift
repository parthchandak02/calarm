//
//  SettingsSheet.swift
//  Calarm
//

import SwiftUI
import UIKit

enum SettingsPage: Hashable {
    case alarms
    case calendars
    case look
    case status
}

/// Settings as a departure board: the root shows each area's current state on one line
/// and pushes into it, so most visits end without a tap.
struct SettingsSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: CalarmTheme {
        themeStore.theme(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BoardSectionLabel(title: "System")
                    link(.alarms, title: "Alarms") {
                        BoardValue(
                            text: SettingsSummary.alarmsLine(
                                offset: store.defaultAlarmOffset,
                                snooze: store.defaultSnooze,
                                vibrates: store.vibrateInsteadOfRinging || store.focusVibrate
                            ),
                            color: theme.accent,
                            showsChevron: true
                        )
                    }
                    link(.calendars, title: "Calendars") {
                        BoardValue(text: calendarsValue, showsChevron: true)
                    }
                    link(.look, title: "Look") {
                        BoardValue(
                            text: "\(themeStore.accent.title.lowercased()) · \(themeStore.appearance.title.lowercased())",
                            showsChevron: true
                        )
                    }
                    link(.status, title: "Status") {
                        let problems = store.statusProblems
                        HStack(spacing: 8) {
                            StatusLight(isProblem: !problems.isEmpty)
                            BoardValue(
                                text: problems.isEmpty ? "all good" : "\(problems.count) issue\(problems.count == 1 ? "" : "s")",
                                color: problems.isEmpty ? nil : theme.destructive,
                                showsChevron: true
                            )
                        }
                    }

                    NextRingBlock()
                    TestAlarmButton()
                        .padding(.top, 16)

                    BoardButton(title: "Show tips again", systemImage: "lightbulb") {
                        CalarmTips.replay()
                        dismiss()
                    }
                    .padding(.top, 8)
                    .accessibilityIdentifier("settings.showTips")

                    buildInfo
                        .padding(.top, 32)
                }
                .padding(.horizontal, CalarmTheme.rowPaddingH)
                .padding(.bottom, 24)
            }
            .background(SettingsBackdrop())
            .boardNavigationTitle("Settings")
            .calarmTransparentToolbarChrome(theme: theme)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: SettingsPage.self) { page in
                Group {
                    switch page {
                    case .alarms: SettingsAlarmsPage()
                    case .calendars: SettingsCalendarsPage()
                    case .look: SettingsLookPage()
                    case .status: SettingsStatusPage()
                    }
                }
                .background(SettingsBackdrop())
                .calarmTransparentToolbarChrome(theme: theme)
            }
        }
        .environment(\.calarmTheme, theme)
        .tint(theme.accent)
        .calarmNavigationStyle(theme: theme, isTransparent: true)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            SettingsBackdrop()
                .environment(\.calarmTheme, theme)
        }
        .accessibilityIdentifier("settings.sheet")
    }

    private func link<Value: View>(_ page: SettingsPage, title: String, @ViewBuilder value: @escaping () -> Value) -> some View {
        NavigationLink(value: page) {
            BoardLine(title: title, trailing: value)
        }
        .buttonStyle(.plain)
    }

    private var calendarsValue: String {
        let eventKit = store.calendarService.availableCalendars
        let google = store.googleCalendarService.isConnected ? store.googleCalendarService.availableCalendars : []
        let enabled = eventKit.filter(\.isEnabled).count
            + google.filter { store.googleCalendarService.isCalendarEnabled($0.id) }.count
        return SettingsSummary.calendarsLine(
            enabled: enabled,
            total: eventKit.count + google.count,
            googleConnected: store.googleCalendarService.isConnected
        )
    }

    private var buildInfo: some View {
        VStack(spacing: 4) {
            Text("\(AppBuildInfo.appName) \(AppBuildInfo.marketingVersion) · Build \(AppBuildInfo.formattedBuildStamp)")
            Text("\(AppBuildInfo.developerName) · © \(AppBuildInfo.copyrightYear)")
        }
        .font(CalarmFont.boardDetail)
        .foregroundStyle(theme.textSecondary.opacity(0.7))
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("settings.developerInfo")
    }
}

/// "NEXT RING 10:59 · Product sync", shared by the Settings root and Status.
struct NextRingBlock: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.calarmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BoardSectionLabel(title: "Next ring")
            if let next = store.nextUpcomingAlarm, let fire = next.nextAlarmDate {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(CalarmTheme.eventTimeString(fire))
                        .font(CalarmFont.title)
                        .foregroundStyle(theme.accent)
                        .monospacedDigit()
                    Text(next.title)
                        .font(CalarmFont.boardDetail)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Nothing is set to ring.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }
}

struct TestAlarmButton: View {
    @EnvironmentObject private var store: ScheduleStore

    var isProminent = false

    @State private var isScheduling = false
    @State private var message: String?

    var body: some View {
        BoardButton(
            title: isScheduling ? "Scheduling…" : "Test alarm · \(Int(AlarmScheduler.testAlarmExpectedRing(lead: store.liveActivityLead)))s",
            systemImage: "play.fill",
            isProminent: isProminent,
            isDisabled: isScheduling,
            action: run
        )
        .accessibilityIdentifier("settings.testAlarm")
        .alert("Test alarm", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func run() {
        #if targetEnvironment(simulator)
        message = "Test alarms must be run on a physical iPhone — the Simulator cannot ring."
        #else
        isScheduling = true
        Task {
            message = await store.scheduleTestAlarm()
                ?? "Test alarm scheduled — it should ring in about 8 seconds. Keep CALarm open so Alarm timing can measure it."
            isScheduling = false
        }
        #endif
    }
}
