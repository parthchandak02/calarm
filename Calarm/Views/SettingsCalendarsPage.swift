//
//  SettingsCalendarsPage.swift
//  Calarm
//

import EventKit
import SwiftUI
import UIKit

struct SettingsCalendarsPage: View {
    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.calarmTheme) private var theme

    @State private var isConnectingGoogle = false
    @State private var googleConnectError: String?

    private var google: GoogleCalendarService { store.googleCalendarService }
    private var eventKitCalendars: [CalendarSummary] { store.calendarService.availableCalendars }
    private var hiddenEventKitCount: Int { eventKitCalendars.filter { !$0.isEnabled }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                googleSection
                eventKitSection

                Text("All-day events are always skipped. Numbers are events in the next few days.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, CalarmTheme.rowPaddingH)
            .padding(.bottom, 24)
        }
        .boardNavigationTitle("Calendars")
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
    private var googleSection: some View {
        if google.isConnected {
            BoardSectionLabel(title: "Google · \(google.connectedEmail ?? "connected")")
            if google.availableCalendars.isEmpty {
                BoardLine(title: "Loading Google calendars…", value: "")
            } else {
                ForEach(google.availableCalendars) { calendar in
                    let isOn = google.isCalendarEnabled(calendar.id)
                    calendarLine(
                        title: calendar.title,
                        color: nil,
                        isBusyOnly: calendar.isBusyOnly,
                        count: eventCount(source: .google, calendarTitle: calendar.title),
                        isOn: isOn
                    ) {
                        google.setCalendarEnabled(calendar.id, enabled: !isOn)
                        Task { await store.reload() }
                    }
                }
            }
            HStack(spacing: 16) {
                Button("Sync now") { Task { await store.reload() } }
                    .foregroundStyle(theme.accent)
                Button("Disconnect", role: .destructive) { store.disconnectGoogleCalendar() }
                    .foregroundStyle(theme.destructive)
                Spacer()
            }
            .font(CalarmFont.boardDetail)
            .frame(minHeight: CalarmTheme.minimumTouchTarget)
        } else {
            BoardSectionLabel(title: "Google")
            if GoogleOAuthConfig.isConfigured {
                Button(action: connectGoogle) {
                    BoardLine(
                        title: isConnectingGoogle ? "Connecting…" : "Connect Google Calendar",
                        detail: "Faster updates than iOS Calendar sync",
                        value: "",
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isConnectingGoogle)
            } else {
                Text("Add GoogleService-Info.plist to enable Google Calendar. See scripts/setup-google-oauth.sh.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var eventKitSection: some View {
        BoardSectionLabel(title: "iOS calendars")
        if eventKitCalendars.isEmpty {
            Text(store.authorizationStatus == .fullAccess ? "No calendars found." : "Grant calendar access to choose calendars.")
                .font(CalarmFont.boardDetail)
                .foregroundStyle(theme.textSecondary)
        } else {
            ForEach(eventKitCalendars) { calendar in
                calendarLine(
                    title: calendar.title,
                    color: CalendarColor.color(fromHex: calendar.colorHex),
                    isBusyOnly: false,
                    count: eventCount(source: .eventKit, calendarTitle: calendar.title),
                    isOn: calendar.isEnabled
                ) {
                    store.calendarService.setCalendarEnabled(calendar.id, enabled: !calendar.isEnabled)
                    Task { await store.reload() }
                }
            }
            if hiddenEventKitCount > 0 {
                BoardButton(title: "\(hiddenEventKitCount) off · turn all on") {
                    store.calendarService.enableAllCalendars()
                    Task { await store.reload() }
                }
                .padding(.top, 14)
            }
            if !google.isConnected {
                Text("Without Google, iOS syncs these on its own schedule, often minutes behind.")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 10)
            }
        }
    }

    private func calendarLine(
        title: String,
        color: Color?,
        isBusyOnly: Bool,
        count: Int,
        isOn: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        BoardLine(title: title, dotColor: color) {
            HStack(spacing: 8) {
                if isBusyOnly {
                    Text("BUSY")
                        .font(CalarmFont.boardLabel)
                        .tracking(1.5)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(theme.surfaceStroke, lineWidth: 1)
                        }
                }
                Text(isOn ? "\(count)" : "—")
                    .font(CalarmFont.boardDetail)
                    .foregroundStyle(isOn ? theme.accent : theme.textSecondary)
                    .monospacedDigit()
                    .accessibilityLabel(isOn ? "\(count) upcoming events" : "Off")
                ArmSquareToggle(isOn: isOn, label: title, onToggle: onToggle)
            }
        }
    }

    private func eventCount(source: CalendarSource, calendarTitle: String) -> Int {
        store.events.filter { $0.source == source && $0.calendarTitle == calendarTitle }.count
    }

    private func connectGoogle() {
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
}
