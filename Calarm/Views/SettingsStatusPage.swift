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
            }()
        ))
    }
}

/// Verdict first: one line says whether alarms will ring, problems follow with their fix,
/// and the passing checks fold into one line.
struct SettingsStatusPage: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.calarmTheme) private var theme

    @State private var showsChecks = false

    var body: some View {
        let problems = store.statusProblems
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                verdict(problems)

                if !problems.isEmpty {
                    BoardSectionLabel(title: "Fix")
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                        BoardLine(title: problem.title, detail: problem.detail, titleColor: theme.destructive) {
                            fixButton(problem.fix)
                        }
                    }
                }

                BoardSectionLabel(title: "Checks")
                Button {
                    withAnimation(.snappy) { showsChecks.toggle() }
                } label: {
                    BoardLine(
                        title: showsChecks ? "Hide details" : "\(checks.count) checks",
                        value: showsChecks ? "" : checks.map(\.value).prefix(2).joined(separator: " · "),
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                if showsChecks {
                    ForEach(checks, id: \.title) { check in
                        BoardLine(title: check.title) {
                            HStack(spacing: 8) {
                                StatusLight(isProblem: check.isProblem)
                                BoardValue(text: check.value, color: check.isProblem ? theme.destructive : nil)
                            }
                        }
                    }
                }

                NextRingBlock()
                TestAlarmButton(isProminent: true)
                    .padding(.top, 16)

                #if targetEnvironment(simulator)
                Text("Alarm sound and AlarmKit behavior require a physical device.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 10)
                #endif
            }
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .padding(.bottom, 24)
        }
        .boardNavigationTitle("Status")
    }

    private func verdict(_ problems: [StatusVerdict.Problem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                StatusLight(isProblem: !problems.isEmpty)
                Text(StatusVerdict.headline(for: problems))
                    .font(CalarmFont.title2)
                    .foregroundStyle(theme.textPrimary)
            }
            Text(StatusVerdict.subline(for: problems, hasUpcomingAlarm: store.nextUpcomingAlarm != nil))
                .font(CalarmFont.boardDetail)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
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
        case .countdownStartsAtFireDate, .other: true
        default: false
        }
    }

    private var alarmTimingLabel: String {
        switch AlarmJournalStore.testProbeVerdict() {
        case nil: "Not measured"
        case .pending: "Waiting for ring"
        case .onTime(let seconds): "On time · \(seconds)s"
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
