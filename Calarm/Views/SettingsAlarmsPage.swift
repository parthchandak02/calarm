//
//  SettingsAlarmsPage.swift
//  Calarm
//

import SwiftUI

struct SettingsAlarmsPage: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.calarmTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(SettingsSummary.alarmsSentence(
                    offset: store.defaultAlarmOffset,
                    snooze: store.defaultSnooze,
                    vibrates: store.vibrateInsteadOfRinging || store.focusVibrate
                ))
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

                BoardSectionLabel(title: "Default alarm · min before")
                FlapPicker(
                    options: AlarmOffsetOption.defaultPreferenceOptions,
                    selection: store.defaultAlarmOffset,
                    tileLabel: SettingsSummary.offsetTile,
                    accessibilityLabel: \.title,
                    onSelect: store.updateDefaultAlarmOffset
                )

                BoardSectionLabel(title: "Snooze · min")
                FlapPicker(
                    options: SnoozeDurationOption.allCases,
                    selection: store.defaultSnooze,
                    tileLabel: SettingsSummary.snoozeTile,
                    accessibilityLabel: \.title,
                    onSelect: store.updateDefaultSnooze
                )

                BoardSectionLabel(title: "Island · min before ring")
                FlapPicker(
                    options: LiveActivityLead.allCases,
                    selection: store.liveActivityLead,
                    columns: 4,
                    tileLabel: SettingsSummary.leadTile,
                    accessibilityLabel: { $0 == .always ? "Live Activity always" : "Live Activity \($0.title)" },
                    onSelect: store.setLiveActivityLead
                )
                .accessibilityIdentifier("settings.alarms.liveActivityLead")

                Text("The Live Activity appears this long before the alarm rings.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)

                BoardSectionLabel(title: "Sound")
                FlapPicker(
                    options: [false, true],
                    selection: store.vibrateInsteadOfRinging,
                    columns: 2,
                    tileLabel: { $0 ? "VIBRATE" : "RING" },
                    accessibilityLabel: { $0 ? "Vibrate instead of ringing" : "Ring" },
                    onSelect: store.setVibrateInsteadOfRinging
                )
                .accessibilityIdentifier("settings.alarms.vibrateInsteadOfRinging")

                if store.focusVibrate {
                    Text("Vibrating now because of a Focus.")
                        .font(CalarmFont.boardDetail)
                        .foregroundStyle(theme.accent)
                        .padding(.top, 10)
                }

                Text("iOS doesn’t let apps see the silent switch. A Focus can turn vibrate on: iOS Settings → Focus → Focus Filters → CALarm.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .padding(.bottom, 24)
        }
        .boardNavigationTitle("Alarms")
    }
}
