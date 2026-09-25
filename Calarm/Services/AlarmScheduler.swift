//
//  AlarmScheduler.swift
//  Calarm
//

import ActivityKit
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
        let title: String
        let withLiveActivity: Bool
        let alarmID: UUID
        let vibrates: Bool
        let isFallback: Bool

        /// Title plus sound: what AlarmKit will not report back, so `needsReschedule` compares
        /// the stored copy.
        var signature: String { "\(title)|\(vibrates ? "vibrate" : "ring")" }

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
        Self.pruneTitles(keeping: Set(currentAlarms.map(\.id)))

        let fallbackPrimaries = fallbackPrimaries(for: events)
        for instance in desired {
            guard !Task.isCancelled else { break }
            let existing = currentAlarms.first { $0.id == instance.alarmID }
            if instance.isFallback,
               isHeldBySnoozeOrAlert(fallbackID: instance.alarmID, primaries: fallbackPrimaries, alarms: currentAlarms) {
                continue
            }
            if !force, let existing, !needsReschedule(existing: existing, instance: instance, snoozeSeconds: snoozeSeconds) {
                continue
            }
            if let existing, isAlerting(existing) { continue }

            let cancelled = cancel(alarmID: instance.alarmID, occurrenceID: instance.occurrenceID)
            if !cancelled, existing != nil {
                failures.append(ScheduleFailure(
                    occurrenceID: instance.occurrenceID,
                    eventTitle: instance.event.title,
                    offsetTitle: instance.offset.title,
                    message: "Cancel failed before reschedule"
                ))
                continue
            }

            let outcome = await schedule(instance, snoozeSeconds: snoozeSeconds)
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

        let duplicates = await reconcileOrphanAlarms(events: events)
        SchedulerLog.info("reschedule complete scheduled=\(scheduledCount) cleaned=\(cleaned + duplicates) failures=\(failures.count)")
        return RescheduleResult(
            scheduledCount: scheduledCount,
            failures: failures,
            skippedDuringAlerting: false,
            skippedTooSoon: skippedTooSoon
        )
    }

    func cancelRemoved(eventIDs: Set<String>) async {
        // Not cancellable: by now `events` no longer lists these IDs, so a skipped cancel
        // leaves an orphan that rings next to its replacement.
        for eventID in eventIDs {
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
        try? AlarmManager.shared.cancel(id: AlarmSchedulingHelpers.fallbackAlarmID(for: id))
        return cancel(alarmID: id, occurrenceID: occurrenceID)
    }

    @discardableResult
    private func cancel(alarmID id: UUID, occurrenceID: String) -> Bool {
        do {
            try AlarmManager.shared.cancel(id: id)
            Self.setCountdownTarget(nil, for: id)
            Self.setTitle(nil, for: id)
            AlarmJournalStore.record(.cancelled, alarmID: id.uuidString, occurrenceID: occurrenceID)
            return true
        } catch {
            SchedulerLog.warning("cancel failed \(occurrenceID) \(id): \(error.localizedDescription)")
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
            // Countdown mode, like the Live Activity alarm. It used to be `.fixed` plus an
            // equal pre-alert, to probe how AlarmKit times that pair; on 2026-09-24 the device
            // answered "Late · 16s", confirming the countdown starts at the fixed date.
            let configuration = AlarmConfiguration(
                countdownDuration: Alarm.CountdownDuration(preAlert: testPreAlert, postAlert: snoozeSeconds),
                schedule: nil,
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: idString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: idString),
                sound: alertSound(vibrates: AlarmSoundPolicy.vibratesNow)
            )
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            // Without a stored target the orphan reconciler sees a dateless countdown and
            // cancels it before it rings.
            Self.setCountdownTarget(fireDate, for: alarmID)
            AlarmJournalStore.record(.scheduled, alarmID: idString, occurrenceID: testID, intendedFire: fireDate)
            AlarmJournalStore.recordTestProbe(alarmID: idString, scheduledAt: scheduledAt, preAlert: testPreAlert)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Moves a vibrating alarm's ringing fallback to follow its snooze. Cancelling it outright
    /// left the post-snooze vibration with nothing behind it.
    func moveFallbackAfterSnooze(primaryID: UUID) async {
        let fallbackID = AlarmSchedulingHelpers.fallbackAlarmID(for: primaryID)
        try? AlarmManager.shared.cancel(id: fallbackID)
        Self.setTitle(nil, for: fallbackID)
        let vibrateSuffix = "|vibrate"
        guard let signature = Self.title(for: primaryID), signature.hasSuffix(vibrateSuffix) else { return }
        let title = String(signature.dropLast(vibrateSuffix.count))
        let snoozeSeconds = persistedSnoozeSeconds
        let fireDate = Date().addingTimeInterval(snoozeSeconds + AlarmSoundPolicy.fallbackDelay)
        let idString = fallbackID.uuidString

        do {
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
                secondaryButtonBehavior: .countdown
            )
            let attributes = AlarmAttributes<AlarmAppMetadata>(
                presentation: AlarmPresentation(alert: alert),
                metadata: AlarmAppMetadata(title: title, accentRawValue: CalarmPersistence.string(forKey: CalarmPersistence.Key.themeAccent)),
                tintColor: resolvedAccentColor()
            )
            let configuration = AlarmConfiguration(
                countdownDuration: Alarm.CountdownDuration(preAlert: 1, postAlert: snoozeSeconds),
                schedule: .fixed(fireDate),
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: idString),
                secondaryIntent: SnoozeAlarmIntent(alarmID: idString),
                sound: .default
            )
            _ = try await AlarmManager.shared.schedule(id: fallbackID, configuration: configuration)
            Self.setTitle("\(title)|ring", for: fallbackID)
            AlarmJournalStore.record(.scheduled, alarmID: idString, intendedFire: fireDate)
        } catch {
            SchedulerLog.error("snooze fallback failed \(primaryID): \(error.localizedDescription)")
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

    /// Cancel orphaned AlarmKit alarms (dropped events, ID migrations) once stale, or earlier
    /// when a managed alarm already rings at the same moment. Other future orphans are kept.
    @discardableResult
    func reconcileOrphanAlarms(events: [ScheduleEvent]) async -> Int {
        let lookup = alarmEventLookup(for: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []
        // Only alarms that will actually ring stand in for an orphan: not fallbacks, which a
        // dismissed vibration cancels, and not alarms about to be cancelled as undesired.
        let primaryIDs = Set(buildDesiredInstances(from: events).filter { !$0.isFallback }.map(\.alarmID))
        let managedFireDates = currentAlarms.filter { primaryIDs.contains($0.id) }.compactMap(intendedFireDate(for:))
        var terminated = 0

        for alarm in currentAlarms {
            guard !Task.isCancelled else { break }
            guard lookup[alarm.id] == nil else { continue }

            if let fireDate = intendedFireDate(for: alarm) {
                // A future orphan is kept so a meeting briefly missing from a fetch still
                // rings, unless a managed alarm already rings at the same moment.
                let duplicate = AlarmSchedulingHelpers.isDuplicateFire(fireDate, of: managedFireDates)
                guard duplicate || shouldTerminateOrphan(alarm: alarm, fireDate: fireDate) else { continue }
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
        let fallbackPrimaries = fallbackPrimaries(for: events)
        var terminated = 0

        for alarm in currentAlarms {
            guard !Task.isCancelled else { break }
            guard lookup[alarm.id] != nil else { continue }
            guard !desiredIDs.contains(alarm.id) else { continue }
            if isHeldBySnoozeOrAlert(fallbackID: alarm.id, primaries: fallbackPrimaries, alarms: currentAlarms) { continue }

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
            ("\($0.occurrenceID)|\($0.title)", $0.offset.rawValue, $0.fireDate)
        }
        let accentRaw = CalarmPersistence.string(forKey: CalarmPersistence.Key.themeAccent) ?? CalarmAccent.amber.rawValue
        let liveActivityEvent = desired.first(where: \.withLiveActivity)?.event
        return AlarmSchedulingHelpers.schedulingFingerprint(
            instances: rows,
            nextLiveActivityKey: nextKey,
            snoozeRawValue: "\(Int(snoozeSeconds))|\(AlarmSoundPolicy.vibratesNow ? "vibrate" : "ring")",
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

    private func buildDesiredInstances(from events: [ScheduleEvent], now: Date = Date()) -> [DesiredInstance] {
        let vibrates = AlarmSoundPolicy.vibratesNow
        // While vibrating, an alarm that fired within the last minute still anchors the
        // fallback behind it. Dropping it the moment it fired cancelled that fallback on the
        // very reconcile its own alerting triggered.
        let earliest = vibrates ? now.addingTimeInterval(-AlarmSoundPolicy.fallbackDelay) : now
        let sources = events.flatMap { event in
            event.alarmOffsets
                .map { ScheduledAlarm(offset: $0, fireDate: $0.fireDate(for: event.startDate)) }
                .filter { $0.fireDate > earliest }
                .map { (event: event, alarm: $0) }
        }
        let sourceByKey = Dictionary(
            sources.map {
                (AlarmSchedulingHelpers.liveActivityKey(occurrenceID: $0.event.id, offsetRawValue: $0.alarm.offset.rawValue), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let groups = AlarmGrouping.groups(sources.map {
            AlarmGrouping.Member(
                occurrenceID: $0.event.id,
                offsetRawValue: $0.alarm.offset.rawValue,
                fireDate: $0.alarm.fireDate,
                title: $0.event.title,
                startDate: $0.event.startDate,
                isBusyOnly: $0.event.isBusyOnly
            )
        })

        let anchors: [(group: AlarmGrouping.Group, source: (event: ScheduleEvent, alarm: ScheduledAlarm))] = groups.compactMap { group in
            let key = AlarmSchedulingHelpers.liveActivityKey(
                occurrenceID: group.primary.occurrenceID,
                offsetRawValue: group.primary.offsetRawValue
            )
            return sourceByKey[key].map { (group, $0) }
        }

        let upcoming = anchors.filter { $0.group.fireDate > now }
        let primaries: [DesiredInstance] = upcoming.enumerated().map { index, anchor in
            DesiredInstance(
                event: anchor.source.event,
                alarm: anchor.source.alarm,
                fireDate: anchor.group.fireDate,
                title: anchor.group.title,
                withLiveActivity: index == 0,
                alarmID: stableAlarmID(for: anchor.source.event.id, offset: anchor.source.alarm.offset),
                vibrates: vibrates,
                isFallback: false
            )
        }
        guard vibrates else { return primaries }

        let upcomingFireDates = primaries.map(\.fireDate)
        let fallbacks: [DesiredInstance] = anchors.compactMap { anchor in
            guard let fireDate = AlarmSoundPolicy.fallbackFireDate(
                anchor: anchor.group.fireDate,
                upcomingFireDates: upcomingFireDates,
                now: now
            ) else { return nil }
            return DesiredInstance(
                event: anchor.source.event,
                alarm: anchor.source.alarm,
                fireDate: fireDate,
                title: anchor.group.title,
                withLiveActivity: false,
                alarmID: AlarmSchedulingHelpers.fallbackAlarmID(
                    for: stableAlarmID(for: anchor.source.event.id, offset: anchor.source.alarm.offset)
                ),
                vibrates: false,
                isFallback: true
            )
        }
        return (primaries + fallbacks).sorted { $0.fireDate < $1.fireDate }
    }

    /// Fallback ID → the vibrating alarm it backs, for every alarm these events could own.
    private func fallbackPrimaries(for events: [ScheduleEvent]) -> [UUID: UUID] {
        var map: [UUID: UUID] = [:]
        for event in events {
            for offset in AlarmOffsetOption.schedulableOffsets {
                let id = stableAlarmID(for: event.id, offset: offset)
                map[AlarmSchedulingHelpers.fallbackAlarmID(for: id)] = id
            }
        }
        return map
    }

    /// A fallback whose vibrating alarm is ringing or snoozed is live, whatever the schedule
    /// says: the snooze intent moved it to follow the snooze.
    private func isHeldBySnoozeOrAlert(fallbackID: UUID, primaries: [UUID: UUID], alarms: [Alarm], now: Date = Date()) -> Bool {
        guard let primaryID = primaries[fallbackID],
              let primary = alarms.first(where: { $0.id == primaryID }) else { return false }
        switch primary.state {
        case .alerting:
            return true
        case .countdown, .paused:
            return intendedFireDate(for: primary).map { $0 <= now } ?? false
        default:
            return false
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

        if Self.title(for: existing.id) != instance.signature { return true }

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
            Self.setTitle(nil, for: alarm.id)
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
                let id = stableAlarmID(for: event.id, offset: offset)
                lookup[id] = event
                lookup[AlarmSchedulingHelpers.fallbackAlarmID(for: id)] = event
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

    private static func titles() -> [String: String] {
        CalarmPersistence.decode([String: String].self, forKey: CalarmPersistence.Key.alarmTitles) ?? [:]
    }

    private static func title(for id: UUID) -> String? {
        titles()[id.uuidString]
    }

    /// The event title an alarm was scheduled with, for the activity log. The stored value
    /// is a signature, `title|ring` or `title|vibrate`.
    static func displayTitle(for id: UUID) -> String {
        guard let signature = title(for: id), let bar = signature.lastIndex(of: "|") else { return "Alarm" }
        return String(signature[..<bar])
    }

    private static func setTitle(_ title: String?, for id: UUID) {
        var all = titles()
        guard all[id.uuidString] != title else { return }
        all[id.uuidString] = title
        saveTitles(all)
    }

    private static func pruneTitles(keeping ids: Set<UUID>) {
        let all = titles()
        let kept = all.filter { key, _ in UUID(uuidString: key).map(ids.contains) ?? false }
        guard kept.count != all.count else { return }
        saveTitles(kept)
    }

    private static func saveTitles(_ titles: [String: String]) {
        if titles.isEmpty {
            CalarmPersistence.remove(forKey: CalarmPersistence.Key.alarmTitles)
        } else {
            CalarmPersistence.encode(titles, forKey: CalarmPersistence.Key.alarmTitles)
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

    private var persistedSnoozeSeconds: TimeInterval {
        let minutes = CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
            ? CalarmPersistence.integer(forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
            : SnoozeDurationOption.fiveMinutes.rawValue
        return TimeInterval(minutes * 60)
    }

    private var snoozeAwareCountdownGrace: TimeInterval {
        AlarmSchedulingHelpers.snoozeAwareCountdownGrace(snoozeSeconds: persistedSnoozeSeconds)
    }

    private func alertSound(vibrates: Bool) -> AlertConfiguration.AlertSound {
        vibrates ? .named(AlarmSoundPolicy.silentSoundName) : .default
    }

    private func schedule(_ instance: DesiredInstance, snoozeSeconds: TimeInterval) async -> ScheduleOutcome {
        let event = instance.event
        let offset = instance.offset
        let fireDate = instance.fireDate
        let title = instance.title
        let withLiveActivity = instance.withLiveActivity
        guard offset.isSchedulable else { return .failed("Offset not schedulable") }
        let alarmID = instance.alarmID
        let idString = alarmID.uuidString
        let secondsUntilAlarm = fireDate.timeIntervalSinceNow
        guard secondsUntilAlarm > 1 else { return .tooSoon }

        do {
            let stopButton = AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "stop.circle")
            let snoozeButton = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
            let alertPresentation = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
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
                        title: LocalizedStringResource(stringLiteral: title),
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
                    title: title,
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
                secondaryIntent: SnoozeAlarmIntent(alarmID: idString),
                sound: alertSound(vibrates: instance.vibrates)
            )

            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
            Self.setCountdownTarget(withLiveActivity ? fireDate : nil, for: alarmID)
            Self.setTitle(instance.signature, for: alarmID)
            AlarmJournalStore.record(
                .scheduled,
                alarmID: idString,
                occurrenceID: event.id,
                intendedFire: fireDate
            )
            SchedulerLog.info("scheduled \(event.id) \(offset.rawValue) fire=\(fireDate) liveActivity=\(withLiveActivity) vibrates=\(instance.vibrates)")
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
