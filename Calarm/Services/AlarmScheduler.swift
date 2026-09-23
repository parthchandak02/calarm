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
        let cleaned = await reconcileAlarmLifecycle(events: events)

        if !force, hasAlertingAlarms() {
            SchedulerLog.warning("reschedule skipped - alarm alerting (cleaned=\(cleaned))")
            return RescheduleResult(scheduledCount: 0, failures: [], skippedDuringAlerting: true, skippedTooSoon: [])
        }

        var failures: [ScheduleFailure] = []
        var skippedTooSoon: [(occurrenceID: String, title: String, offset: AlarmOffsetOption)] = []
        var scheduledCount = 0

        let desired = buildDesiredInstances(from: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []
        // AlarmKit deletes spent alarms silently, so their stored targets go with them here.
        Self.pruneCountdownTargets(keeping: Set(currentAlarms.map(\.id)))

        for instance in desired {
            guard !Task.isCancelled else { break }
            let existing = currentAlarms.first { $0.id == instance.alarmID }
            if !force, let existing, !needsReschedule(existing: existing, instance: instance, snoozeSeconds: snoozeSeconds) {
                continue
            }
            if let existing, isAlerting(existing) { continue }

            let cancelled = await cancel(occurrenceID: instance.occurrenceID, offset: instance.offset)
            if !cancelled, existing != nil {
                failures.append(ScheduleFailure(
                    occurrenceID: instance.occurrenceID,
                    eventTitle: instance.event.title,
                    offsetTitle: instance.offset.title,
                    message: "Cancel failed before reschedule"
                ))
                continue
            }

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

        SchedulerLog.info("reschedule complete scheduled=\(scheduledCount) cleaned=\(cleaned) failures=\(failures.count)")
        return RescheduleResult(
            scheduledCount: scheduledCount,
            failures: failures,
            skippedDuringAlerting: false,
            skippedTooSoon: skippedTooSoon
        )
    }

    func cancelRemoved(eventIDs: Set<String>) async {
        for eventID in eventIDs {
            guard !Task.isCancelled else { break }
            await cancelAll(for: eventID)
        }
    }

    func cancelAll(for occurrenceID: String) async {
        for offset in AlarmOffsetOption.schedulableOffsets {
            await cancel(occurrenceID: occurrenceID, offset: offset)
        }
    }

    @discardableResult
    func cancel(occurrenceID: String, offset: AlarmOffsetOption) async -> Bool {
        let id = stableAlarmID(for: occurrenceID, offset: offset)
        do {
            try AlarmManager.shared.cancel(id: id)
            Self.setCountdownTarget(nil, for: id)
            AlarmJournalStore.record(.cancelled, alarmID: id.uuidString, occurrenceID: occurrenceID)
            return true
        } catch {
            SchedulerLog.warning("cancel failed \(occurrenceID) \(offset.rawValue): \(error.localizedDescription)")
            return false
        }
    }

    func scheduleTestAlarm(snoozeSeconds: TimeInterval) async -> String? {
        let testPreAlert: TimeInterval = 8
        let scheduledAt = Date()
        let fireDate = scheduledAt.addingTimeInterval(testPreAlert)
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
                // Deliberately `.fixed` plus an equal pre-alert, unlike real alarms: it is the
                // probe for how AlarmKit times that combination. See AlarmTimingProbe.
                countdownDuration: Alarm.CountdownDuration(preAlert: testPreAlert, postAlert: snoozeSeconds),
                schedule: .fixed(fireDate),
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: idString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: idString)
            )
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            AlarmJournalStore.record(.scheduled, alarmID: idString, occurrenceID: testID, intendedFire: fireDate)
            AlarmJournalStore.recordTestProbe(alarmID: idString, scheduledAt: scheduledAt, preAlert: testPreAlert)
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
            guard let fireDate = intendedFireDate(for: alarm) else { return true }
            return AlarmSchedulingHelpers.hasUpcomingFireDate(fireDate)
        }
    }

    /// Always-safe cleanup: stale countdowns, expired events, orphans, and undesired alarms.
    @discardableResult
    func reconcileAlarmLifecycle(events: [ScheduleEvent]) async -> Int {
        let orphans = await reconcileOrphanAlarms(events: events)
        let stale = await reconcileStaleAlarms(events: events)
        let undesired = await cancelUndesiredAlarms(events: events)
        return orphans + stale + undesired
    }

    /// Cancel AlarmKit alarms that no longer map to the current schedule (dropped events, ID migrations).
    @discardableResult
    func reconcileOrphanAlarms(events: [ScheduleEvent]) async -> Int {
        let lookup = alarmEventLookup(for: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []
        var terminated = 0

        for alarm in currentAlarms {
            guard !Task.isCancelled else { break }
            guard lookup[alarm.id] == nil else { continue }

            if let fireDate = intendedFireDate(for: alarm) {
                guard shouldTerminateOrphan(alarm: alarm, fireDate: fireDate) else { continue }
            } else if !isAlerting(alarm), case .scheduled = alarm.state {
                continue
            }

            if terminate(alarm) {
                terminated += 1
                SchedulerLog.info("terminated orphan alarm \(alarm.id)")
            }
        }

        return terminated
    }

    /// Cancel AlarmKit alarms whose fixed fire time has passed. Ends stale Live Activities.
    @discardableResult
    func reconcileStaleAlarms(events: [ScheduleEvent]) async -> Int {
        let lookup = alarmEventLookup(for: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []
        var terminated = 0

        for alarm in currentAlarms where lookup[alarm.id] != nil {
            guard !Task.isCancelled else { break }
            guard let fireDate = intendedFireDate(for: alarm) else { continue }
            let event = lookup[alarm.id]
            guard shouldTerminateStale(alarm: alarm, event: event, fireDate: fireDate) else { continue }

            if terminate(alarm) {
                terminated += 1
                SchedulerLog.info("terminated stale alarm \(alarm.id) fire=\(fireDate)")
            }
        }

        return terminated
    }

    /// Cancel alarms no longer in the desired schedule (including ended events).
    @discardableResult
    func cancelUndesiredAlarms(events: [ScheduleEvent]) async -> Int {
        let desiredIDs = Set(buildDesiredInstances(from: events).map(\.alarmID))
        let lookup = alarmEventLookup(for: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []
        var terminated = 0

        for alarm in currentAlarms {
            guard !Task.isCancelled else { break }
            guard lookup[alarm.id] != nil else { continue }
            guard !desiredIDs.contains(alarm.id) else { continue }

            if isAlerting(alarm), let event = lookup[alarm.id], !AlarmSchedulingHelpers.isEventEnded(endDate: event.endDate) {
                if let fireDate = intendedFireDate(for: alarm),
                   !AlarmSchedulingHelpers.isStaleAlarm(
                       fireDate: fireDate,
                       graceAfterFire: AlarmSchedulingHelpers.alertingCleanupGrace
                   ) {
                    continue
                }
            }

            if terminate(alarm) {
                terminated += 1
                SchedulerLog.info("terminated undesired alarm \(alarm.id)")
            }
        }

        return terminated
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
        let liveActivityEvent = desired.first(where: \.withLiveActivity)?.event
        return AlarmSchedulingHelpers.schedulingFingerprint(
            instances: rows,
            nextLiveActivityKey: nextKey,
            snoozeRawValue: String(Int(snoozeSeconds)),
            accentRawValue: accentRaw,
            liveActivityTintKey: liveActivityTintKey(for: liveActivityEvent, accentRaw: accentRaw)
        )
    }

    private func liveActivityTintKey(for event: ScheduleEvent?, accentRaw: String) -> String {
        guard CalarmPersistence.bool(forKey: CalarmPersistence.Key.useCalendarColorInLiveActivity),
              let hex = event?.calendarColorHex else {
            return "accent:\(accentRaw)"
        }
        return "cal:\(hex)"
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

        guard let scheduledDate = intendedFireDate(for: existing) else { return true }
        if abs(scheduledDate.timeIntervalSince(instance.fireDate)) > 0.5 { return true }

        let isCountdownMode = existing.schedule == nil
        if instance.withLiveActivity != isCountdownMode { return true }

        let postAlert = existing.countdownDuration?.postAlert ?? 0
        if abs(postAlert - snoozeSeconds) > 0.5 { return true }

        return false
    }

    private func isAlerting(_ alarm: Alarm) -> Bool {
        if case .alerting = alarm.state { return true }
        return false
    }

    private func shouldTerminateStale(alarm: Alarm, event: ScheduleEvent?, fireDate: Date) -> Bool {
        if let event, AlarmSchedulingHelpers.isEventEnded(endDate: event.endDate) {
            return true
        }

        switch alarm.state {
        case .countdown, .paused:
            // Cancel stuck countdowns once fire time passes — do not wait for event.endDate.
            // A long meeting block otherwise keeps a missed alarm alive for hours (PR #10
            // regression). The grace outlasts one snooze, since that is what a countdown past
            // its fire time normally is.
            return AlarmSchedulingHelpers.isStaleAlarm(
                fireDate: fireDate,
                graceAfterFire: snoozeAwareCountdownGrace
            )
        case .alerting:
            return AlarmSchedulingHelpers.isStaleAlarm(
                fireDate: fireDate,
                graceAfterFire: AlarmSchedulingHelpers.alertingCleanupGrace
            )
        default:
            return AlarmSchedulingHelpers.isStaleAlarm(fireDate: fireDate)
        }
    }

    private func shouldTerminateOrphan(alarm: Alarm, fireDate: Date) -> Bool {
        switch alarm.state {
        case .alerting:
            return AlarmSchedulingHelpers.isStaleAlarm(
                fireDate: fireDate,
                graceAfterFire: AlarmSchedulingHelpers.alertingCleanupGrace
            )
        case .countdown, .paused:
            return AlarmSchedulingHelpers.isStaleAlarm(
                fireDate: fireDate,
                graceAfterFire: snoozeAwareCountdownGrace
            )
        default:
            return AlarmSchedulingHelpers.isStaleAlarm(fireDate: fireDate)
        }
    }

    @discardableResult
    private func terminate(_ alarm: Alarm) -> Bool {
        if isAlerting(alarm) {
            do {
                try AlarmManager.shared.stop(id: alarm.id)
            } catch {
                SchedulerLog.warning("stop failed \(alarm.id): \(error.localizedDescription)")
            }
        }
        do {
            try AlarmManager.shared.cancel(id: alarm.id)
            Self.setCountdownTarget(nil, for: alarm.id)
            return true
        } catch {
            SchedulerLog.warning("cancel failed \(alarm.id): \(error.localizedDescription)")
            return false
        }
    }

    private func alarmEventLookup(for events: [ScheduleEvent]) -> [UUID: ScheduleEvent] {
        var lookup: [UUID: ScheduleEvent] = [:]
        for event in events {
            for offset in AlarmOffsetOption.schedulableOffsets {
                lookup[stableAlarmID(for: event.id, offset: offset)] = event
            }
        }
        return lookup
    }

    /// The fixed date for a scheduled alarm, or the stored target for a countdown-mode alarm,
    /// which AlarmKit keeps no date for.
    private func intendedFireDate(for alarm: Alarm) -> Date? {
        if case .fixed(let date) = alarm.schedule { return date }
        return Self.countdownTarget(for: alarm.id)
    }

    private static func countdownTargets() -> [String: TimeInterval] {
        CalarmPersistence.decode([String: TimeInterval].self, forKey: CalarmPersistence.Key.countdownTargets) ?? [:]
    }

    private static func countdownTarget(for id: UUID) -> Date? {
        countdownTargets()[id.uuidString].map(Date.init(timeIntervalSince1970:))
    }

    private static func setCountdownTarget(_ date: Date?, for id: UUID) {
        var targets = countdownTargets()
        guard targets[id.uuidString] != date?.timeIntervalSince1970 else { return }
        targets[id.uuidString] = date?.timeIntervalSince1970
        if targets.isEmpty {
            CalarmPersistence.remove(forKey: CalarmPersistence.Key.countdownTargets)
        } else {
            CalarmPersistence.encode(targets, forKey: CalarmPersistence.Key.countdownTargets)
        }
    }

    private static func pruneCountdownTargets(keeping ids: Set<UUID>) {
        let targets = countdownTargets()
        let kept = targets.filter { key, _ in UUID(uuidString: key).map(ids.contains) ?? false }
        guard kept.count != targets.count else { return }
        if kept.isEmpty {
            CalarmPersistence.remove(forKey: CalarmPersistence.Key.countdownTargets)
        } else {
            CalarmPersistence.encode(kept, forKey: CalarmPersistence.Key.countdownTargets)
        }
    }

    private var snoozeAwareCountdownGrace: TimeInterval {
        let minutes = CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
            ? CalarmPersistence.integer(forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
            : SnoozeDurationOption.fiveMinutes.rawValue
        return AlarmSchedulingHelpers.snoozeAwareCountdownGrace(snoozeSeconds: TimeInterval(minutes * 60))
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
            let tint = resolvedLiveActivityTint(for: event)
            if withLiveActivity {
                let pauseButton = AlarmButton(text: "Pause", textColor: tint, systemImageName: "pause")
                let resumeButton = AlarmButton(text: "Resume", textColor: tint, systemImageName: "play")
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
                    accentRawValue: accentRaw,
                    eventEndTimestamp: event.endDate.timeIntervalSince1970,
                    eventStartTimestamp: event.startDate.timeIntervalSince1970
                ),
                tintColor: resolvedLiveActivityTint(for: event)
            )

            let countdownDuration: Alarm.CountdownDuration?
            let alarmSchedule: Alarm.Schedule?
            if withLiveActivity {
                // No schedule: a countdown that starts now and rings after `preAlert`, the
                // one combination Apple documents unambiguously. `.fixed` plus a pre-alert is
                // documented to count down *to* the fixed date, but on device a 9:00 event's
                // countdown was still running at 9:50 toward 10:14:54 — exactly the fixed
                // date plus the pre-alert, as if the countdown started *at* the fixed date.
                // That also explains the "stuck countdown" hours-late fires fixed in ea79c68.
                // The 8-second test alarm probes which behaviour the device has.
                countdownDuration = Alarm.CountdownDuration(
                    preAlert: secondsUntilAlarm,
                    postAlert: snoozeSeconds
                )
                alarmSchedule = nil
            } else {
                // A one second pre-alert, and it is not cosmetic. AlarmKit alarms fail to
                // present when the foregrounded app is in landscape; Apple's own Reminders
                // works around it with exactly this, and the WWDC demo had the bug.
                // `needsReschedule` keys Live Activity on schedule type, not pre-alert, so
                // this does not cause reschedule churn. Under the start-at-fixed-date
                // behaviour this rings one second late, which is harmless.
                countdownDuration = Alarm.CountdownDuration(
                    preAlert: 1,
                    postAlert: snoozeSeconds
                )
                alarmSchedule = .fixed(fireDate)
            }

            let configuration = AlarmConfiguration(
                countdownDuration: countdownDuration,
                schedule: alarmSchedule,
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: idString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: idString)
            )

            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            Self.setCountdownTarget(withLiveActivity ? fireDate : nil, for: alarmID)
            AlarmJournalStore.record(
                .scheduled,
                alarmID: idString,
                occurrenceID: event.id,
                intendedFire: fireDate
            )
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

    private func resolvedLiveActivityTint(for event: ScheduleEvent) -> Color {
        if CalarmPersistence.bool(forKey: CalarmPersistence.Key.useCalendarColorInLiveActivity),
           let hex = event.calendarColorHex,
           let calendarColor = CalendarColor.color(fromHex: hex) {
            return calendarColor
        }
        return resolvedAccentColor()
    }

    private func stableAlarmID(for occurrenceID: String, offset: AlarmOffsetOption) -> UUID {
        AlarmSchedulingHelpers.stableAlarmID(occurrenceID: occurrenceID, offsetRawValue: offset.rawValue)
    }
}
