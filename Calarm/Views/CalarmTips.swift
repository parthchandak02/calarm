//
//  CalarmTips.swift
//  Calarm
//

import AlarmKit
import EventKit
import SwiftUI
import TipKit

/// First-run tips. Each tip's ID carries a generation so "Show tips again" in Settings can
/// bring every tip back without a relaunch: `Tips.resetDatastore()` only works before
/// `Tips.configure()`, so a replay has to present tips TipKit has never seen.
nonisolated enum CalarmTips {
    static let generationKey = "calarm.tips.generation"
    private static let seededKey = "calarm.tips.seeded"

    @Parameter static var isActive: Bool = true

    static var generation: Int {
        UserDefaults.standard.integer(forKey: generationKey)
    }

    @MainActor
    static func configure() {
        if ScreenshotMode.isEnabled {
            Tips.hideAllTipsForTesting()
        }
        try? Tips.configure()
        seedIfNeeded()
    }

    static func replay() {
        UserDefaults.standard.set(generation + 1, forKey: generationKey)
        isActive = true
    }

    @MainActor
    static func scheduleGroup(generation: Int) -> TipGroup {
        TipGroup(.ordered) {
            ArmAlarmTip(generation: generation)
            OpenEventTip(generation: generation)
            BulkAlarmsTip(generation: generation)
            SettingsTip(generation: generation)
        }
    }

    /// Runs once per install, before anything asks for permission, so the permission
    /// states still say whether this person has used CALarm before.
    @MainActor
    private static func seedIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)

        let signals = TutorialEligibility.Signals(
            alarmPermissionAsked: AlarmManager.shared.authorizationState != .notDetermined,
            calendarPermissionAsked: EKEventStore.authorizationStatus(for: .event) != .notDetermined,
            googleConnected: GoogleCalendarPreferences().isConnected,
            hasSavedPreferences: savedPreferenceKeys.contains(where: CalarmPersistence.objectExists)
        )
        if TutorialEligibility.isReturningUser(signals) {
            isActive = false
        }
    }

    @MainActor
    private static var savedPreferenceKeys: [String] {
        typealias Key = CalarmPersistence.Key
        return [
            Key.defaultAlarmOffset, Key.legacyDefaultOffsetMinutes, Key.defaultSnoozeMinutes,
            Key.eventOverrides, Key.themeAccent, Key.themeAppearance,
            Key.enabledCalendarIDs, Key.disabledCalendarIDs,
        ]
    }
}

nonisolated struct ConnectCalendarTip: Tip {
    let generation: Int
    var id: String { "calarm.tip.connectCalendar.\(generation)" }
    var title: Text { Text("Start with your calendar") }
    var message: Text? { Text("CALarm reads your events from Apple Calendar, or from Google through Settings.") }
    var image: Image? { Image(systemName: "calendar") }
    var rules: [Rule] { [#Rule(CalarmTips.$isActive) { $0 }] }
}

nonisolated struct ArmAlarmTip: Tip {
    let generation: Int
    var id: String { "calarm.tip.armAlarm.\(generation)" }
    var title: Text { Text("Tap the square to arm") }
    var message: Text? { Text("A lit square rings as a real alarm. The first time, iOS asks to allow alarms.") }
    var image: Image? { Image(systemName: "square.fill") }
    var rules: [Rule] { [#Rule(CalarmTips.$isActive) { $0 }] }
}

nonisolated struct OpenEventTip: Tip {
    let generation: Int
    var id: String { "calarm.tip.openEvent.\(generation)" }
    var title: Text { Text("Tap an event for more") }
    var message: Text? { Text("Choose when it rings, or give it more than one alarm.") }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Rule] { [#Rule(CalarmTips.$isActive) { $0 }] }
}

nonisolated struct BulkAlarmsTip: Tip {
    let generation: Int
    var id: String { "calarm.tip.bulkAlarms.\(generation)" }
    var title: Text { Text("Arm everything at once") }
    var message: Text? { Text("Turn every upcoming alarm on or off from here.") }
    var image: Image? { Image(systemName: "bell.badge") }
    var rules: [Rule] { [#Rule(CalarmTips.$isActive) { $0 }] }
}

nonisolated struct SettingsTip: Tip {
    let generation: Int
    var id: String { "calarm.tip.settings.\(generation)" }
    var title: Text { Text("Set your defaults") }
    var message: Text? { Text("How early new events ring, when the Island countdown starts, and a test alarm.") }
    var image: Image? { Image(systemName: "gearshape") }
    var rules: [Rule] { [#Rule(CalarmTips.$isActive) { $0 }] }
}

struct BoardTipStyle: TipViewStyle {
    let theme: CalarmTheme

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.image?
                .font(.title3)
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                configuration.title?
                    .font(CalarmFont.headline)
                    .foregroundStyle(theme.textPrimary)
                configuration.message?
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(16)
    }
}

extension View {
    func calarmTipStyle(_ theme: CalarmTheme) -> some View {
        tipViewStyle(BoardTipStyle(theme: theme))
            .tipBackground(theme.background)
    }
}
