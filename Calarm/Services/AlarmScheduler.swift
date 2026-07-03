//
//  AlarmScheduler.swift
//  Calarm
//

import AlarmKit
import CryptoKit
import Foundation
import SwiftUI

@MainActor
final class AlarmScheduler {
    private typealias AlarmConfiguration = AlarmManager.AlarmConfiguration<AlarmAppMetadata>

    func reschedule(events: [ScheduleEvent], snoozeSeconds: TimeInterval, force: Bool = false) async {
        if !force, hasActiveAlarms() {
            return
        }

        let allInstances = events.flatMap { event in
            event.scheduledAlarms.map { alarm in
                (event: event, alarm: alarm)
            }
        }.sorted { $0.alarm.fireDate < $1.alarm.fireDate }

        let nextLiveActivityKey = allInstances.first.map { liveActivityKey(eventID: $0.event.id, offset: $0.alarm.offset) }

        for event in events {
            await cancelAll(for: event.id)
        }

        for instance in allInstances {
            let key = liveActivityKey(eventID: instance.event.id, offset: instance.alarm.offset)
            await schedule(
                instance.event,
                offset: instance.alarm.offset,
                withLiveActivity: key == nextLiveActivityKey,
                snoozeSeconds: snoozeSeconds
            )
        }
    }

    func reschedule(event: ScheduleEvent, among events: [ScheduleEvent], snoozeSeconds: TimeInterval) async {
        await cancelAll(for: event.id)

        let allInstances = events.flatMap { ev in
            ev.scheduledAlarms.map { (event: ev, alarm: $0) }
        }.sorted { $0.alarm.fireDate < $1.alarm.fireDate }

        let nextLiveActivityKey = allInstances.first.map { liveActivityKey(eventID: $0.event.id, offset: $0.alarm.offset) }

        for alarm in event.scheduledAlarms {
            let key = liveActivityKey(eventID: event.id, offset: alarm.offset)
            await schedule(
                event,
                offset: alarm.offset,
                withLiveActivity: key == nextLiveActivityKey,
                snoozeSeconds: snoozeSeconds
            )
        }
    }

    func cancelAll(for eventID: String) async {
        for offset in AlarmOffsetOption.allCases {
            await cancel(eventID: eventID, offset: offset)
        }
    }

    func cancel(eventID: String, offset: AlarmOffsetOption) async {
        try? AlarmManager.shared.cancel(id: stableAlarmID(for: eventID, offset: offset))
    }

    private func hasActiveAlarms() -> Bool {
        guard let alarms = try? AlarmManager.shared.alarms else { return false }
        return alarms.contains { alarm in
            switch alarm.state {
            case .countdown, .alerting:
                return true
            default:
                return false
            }
        }
    }

    private func schedule(
        _ event: ScheduleEvent,
        offset: AlarmOffsetOption,
        withLiveActivity: Bool,
        snoozeSeconds: TimeInterval
    ) async {
        let alarmID = stableAlarmID(for: event.id, offset: offset)
        let idString = alarmID.uuidString
        let fireDate = offset.fireDate(for: event.startDate)

        do {
            let stopButton = AlarmButton(
                text: "Dismiss",
                textColor: .white,
                systemImageName: "stop.circle"
            )

            let snoozeButton = AlarmButton(
                text: "Snooze",
                textColor: .white,
                systemImageName: "zzz"
            )

            let alertPresentation = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: event.title),
                stopButton: stopButton,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .countdown
            )

            let presentation: AlarmPresentation
            if withLiveActivity {
                let pauseButton = AlarmButton(
                    text: "Pause",
                    textColor: .red,
                    systemImageName: "pause"
                )
                let resumeButton = AlarmButton(
                    text: "Resume",
                    textColor: .red,
                    systemImageName: "play"
                )

                presentation = AlarmPresentation(
                    alert: alertPresentation,
                    countdown: AlarmPresentation.Countdown(
                        title: LocalizedStringResource(stringLiteral: event.title),
                        pauseButton: pauseButton
                    ),
                    paused: AlarmPresentation.Paused(
                        title: LocalizedStringResource(stringLiteral: "Paused"),
                        resumeButton: resumeButton
                    )
                )
            } else {
                presentation = AlarmPresentation(alert: alertPresentation)
            }

            let attributes = AlarmAttributes<AlarmAppMetadata>(
                presentation: presentation,
                metadata: AlarmAppMetadata(
                    title: event.title,
                    offsetLabel: offset.title
                ),
                tintColor: resolvedAccentColor()
            )

            let secondsUntilAlarm = fireDate.timeIntervalSinceNow
            guard secondsUntilAlarm > 1 else { return }

            let countdownDuration = Alarm.CountdownDuration(
                preAlert: secondsUntilAlarm,
                postAlert: snoozeSeconds
            )

            let configuration = AlarmConfiguration(
                countdownDuration: countdownDuration,
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: idString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: idString)
            )

            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
        } catch {
            print("Failed to schedule alarm for \(event.title) (\(offset.title)): \(error)")
        }
    }

    private func liveActivityKey(eventID: String, offset: AlarmOffsetOption) -> String {
        "\(eventID).\(offset.rawValue)"
    }

    private func resolvedAccentColor() -> Color {
        if let raw = CalarmPersistence.string(forKey: CalarmPersistence.Key.themeAccent),
           let accent = CalarmAccent(rawValue: raw) {
            return accent.color
        }
        return CalarmAccent.orange.color
    }

    private func stableAlarmID(for eventID: String, offset: AlarmOffsetOption) -> UUID {
        let digest = SHA256.hash(data: Data("calarm.\(eventID).\(offset.rawValue)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

nonisolated struct AlarmAppMetadata: AlarmMetadata, Sendable, Codable {
    let title: String
    let offsetLabel: String?

    nonisolated init(title: String = "Alarm", offsetLabel: String? = nil) {
        self.title = title
        self.offsetLabel = offsetLabel
    }
}
