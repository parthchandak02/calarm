//
//  SettingsSheet.swift
//  Calarm
//

import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var defaultAlarmOffset: AlarmOffsetOption
    @State private var defaultSnooze: SnoozeDurationOption

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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                developerInfoBar
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .calarmToolbarChrome(theme: theme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Settings")
                            .font(CalarmFont.bodyMedium)
                        Text("Build \(AppBuildInfo.formattedBuildStamp)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
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
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
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
