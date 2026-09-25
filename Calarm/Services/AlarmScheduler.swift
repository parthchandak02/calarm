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

    struct DesiredInstance {
        let event: ScheduleEvent
        let alarm: ScheduledAlarm
        let fireDate: Date
        let title: String
        let plan: LiveActivityPlan
        let alarmID: UUID
        let vibrates: Bool

        /// Title plus sound: what AlarmKit will not report back, so `needsReschedule` compares
        /// the stored copy.
        var signature: String { "\(title)|\(vibrates ? "vibrate" : "ring")" }

        var withLiveActivity: Bool { plan.showsLiveActivity }
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
        let currentAlarms: [Alarm]
        do {
            currentAlarms = try AlarmManager.shared.alarms
            // AlarmKit deletes spent alarms silently, so their stored state goes with them here.
            // Only on a successful read: `alarms` throwing looks like "nothing scheduled", and
            // pruning then wiped every stored ring time.
            Self.pruneStoredState(keeping: Set(currentAlarms.map(\.id)))
        } catch {
            // Scheduling blind would cancel and recreate every alarm, ringing ones included.
            // Existing alarms stay armed; the failure keeps the fingerprint unsaved so the
            // next trigger retries.
            SchedulerLog.warning("alarms read failed: \(error.localizedDescription)")
            return RescheduleResult(
                scheduledCount: 0,
                failures: [ScheduleFailure(
                    occurrenceID: "",
                    eventTitle: "Alarms",
                    offsetTitle: "",
                    message: "Could not read scheduled alarms: \(error.localizedDescription)"
                )],
                skippedDuringAlerting: false,
                skippedTooSoon: []
            )
        }

        for instance in desired {
            guard !Task.isCancelled else { break }
            let existing = currentAlarms.first { $0.id == instance.alarmID }
            if !force, let existing, !needsReschedule(existing: existing, instance: instance, snoozeSeconds: snoozeSeconds) {
                continue
            }
            if let existing, isAlerting(existing) { continue }
            // Before the cancel: a forced reschedule under a second out otherwise cancelled an
            // alarm it could not replace.
            guard instance.fireDate.timeIntervalSinceNow > 1 else {
                skippedTooSoon.append((instance.occurrenceID, instance.event.title, instance.offset))
                continue
            }

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
        // Earlier builds armed a ringing fallback behind each vibrating alarm.
        try? AlarmManager.shared.cancel(id: AlarmSchedulingHelpers.fallbackAlarmID(for: id))
        return cancel(alarmID: id, occurrenceID: occurrenceID)
    }

    @discardableResult
    private func cancel(alarmID id: UUID, occurrenceID: String) -> Bool {
        do {
            try AlarmManager.shared.cancel(id: id)
            Self.clearStoredState(for: id)
            AlarmJournalStore.record(.cancelled, alarmID: id.uuidString, occurrenceID: occurrenceID)
            return true
        } catch {
            SchedulerLog.warning("cancel failed \(occurrenceID) \(id): \(error.localizedDescription)")
            return false
        }
    }

    /// Seconds from tap to ring for the test alarm under `lead`: a window alarm is `.fixed`
    /// eight seconds out with an eight second pre-alert, so on device it rings at 16s.
    nonisolated static func testAlarmExpectedRing(lead: LiveActivityLead) -> TimeInterval {
        lead == .always ? testPreAlert : 2 * testPreAlert
    }

    nonisolated private static let testPreAlert: TimeInterval = 8

    func scheduleTestAlarm(snoozeSeconds: TimeInterval, lead: LiveActivityLead) async -> String? {
        let testPreAlert = Self.testPreAlert
        let scheduledAt = Date()
        let usesWindow = lead != .always
        let fireDate = scheduledAt.addingTimeInterval(Self.testAlarmExpectedRing(lead: lead))
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
            // Scheduled the way real alarms are under `lead`, so it exercises the shipping path:
            // countdown mode for Always, else a window `.fixed` at +8s with an 8s pre-alert.
            // On 2026-09-24 the device showed that pair counting down from the fixed date
            // ("Late · 16s"), which the window scheduling now relies on.
            let configuration = AlarmConfiguration(
                countdownDuration: Alarm.CountdownDuration(preAlert: testPreAlert, postAlert: snoozeSeconds),
                schedule: usesWindow ? .fixed(scheduledAt.addingTimeInterval(testPreAlert)) : nil,
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
            AlarmJournalStore.recordTestProbe(
                alarmID: idString,
                scheduledAt: scheduledAt,
                preAlert: testPreAlert,
                expectedRing: Self.testAlarmExpectedRing(lead: lead)
            )
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
        let fallbacks = cancelLegacyFallbacks()
        return orphans + stale + undesired + fallbacks
    }

    /// Cancels every ringing fallback an earlier build armed behind a vibrating alarm, including
    /// those of events no longer listed, which `alarmEventLookup` cannot reach. Candidates are
    /// every alarm ID this app still knows of: in AlarmKit, in stored state, in the journal.
    @discardableResult
    func cancelLegacyFallbacks() -> Int {
        guard let alarms = try? AlarmManager.shared.alarms, !alarms.isEmpty else { return 0 }
        let current = Set(alarms.map(\.id))
        var candidates = current
        for key in [CalarmPersistence.Key.countdownTargets, CalarmPersistence.Key.snoozedUntil] {
            candidates.formUnion(Self.storedDates(key).keys.compactMap(UUID.init(uuidString:)))
        }
        candidates.formUnion(Self.titles().keys.compactMap(UUID.init(uuidString:)))
        candidates.formUnion(AlarmJournalStore.load().compactMap { UUID(uuidString: $0.alarmID) })

        var cancelled = 0
        for id in candidates {
            let fallbackID = AlarmSchedulingHelpers.fallbackAlarmID(for: id)
            guard current.contains(fallbackID), let alarm = alarms.first(where: { $0.id == fallbackID }) else { continue }
            if terminate(alarm) {
                cancelled += 1
                SchedulerLog.info("cancelled legacy fallback \(fallbackID)")
            }
        }
        return cancelled
    }

    /// Cancel orphaned AlarmKit alarms (dropped events, ID migrations) once stale, or earlier
    /// when a managed alarm already rings at the same moment. Other future orphans are kept.
    @discardableResult
    func reconcileOrphanAlarms(events: [ScheduleEvent]) async -> Int {
        let lookup = alarmEventLookup(for: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []
        // Only alarms that will actually ring stand in for an orphan, not ones about to be
        // cancelled as undesired.
        let primaryIDs = Set(buildDesiredInstances(from: events).map(\.alarmID))
        let managedFireDates = currentAlarms.filter { primaryIDs.contains($0.id) }.compactMap(intendedFireDate(for:))
        var terminated = 0

        for alarm in currentAlarms {
            guard !Task.isCancelled else { break }
            guard lookup[alarm.id] == nil else { continue }

            if let fireDate = intendedFireDate(for: alarm) {
                // A future orphan is kept so a meeting briefly missing from a fetch still
                // rings, unless a managed alarm already rings at the same moment. A snooze in
                // progress is never a duplicate: nothing else will ring for it.
                let duplicate = !isSnoozeHold(alarm, fireDate: fireDate)
                    && AlarmSchedulingHelpers.isDuplicateFire(fireDate, of: managedFireDates)
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
        let fallbackIDs = legacyFallbackIDs(for: events)
        let currentAlarms = (try? AlarmManager.shared.alarms) ?? []
        var terminated = 0

        for alarm in currentAlarms {
            guard !Task.isCancelled else { break }
            guard let event = lookup[alarm.id] else { continue }
            guard !desiredIDs.contains(alarm.id) else { continue }
            // Upcoming alarms only are desired, so a snoozed or ringing one is never in the
            // set. Terminating it here killed every snooze, in ring mode too. A legacy
            // fallback is a second ring and always goes.
            if !fallbackIDs.contains(alarm.id),
               let holdUntil = holdUntil(for: alarm),
               !AlarmSchedulingHelpers.shouldEndWithEvent(endDate: event.endDate, holdUntil: holdUntil),
               Date() < holdUntil {
                continue
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
            liveActivityTintKey: liveActivityTintKey(for: liveActivityEvent, accentRaw: accentRaw),
            liveActivityLeadMinutes: LiveActivityLead.persisted.rawValue
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
        Self.desiredInstances(
            events: events,
            vibrates: AlarmSoundPolicy.vibratesNow,
            lead: LiveActivityLead.persisted,
            rangFireDates: Self.storedDateMap(CalarmPersistence.Key.rangFireDates),
            now: now
        )
    }

    /// One instance per upcoming alarm minute: exactly one ring per chosen offset, vibrating
    /// or not. An alarm ID that already rang for its fire date is left out.
    static func desiredInstances(
        events: [ScheduleEvent],
        vibrates: Bool,
        lead: LiveActivityLead,
        rangFireDates: [UUID: Date],
        now: Date
    ) -> [DesiredInstance] {
        let sources = events.flatMap { event in
            event.alarmOffsets
                .map { ScheduledAlarm(offset: $0, fireDate: $0.fireDate(for: event.startDate)) }
                .filter { $0.fireDate > now }
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

        let upcoming: [(group: AlarmGrouping.Group, source: (event: ScheduleEvent, alarm: ScheduledAlarm), alarmID: UUID)] = groups.compactMap { group in
            let key = AlarmSchedulingHelpers.liveActivityKey(
                occurrenceID: group.primary.occurrenceID,
                offsetRawValue: group.primary.offsetRawValue
            )
            guard let source = sourceByKey[key] else { return nil }
            let alarmID = AlarmSchedulingHelpers.stableAlarmID(
                occurrenceID: source.event.id,
                offsetRawValue: source.alarm.offset.rawValue
            )
            guard !AlarmSchedulingHelpers.alreadyRang(fireDate: group.fireDate, rangFireDate: rangFireDates[alarmID]) else { return nil }
            return (group, source, alarmID)
        }

        let plans = LiveActivityWindow.plans(fireDates: upcoming.map(\.group.fireDate), lead: lead, now: now)
        return zip(upcoming, plans).map { anchor, plan in
            DesiredInstance(
                event: anchor.source.event,
                alarm: anchor.source.alarm,
                fireDate: anchor.group.fireDate,
                title: anchor.group.title,
                plan: plan,
                alarmID: anchor.alarmID,
                vibrates: vibrates
            )
        }
    }

    /// Ringing fallbacks earlier builds could have armed for these events.
    private func legacyFallbackIDs(for events: [ScheduleEvent]) -> Set<UUID> {
        Set(managedAlarmIDs(for: events).map(AlarmSchedulingHelpers.fallbackAlarmID(for:)))
    }

    /// Until when a snoozed or ringing alarm is still live, or nil for any other state.
    private func holdUntil(for alarm: Alarm) -> Date? {
        guard let fireDate = intendedFireDate(for: alarm) else { return nil }
        let snoozedUntil = Self.storedDate(CalarmPersistence.Key.snoozedUntil, for: alarm.id)
        switch alarm.state {
        case .countdown, .paused:
            guard snoozedUntil != nil || fireDate <= Date() else { return nil }
            return AlarmSchedulingHelpers.snoozeHoldDeadline(fireDate: fireDate, snoozedUntil: snoozedUntil, snoozeSeconds: persistedSnoozeSeconds)
        case .alerting:
            return AlarmSchedulingHelpers.alertingDeadline(fireDate: fireDate, snoozedUntil: snoozedUntil, snoozeSeconds: persistedSnoozeSeconds)
        default:
            return nil
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

        var fixedDate: Date?
        if case .fixed(let date) = existing.schedule { fixedDate = date }
        guard LiveActivityWindow.existingSatisfies(
            plan: instance.plan,
            fireDate: instance.fireDate,
            existingFixedDate: fixedDate,
            existingPreAlert: existing.countdownDuration?.preAlert,
            storedTarget: Self.countdownTarget(for: existing.id),
            now: Date()
        ) else { return true }

        if Self.title(for: existing.id) != instance.signature { return true }

        let postAlert = existing.countdownDuration?.postAlert ?? 0
        if abs(postAlert - snoozeSeconds) > 0.5 { return true }

        return false
    }

    private func isAlerting(_ alarm: Alarm) -> Bool {
        if case .alerting = alarm.state { return true }
        return false
    }

    private func shouldTerminateStale(alarm: Alarm, event: ScheduleEvent?, fireDate: Date) -> Bool {
        let holdUntil = holdUntil(for: alarm)
        if let event, AlarmSchedulingHelpers.shouldEndWithEvent(endDate: event.endDate, holdUntil: holdUntil) {
            return true
        }
        return isPastHold(alarm: alarm, fireDate: fireDate, holdUntil: holdUntil)
    }

    private func shouldTerminateOrphan(alarm: Alarm, fireDate: Date) -> Bool {
        isPastHold(alarm: alarm, fireDate: fireDate, holdUntil: holdUntil(for: alarm))
    }

    /// Stuck countdowns go once their snooze hold ends — not at `event.endDate`, which kept a
    /// missed alarm alive for hours on a long meeting block (PR #10 regression).
    private func isPastHold(alarm: Alarm, fireDate: Date, holdUntil: Date?) -> Bool {
        switch alarm.state {
        case .countdown, .paused, .alerting:
            guard let holdUntil else { return false }
            return Date() >= holdUntil
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
            Self.clearStoredState(for: alarm.id)
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

    /// When the alarm rings. The stored target wins over the fixed date: a window alarm's
    /// fixed date is when its card appears, minutes before it rings, and a countdown-mode
    /// alarm has no date at all.
    private func intendedFireDate(for alarm: Alarm) -> Date? {
        Self.intendedFireDate(for: alarm)
    }

    static func intendedFireDate(for alarm: Alarm) -> Date? {
        var fixedDate: Date?
        if case .fixed(let date) = alarm.schedule { fixedDate = date }
        return LiveActivityWindow.resolvedFireDate(
            fixedDate: fixedDate,
            preAlert: alarm.countdownDuration?.preAlert,
            storedTarget: countdownTarget(for: alarm.id)
        )
    }

    private func isSnoozeHold(_ alarm: Alarm, fireDate: Date?) -> Bool {
        let isCountingDown: Bool
        switch alarm.state {
        case .countdown, .paused: isCountingDown = true
        default: isCountingDown = false
        }
        return AlarmSchedulingHelpers.isSnoozeHold(
            isCountingDown: isCountingDown,
            fireDate: fireDate,
            snoozedUntil: Self.storedDate(CalarmPersistence.Key.snoozedUntil, for: alarm.id),
            snoozeSeconds: persistedSnoozeSeconds
        )
    }

    static func storedDates(_ key: String) -> [String: TimeInterval] {
        CalarmPersistence.decode([String: TimeInterval].self, forKey: key) ?? [:]
    }

    private static func storedDateMap(_ key: String) -> [UUID: Date] {
        var map: [UUID: Date] = [:]
        for (key, value) in storedDates(key) {
            if let id = UUID(uuidString: key) { map[id] = Date(timeIntervalSince1970: value) }
        }
        return map
    }

    private static func storedDate(_ key: String, for id: UUID) -> Date? {
        storedDates(key)[id.uuidString].map(Date.init(timeIntervalSince1970:))
    }

    private static func setStoredDate(_ date: Date?, for id: UUID, key: String) {
        var dates = storedDates(key)
        guard dates[id.uuidString] != date?.timeIntervalSince1970 else { return }
        dates[id.uuidString] = date?.timeIntervalSince1970
        saveStoredDates(dates, key: key)
    }

    private static func saveStoredDates(_ dates: [String: TimeInterval], key: String) {
        if dates.isEmpty {
            CalarmPersistence.remove(forKey: key)
        } else {
            CalarmPersistence.encode(dates, forKey: key)
        }
    }

    private static func countdownTarget(for id: UUID) -> Date? {
        storedDate(CalarmPersistence.Key.countdownTargets, for: id)
    }

    private static func setCountdownTarget(_ date: Date?, for id: UUID) {
        setStoredDate(date, for: id, key: CalarmPersistence.Key.countdownTargets)
    }

    /// Called by `SnoozeAlarmIntent` before it snoozes, so cleanup holds the snooze until it
    /// actually ends rather than a fixed time after the first ring.
    /// Uses the alarm's own snooze length: the setting may have changed since it was
    /// scheduled (a ringing alarm is never rescheduled), and a short hold cancelled the snooze.
    static func recordSnooze(id: UUID, now: Date = Date()) {
        let alarm = (try? AlarmManager.shared.alarms)?.first { $0.id == id }
        let seconds = alarm?.countdownDuration?.postAlert ?? storedSnoozeSeconds
        setStoredDate(now.addingTimeInterval(seconds), for: id, key: CalarmPersistence.Key.snoozedUntil)
    }

    static func clearSnooze(id: UUID) {
        setStoredDate(nil, for: id, key: CalarmPersistence.Key.snoozedUntil)
    }

    /// Remembers the fire date an alarm rang for. Kept after AlarmKit deletes the alarm; that
    /// is the point. Entries expire a day after their fire date.
    static func recordRang(_ alarm: Alarm, now: Date = Date()) {
        guard let fireDate = intendedFireDate(for: alarm) else { return }
        let all = storedDates(CalarmPersistence.Key.rangFireDates)
        guard all[alarm.id.uuidString] != fireDate.timeIntervalSince1970 else { return }
        var dates = all.filter { $0.value > now.timeIntervalSince1970 - 86_400 }
        dates[alarm.id.uuidString] = fireDate.timeIntervalSince1970
        saveStoredDates(dates, key: CalarmPersistence.Key.rangFireDates)
    }

    static func recordRang(id: UUID) {
        guard let alarm = (try? AlarmManager.shared.alarms)?.first(where: { $0.id == id }) else { return }
        recordRang(alarm)
    }

    private static func clearStoredState(for id: UUID) {
        setCountdownTarget(nil, for: id)
        setTitle(nil, for: id)
        clearSnooze(id: id)
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

    private static func pruneStoredState(keeping ids: Set<UUID>) {
        pruneTitles(keeping: ids)
        for key in [CalarmPersistence.Key.countdownTargets, CalarmPersistence.Key.snoozedUntil] {
            let dates = storedDates(key)
            let kept = dates.filter { key, _ in UUID(uuidString: key).map(ids.contains) ?? false }
            if kept.count != dates.count { saveStoredDates(kept, key: key) }
        }
    }

    private var persistedSnoozeSeconds: TimeInterval { Self.storedSnoozeSeconds }

    private static var storedSnoozeSeconds: TimeInterval {
        let minutes = CalarmPersistence.objectExists(forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
            ? CalarmPersistence.integer(forKey: CalarmPersistence.Key.defaultSnoozeMinutes)
            : SnoozeDurationOption.fiveMinutes.rawValue
        return TimeInterval(minutes * 60)
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
            var plan = instance.plan
            if case .fixedWindow(let start, _) = plan, start.timeIntervalSinceNow <= 1 {
                plan = .countdownNow(preAlert: secondsUntilAlarm)
            }
            switch plan {
            case .countdownNow:
                // No schedule: a countdown that starts now and rings after `preAlert`, the
                // one combination Apple documents unambiguously.
                countdownDuration = Alarm.CountdownDuration(
                    preAlert: secondsUntilAlarm,
                    postAlert: snoozeSeconds
                )
                alarmSchedule = nil
            case .fixedWindow(let start, let preAlert):
                // `.fixed` plus a pre-alert is documented to count down *to* the fixed date,
                // but on device it counts down *from* it: a 9:00 event's countdown ran at 9:50
                // toward 10:14:54, the fixed date plus the pre-alert, and the 8-second test
                // alarm rang at 16s. So the fixed date is when the card appears, `preAlert`
                // before the ring. If a device ever follows the docs this rings `preAlert`
                // early, never late. See RESEARCH.md § Countdown timing.
                countdownDuration = Alarm.CountdownDuration(
                    preAlert: preAlert,
                    postAlert: snoozeSeconds
                )
                alarmSchedule = .fixed(start)
            case .alertOnly:
                // A one second pre-alert, and it is not cosmetic. AlarmKit alarms fail to
                // present when the foregrounded app is in landscape; Apple's own Reminders
                // works around it with exactly this, and the WWDC demo had the bug.
                // `LiveActivityWindow.existingSatisfies` treats a pre-alert this short as no
                // Live Activity, so it causes no reschedule churn. Under the start-at-fixed-date
                // behaviour this rings one second late, which is harmless.
                countdownDuration = Alarm.CountdownDuration(
                    preAlert: LiveActivityWindow.alertOnlyPreAlert,
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
            SchedulerLog.info("scheduled \(event.id) \(offset.rawValue) fire=\(fireDate) plan=\(plan) vibrates=\(instance.vibrates)")
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
