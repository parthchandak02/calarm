//
//  ScreenshotDemoData.swift
//  Calarm
//

import Foundation

/// Fictional calendar events for App Store screenshots — no real user data.
enum ScreenshotDemoData {
    static let featuredEventID = "screenshot-event-design-review"

    static func events(referenceDate: Date = Date()) -> [ScheduleEvent] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)

        func event(
            id: String,
            title: String,
            dayOffset: Int,
            hour: Int,
            minute: Int,
            durationMinutes: Int,
            location: String?,
            calendarTitle: String,
            alarmOffsets: [AlarmOffsetOption]
        ) -> ScheduleEvent {
            let start = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: calendar.date(byAdding: .day, value: dayOffset, to: todayStart) ?? todayStart
            ) ?? todayStart
            let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start

            return ScheduleEvent(
                id: id,
                title: title,
                startDate: start,
                endDate: end,
                location: location,
                calendarTitle: calendarTitle,
                alarmOffsets: alarmOffsets
            )
        }

        return [
            event(
                id: "screenshot-event-standup",
                title: "Team standup",
                dayOffset: 0,
                hour: 9,
                minute: 30,
                durationMinutes: 30,
                location: nil,
                calendarTitle: "Work",
                alarmOffsets: [.fiveMinutes]
            ),
            event(
                id: featuredEventID,
                title: "Design review",
                dayOffset: 0,
                hour: 14,
                minute: 0,
                durationMinutes: 60,
                location: "Studio B",
                calendarTitle: "Work",
                alarmOffsets: [.tenMinutes, .thirtyMinutes]
            ),
            event(
                id: "screenshot-event-sync",
                title: "Product sync",
                dayOffset: 1,
                hour: 11,
                minute: 0,
                durationMinutes: 45,
                location: "Video call",
                calendarTitle: "Work",
                alarmOffsets: [.oneMinute]
            ),
            event(
                id: "screenshot-event-demo",
                title: "Client demo",
                dayOffset: 2,
                hour: 15,
                minute: 30,
                durationMinutes: 90,
                location: "Conference room",
                calendarTitle: "Work",
                alarmOffsets: []
            ),
            event(
                id: "screenshot-event-planning",
                title: "Sprint planning",
                dayOffset: 3,
                hour: 10,
                minute: 0,
                durationMinutes: 120,
                location: nil,
                calendarTitle: "Work",
                alarmOffsets: [.sixtyMinutes]
            ),
            event(
                id: "screenshot-event-workshop",
                title: "Workshop",
                dayOffset: 5,
                hour: 13,
                minute: 0,
                durationMinutes: 180,
                location: "Main campus",
                calendarTitle: "Personal",
                alarmOffsets: [.oneDayBefore]
            )
        ]
    }

    /// Preferences applied when screenshot mode boots (deterministic theme).
    static func applyDemoPreferencesSync() {
        CalarmPersistence.setString(CalarmAppearance.dark.rawValue, forKey: CalarmPersistence.Key.themeAppearance)
        CalarmPersistence.setString(CalarmAccent.coral.rawValue, forKey: CalarmPersistence.Key.themeAccent)
        CalarmPersistence.setString(AlarmOffsetOption.tenMinutes.rawValue, forKey: CalarmPersistence.Key.defaultAlarmOffset)
        CalarmPersistence.setInteger(SnoozeDurationOption.fiveMinutes.rawValue, forKey: CalarmPersistence.Key.defaultSnoozeMinutes)

        var overrides: [String: EventOverride] = [:]
        for event in events() where !event.alarmOffsets.isEmpty {
            overrides[event.id] = EventOverride(
                alarmOffsets: event.alarmOffsets.map(\.rawValue),
                legacyOffsetMinutes: nil,
                legacyEnabled: nil
            )
        }
        CalarmPersistence.encode(overrides, forKey: CalarmPersistence.Key.eventOverrides)
    }
}
