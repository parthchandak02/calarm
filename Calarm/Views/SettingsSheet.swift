//
//  SettingsSheet.swift
//  Calarm
//

import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var store: ScheduleStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var theme: CalarmTheme {
        themeStore.theme(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    defaultAlarmSection
                    snoozeSection
                    appearanceSection
                    accentSection
                }
                .padding(20)
                .padding(.bottom, 8)
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
        .id(themeStore.themeToken)
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

            Text("Used when you turn an alarm on from the schedule list or add your first alarm to an event.")
                .font(CalarmFont.subheadline)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            AlarmOffsetListPicker(
                options: AlarmOffsetOption.allCases,
                selected: store.defaultAlarmOffset,
                theme: theme
            ) { offset in
                store.updateDefaultAlarmOffset(offset)
            }
        }
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
                        isSelected: store.defaultSnooze == option,
                        theme: theme
                    ) {
                        store.updateDefaultSnooze(option)
                    }

                    if index < SnoozeDurationOption.allCases.count - 1 {
                        Divider().overlay(theme.surfaceStroke)
                    }
                }
            }
        }
    }
}
