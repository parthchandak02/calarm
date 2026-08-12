//
//  AlarmScheduler.swift
//  Calarm
//

import AlarmKit
import Foundation
import SwiftUI

@MainActor
final class AlarmScheduler {
    private typealias AlarmConfiguration = AlarmManager.AlarmConfiguration<AlarmAppMetadata>

    struct RescheduleResult {
        let scheduledCount: Int
        let failures: [ScheduleFailure]
        let skippedDuringAlerting: Bool
        let skippedTooSoon: [(occurrenceID: String, title: String, offset: AlarmOffsetOption)]
    }

    private struct DesiredInstance {
        let event: ScheduleEvent
        let alarm: ScheduledAlarm
        let fireDate: Date
        let withLiveActivity: Bool
        let alarmID: UUID

        var occurrenceID: String { event.id }
        var offset: AlarmOffsetOption { alarm.offset }
    }

    func reschedule(events: [ScheduleEvent], snoozeSeconds: TimeInterval, force: Bool = false) async -> RescheduleResult {
        if !force, hasAlertingAlarms() {
            SchedulerLog.warning("reschedule skipped — alarm alerting")
            return RescheduleResult(scheduledCount: 0, failures: [], skippedDuringAlerting: true, skippedTooSoon: [])
        }

        var failures: [ScheduleFailure] = []
        var skippedTooSoon: [(occurrenceID: String, title: String, offset: AlarmOffsetOption)] = []
        var scheduledCount = 0

        let cancelledStale = await reconcileStaleAlarms(events: events)

        let desired = buildDesiredInstances(from: events)
        let desiredIDs = Set(desired.map(\.alarmID))
        let managedIDs = managedAlarmIDs(for: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []

        for alarm in currentAlarms where managedIDs.contains(alarm.id) && !desiredIDs.contains(alarm.id) {
            if isAlerting(alarm) { continue }
            try? AlarmManager.shared.cancel(id: alarm.id)
            SchedulerLog.info("cancelled orphan alarm \(alarm.id)")
        }

        for instance in desired {
            let existing = currentAlarms.first { $0.id == instance.alarmID }
            if !force, let existing, !needsReschedule(existing: existing, instance: instance, snoozeSeconds: snoozeSeconds) {
                continue
            }
            if let existing, isAlerting(existing) { continue }

            await cancel(occurrenceID: instance.occurrenceID, offset: instance.offset)

            let outcome = await schedule(
                instance.event,
                offset: instance.offset,
                fireDate: instance.fireDate,
                withLiveActivity: instance.withLiveActivity,
                snoozeSeconds: snoozeSeconds
            )
            switch outcome {
            case .scheduled:
                scheduledCount += 1
            case .tooSoon:
                skippedTooSoon.append((instance.occurrenceID, instance.event.title, instance.offset))
            case .failed(let message):
                failures.append(ScheduleFailure(
                    occurrenceID: instance.occurrenceID,
                    eventTitle: instance.event.title,
                    offsetTitle: instance.offset.title,
                    message: message
                ))
            }
        }

        SchedulerLog.info("reschedule complete scheduled=\(scheduledCount) cancelledStale=\(cancelledStale) failures=\(failures.count)")
        return RescheduleResult(
            scheduledCount: scheduledCount,
            failures: failures,
            skippedDuringAlerting: false,
            skippedTooSoon: skippedTooSoon
        )
    }

    func cancelRemoved(eventIDs: Set<String>) async {
        for eventID in eventIDs {
            await cancelAll(for: eventID)
        }
    }

    func cancelAll(for occurrenceID: String) async {
        for offset in AlarmOffsetOption.schedulableOffsets {
            await cancel(occurrenceID: occurrenceID, offset: offset)
        }
    }

    func cancel(occurrenceID: String, offset: AlarmOffsetOption) async {
        try? AlarmManager.shared.cancel(id: stableAlarmID(for: occurrenceID, offset: offset))
    }

    func scheduleTestAlarm(snoozeSeconds: TimeInterval) async -> String? {
        let fireDate = Date().addingTimeInterval(8)
        let testID = "calarm.test.\(Int(fireDate.timeIntervalSince1970))"
        let alarmID = AlarmSchedulingHelpers.stableAlarmID(occurrenceID: testID, offsetRawValue: "test")
        let idString = alarmID.uuidString

        do {
            let stopButton = AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "stop.circle")
            let snoozeButton = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
            let alertPresentation = AlarmPresentation.Alert(
                title: "CALarm Test",
                stopButton: stopButton,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .countdown
            )
            let accent = resolvedAccentColor()
            let pauseButton = AlarmButton(text: "Pause", textColor: accent, systemImageName: "pause")
            let resumeButton = AlarmButton(text: "Resume", textColor: accent, systemImageName: "play")
            let presentation = AlarmPresentation(
                alert: alertPresentation,
                countdown: AlarmPresentation.Countdown(title: "CALarm Test", pauseButton: pauseButton),
                paused: AlarmPresentation.Paused(title: "Paused", resumeButton: resumeButton)
            )
            let attributes = AlarmAttributes<AlarmAppMetadata>(
                presentation: presentation,
                metadata: AlarmAppMetadata(title: "CALarm Test", offsetLabel: "Test", eventID: testID),
                tintColor: resolvedAccentColor()
            )
            let configuration = AlarmConfiguration(
                countdownDuration: Alarm.CountdownDuration(preAlert: 8, postAlert: snoozeSeconds),
                schedule: .fixed(fireDate),
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: idString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: idString)
            )
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func hasAlertingAlarms() -> Bool {
        guard let alarms = try? AlarmManager.shared.alarms else { return false }
        return alarms.contains { isAlerting($0) }
    }

    func hasActiveCountdown() -> Bool {
        hasActiveUpcomingCountdown()
    }

    /// Only defer reschedules while a future alarm is actively counting down.
    func hasActiveUpcomingCountdown() -> Bool {
        guard let alarms = try? AlarmManager.shared.alarms else { return false }
        return alarms.contains { alarm in
            guard case .countdown = alarm.state else { return false }
            guard let fireDate = fixedFireDate(for: alarm) else { return true }
            return AlarmSchedulingHelpers.hasUpcomingFireDate(fireDate)
        }
    }

    /// Cancel AlarmKit alarms whose fixed fire time has passed. Ends stale Live Activities.
    @discardableResult
    func reconcileStaleAlarms(events: [ScheduleEvent]) async -> Int {
        let managedIDs = managedAlarmIDs(for: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []
        var cancelled = 0

        for alarm in currentAlarms where managedIDs.contains(alarm.id) {
            guard let fireDate = fixedFireDate(for: alarm) else { continue }
            guard AlarmSchedulingHelpers.isStaleAlarm(fireDate: fireDate) else { continue }
            guard shouldAutoCancelStale(alarm) else { continue }

            try? AlarmManager.shared.cancel(id: alarm.id)
            cancelled += 1
            SchedulerLog.info("cancelled stale alarm \(alarm.id) fire=\(fireDate)")
        }

        return cancelled
    }

    func schedulingFingerprint(for events: [ScheduleEvent], snoozeSeconds: TimeInterval) -> String {
        let desired = buildDesiredInstances(from: events)
        let nextKey = desired.first(where: \.withLiveActivity).map {
            AlarmSchedulingHelpers.liveActivityKey(occurrenceID: $0.occurrenceID, offsetRawValue: $0.offset.rawValue)
        }
        let rows = desired.map {
            ($0.occurrenceID, $0.offset.rawValue, $0.fireDate)
        }
        let accentRaw = CalarmPersistence.string(forKey: CalarmPersistence.Key.themeAccent) ?? CalarmAccent.orange.rawValue
        return AlarmSchedulingHelpers.schedulingFingerprint(
            instances: rows,
            nextLiveActivityKey: nextKey,
            snoozeRawValue: String(Int(snoozeSeconds)),
            accentRawValue: accentRaw
        )
    }

    private enum ScheduleOutcome {
        case scheduled
        case tooSoon
        case failed(String)
    }

    private func buildDesiredInstances(from events: [ScheduleEvent]) -> [DesiredInstance] {
        let rawInstances = events.flatMap { event in
            event.scheduledAlarms.map { alarm in
                (
                    event: event,
                    alarm: alarm,
                    occurrenceID: event.id,
                    offsetRaw: alarm.offset.rawValue,
                    fireDate: alarm.fireDate
                )
            }
        }

        let staggered = AlarmSchedulingHelpers.collisionGroupsSortedByFireDate(
            instances: rawInstances.map { ($0.occurrenceID, $0.offsetRaw, $0.fireDate) }
        )

        let instanceByKey = Dictionary(
            uniqueKeysWithValues: rawInstances.map {
                (AlarmSchedulingHelpers.liveActivityKey(occurrenceID: $0.occurrenceID, offsetRawValue: $0.offsetRaw), $0)
            }
        )

        let orderedInstances: [(event: ScheduleEvent, alarm: ScheduledAlarm, fireDate: Date)] = staggered.compactMap { row in
            let key = AlarmSchedulingHelpers.liveActivityKey(occurrenceID: row.occurrenceID, offsetRawValue: row.offsetRawValue)
            guard let source = instanceByKey[key] else { return nil }
            return (source.event, source.alarm, row.fireDate)
        }

        let nextLiveActivityKey = orderedInstances.first.map {
            AlarmSchedulingHelpers.liveActivityKey(occurrenceID: $0.event.id, offsetRawValue: $0.alarm.offset.rawValue)
        }

        return orderedInstances.map { instance in
            let key = AlarmSchedulingHelpers.liveActivityKey(
                occurrenceID: instance.event.id,
                offsetRawValue: instance.alarm.offset.rawValue
            )
            return DesiredInstance(
                event: instance.event,
                alarm: instance.alarm,
                fireDate: instance.fireDate,
                withLiveActivity: key == nextLiveActivityKey,
                alarmID: stableAlarmID(for: instance.event.id, offset: instance.alarm.offset)
            )
        }
    }

    private func managedAlarmIDs(for events: [ScheduleEvent]) -> Set<UUID> {
        var ids = Set<UUID>()
        for event in events {
            for offset in AlarmOffsetOption.schedulableOffsets {
                ids.insert(stableAlarmID(for: event.id, offset: offset))
            }
        }
        return ids
    }

    private func needsReschedule(existing: Alarm, instance: DesiredInstance, snoozeSeconds: TimeInterval) -> Bool {
        if case .alerting = existing.state { return false }

        guard case .fixed(let scheduledDate) = existing.schedule else { return true }
        if abs(scheduledDate.timeIntervalSince(instance.fireDate)) > 0.5 { return true }

        let wantsPreAlert = instance.withLiveActivity
        let preAlert = existing.countdownDuration?.preAlert ?? 0
        let hasPreAlert = preAlert > 1
        if wantsPreAlert != hasPreAlert { return true }

        let postAlert = existing.countdownDuration?.postAlert ?? 0
        if abs(postAlert - snoozeSeconds) > 0.5 { return true }

        return false
    }

    private func isAlerting(_ alarm: Alarm) -> Bool {
        if case .alerting = alarm.state { return true }
        return false
    }

    private func shouldAutoCancelStale(_ alarm: Alarm) -> Bool {
        switch alarm.state {
        case .countdown, .paused:
            return true
        case .alerting:
            return false
        default:
            return true
        }
    }

    private func fixedFireDate(for alarm: Alarm) -> Date? {
        guard case .fixed(let date) = alarm.schedule else { return nil }
        return date
    }

    private func schedule(
        _ event: ScheduleEvent,
        offset: AlarmOffsetOption,
        fireDate: Date,
        withLiveActivity: Bool,
        snoozeSeconds: TimeInterval
    ) async -> ScheduleOutcome {
        guard offset.isSchedulable else { return .failed("Offset not schedulable") }
        let alarmID = stableAlarmID(for: event.id, offset: offset)
        let idString = alarmID.uuidString
        let secondsUntilAlarm = fireDate.timeIntervalSinceNow
        guard secondsUntilAlarm > 1 else { return .tooSoon }

        do {
            let stopButton = AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "stop.circle")
            let snoozeButton = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
            let alertPresentation = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: event.title),
                stopButton: stopButton,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .countdown
            )

            let presentation: AlarmPresentation
            let accent = resolvedAccentColor()
            if withLiveActivity {
                let pauseButton = AlarmButton(text: "Pause", textColor: accent, systemImageName: "pause")
                let resumeButton = AlarmButton(text: "Resume", textColor: accent, systemImageName: "play")
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

            let accentRaw = CalarmPersistence.string(forKey: CalarmPersistence.Key.themeAccent)
            let attributes = AlarmAttributes<AlarmAppMetadata>(
                presentation: presentation,
                metadata: AlarmAppMetadata(
                    title: event.title,
                    offsetLabel: offset.title,
                    eventID: event.id,
                    accentRawValue: accentRaw
                ),
                tintColor: resolvedAccentColor()
            )

            let countdownDuration: Alarm.CountdownDuration?
            if withLiveActivity {
                countdownDuration = Alarm.CountdownDuration(
                    preAlert: secondsUntilAlarm,
                    postAlert: snoozeSeconds
                )
            } else {
                countdownDuration = Alarm.CountdownDuration(
                    preAlert: nil,
                    postAlert: snoozeSeconds
                )
            }

            let configuration = AlarmConfiguration(
                countdownDuration: countdownDuration,
                schedule: .fixed(fireDate),
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: idString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: idString)
            )

            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            SchedulerLog.info("scheduled \(event.id) \(offset.rawValue) fire=\(fireDate) liveActivity=\(withLiveActivity)")
            return .scheduled
        } catch {
            let message = error.localizedDescription
            SchedulerLog.error("schedule failed \(event.id) \(offset.rawValue): \(message)")
            return .failed(message)
        }
    }

    private func resolvedAccentColor() -> Color {
        CalarmAccent.resolved(from: CalarmPersistence.string(forKey: CalarmPersistence.Key.themeAccent)).color
    }

    private func stableAlarmID(for occurrenceID: String, offset: AlarmOffsetOption) -> UUID {
        AlarmSchedulingHelpers.stableAlarmID(occurrenceID: occurrenceID, offsetRawValue: offset.rawValue)
    }
}
