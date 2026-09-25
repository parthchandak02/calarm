//
//  SettingsStatusPage.swift
//  Calarm
//

import AlarmKit
import EventKit
import SwiftUI
import UIKit

extension ScheduleStore {
    var statusProblems: [StatusVerdict.Problem] {
        StatusVerdict.problems(for: StatusVerdict.Input(
            alarmsDenied: alarmAuthorization == .denied,
            hasEventSource: hasEventSource,
            googleSyncError: googleSyncErrorMessage,
            scheduleFailureCount: scheduleFailures.count,
            firstScheduleFailure: scheduleFailures.first.map { "\($0.eventTitle): \($0.message)" },
            timingLateSeconds: {
                switch AlarmJournalStore.testProbeVerdict() {
                case .countdownStartsAtFireDate(let seconds), .other(let seconds): seconds
                default: nil
                }
            }(),
            timingEarlySeconds: {
                if case .early(let seconds) = AlarmJournalStore.testProbeVerdict() { return seconds }
                return nil
            }(),
            timingExpectedSeconds: Int(AlarmJournalStore.testProbeExpectedRing() ?? 8)
        ))
    }
}

/// An activity log: what CALarm did, newest first, with any current problem pinned on top
/// as a NOW line carrying its fix. The owner debugs "why didn't it ring?" this way.
struct SettingsStatusPage: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.calarmTheme) private var theme

    @State private var entries: [ActivityLog.Entry] = []

    var body: some View {
        let problems = store.statusProblems
        let days = ActivityLog.days(entries, now: .now)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !problems.isEmpty {
                    BoardSectionLabel(title: "Now")
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            logLine(time: "NOW", kind: .fail, text: "\(problem.title) · \(problem.detail)")
                            fixButton(problem.fix)
                        }
                    }
                }

                if days.isEmpty {
                    BoardSectionLabel(title: "Today")
                    Text("Nothing logged yet. Entries appear as CALarm syncs, schedules and rings.")
                        .font(CalarmFont.boardDetail)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(days, id: \.title) { day in
                        BoardSectionLabel(title: day.title)
                        ForEach(Array(day.entries.enumerated()), id: \.offset) { _, entry in
                            logLine(time: CalarmTheme.eventTimeString(entry.date), kind: entry.kind, text: entry.text)
                        }
                    }
                }

                TestAlarmButton()
                    .padding(.top, 20)

                Text("Log stays on this phone and is cleared after 7 days.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 10)

                Text(checks.map { "\($0.title.lowercased()) \($0.value)" }.joined(separator: " · "))
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)

                #if targetEnvironment(simulator)
                Text("Alarm sound and AlarmKit behavior require a physical device.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 6)
                #endif
            }
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .padding(.bottom, 24)
        }
        .refreshable { entries = ActivityLog.load() }
        .onAppear { entries = ActivityLog.load() }
        .onChange(of: store.lastRescheduleSummary) { _, _ in entries = ActivityLog.load() }
        .boardNavigationTitle("Status")
    }

    private func logLine(time: String, kind: ActivityLog.Kind, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(time)
                .foregroundStyle(theme.textPrimary)
                .frame(width: 64, alignment: .leading)
            Text(kind.label)
                .foregroundStyle(color(for: kind))
            Text(text)
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(CalarmFont.boardDetail)
        .monospacedDigit()
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func color(for kind: ActivityLog.Kind) -> Color {
        switch kind {
        case .fail: theme.destructive
        case .resched, .rang, .snoozed, .dismissed, .test: theme.accent
        case .sync, .focus: theme.textSecondary
        }
    }

    @ViewBuilder
    private func fixButton(_ fix: StatusVerdict.Fix) -> some View {
        switch fix {
        case .openSystemSettings:
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.glass)
            .font(CalarmFont.boardDetail)
        case .retrySync:
            Button("Retry") {
                store.clearGoogleSyncError()
                store.clearScheduleFailures()
                Task { await store.reload() }
            }
            .buttonStyle(.glass)
            .font(CalarmFont.boardDetail)
        case .runTestAlarm:
            EmptyView()
        }
    }

    private struct Check {
        let title: String
        let value: String
        let isProblem: Bool
    }

    private var checks: [Check] {
        [
            Check(title: "Calendar access", value: calendarStatusLabel, isProblem: !store.hasEventSource),
            Check(title: "Alarm access", value: alarmStatusLabel, isProblem: store.alarmAuthorization == .denied),
            Check(title: "Google", value: googleLabel, isProblem: store.googleSyncErrorMessage != nil),
            Check(title: "Alarm timing", value: alarmTimingLabel, isProblem: isTimingLate),
            Check(title: "Last reschedule", value: lastRescheduleLabel, isProblem: !store.scheduleFailures.isEmpty),
            Check(title: "Events loaded", value: eventSourceLabel, isProblem: false),
        ]
    }

    private var isTimingLate: Bool {
        switch AlarmJournalStore.testProbeVerdict() {
        case .countdownStartsAtFireDate, .other, .early: true
        default: false
        }
    }

    private var alarmTimingLabel: String {
        switch AlarmJournalStore.testProbeVerdict() {
        case nil: "Not measured"
        case .pending: "Waiting for ring"
        case .onTime(let seconds): "On time · \(seconds)s"
        case .early(let seconds): "Early · \(seconds)s"
        case .countdownStartsAtFireDate(let seconds): "Late · \(seconds)s"
        case .other(let seconds): "Unexpected · \(seconds)s"
        }
    }

    private var calendarStatusLabel: String {
        switch store.authorizationStatus {
        case .fullAccess: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .writeOnly: "Write only"
        case .notDetermined: "Not asked"
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

    private var googleLabel: String {
        if store.googleSyncErrorMessage != nil { return "Sync failed" }
        return store.googleCalendarService.isConnected ? "Connected" : "Not connected"
    }

    private var lastRescheduleLabel: String {
        guard let summary = store.lastRescheduleSummary else { return "—" }
        let time = summary.finishedAt.formatted(date: .omitted, time: .shortened)
        return "\(time) · \(summary.scheduledCount) ok"
    }

    /// Answers "why is the list empty" without a rebuild: which source produced events,
    /// and whether the per-calendar filter is narrowing things.
    private var eventSourceLabel: String {
        let eventKit = store.events.filter { $0.source == .eventKit }.count
        let google = store.events.filter { $0.source == .google }.count
        let all = store.calendarService.availableCalendars
        let off = all.filter { !$0.isEnabled }.count
        let filter = off == 0 ? "all \(all.count) cals" : "\(all.count - off)/\(all.count) cals"
        let googlePart = store.googleCalendarService.isConnected ? "google \(google)" : "google off"
        return "ek \(eventKit) · \(googlePart) · \(filter)"
    }
}
