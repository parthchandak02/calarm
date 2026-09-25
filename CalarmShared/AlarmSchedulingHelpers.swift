//
//  AlarmSchedulingHelpers.swift
//  CalarmShared
//

import CryptoKit
import Foundation

enum AlarmSchedulingHelpers {
    nonisolated static func stableAlarmID(occurrenceID: String, offsetRawValue: String) -> UUID {
        let digest = SHA256.hash(data: Data("calarm.\(occurrenceID).\(offsetRawValue)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// The ringing alarm that follows a vibrating one. Derived from the vibrating alarm's ID
    /// so the stop and snooze intents can cancel it knowing only that ID.
    nonisolated static func fallbackAlarmID(for alarmID: UUID) -> UUID {
        stableAlarmID(occurrenceID: alarmID.uuidString, offsetRawValue: "fallback")
    }

    static func liveActivityKey(occurrenceID: String, offsetRawValue: String) -> String {
        "\(occurrenceID).\(offsetRawValue)"
    }

    /// Stable fingerprint of desired AlarmKit schedules (occurrence, offset, fire time, snooze, accent).
    static func schedulingFingerprint(
        instances: [(occurrenceID: String, offsetRawValue: String, fireDate: Date)],
        nextLiveActivityKey: String?,
        snoozeRawValue: String,
        accentRawValue: String,
        liveActivityTintKey: String? = nil,
        liveActivityLeadMinutes: Int
    ) -> String {
        let rows = instances.map {
            "\($0.occurrenceID).\($0.offsetRawValue).\(Int($0.fireDate.timeIntervalSince1970))"
        }.sorted()
        return (rows + [
            "la:\(nextLiveActivityKey ?? "none")",
            "snooze:\(snoozeRawValue)",
            "accent:\(accentRawValue)",
            "tint:\(liveActivityTintKey ?? "accent")",
            "lead:\(liveActivityLeadMinutes)"
        ]).joined(separator: "|")
    }

    /// Window within which an orphaned alarm counts as ringing alongside a managed one. Narrower
    /// than the one-minute gap between any two distinct alarm times.
    static let duplicateFireTolerance: TimeInterval = 30

    /// True when `fireDate` lands on top of an alarm that is still managed. An orphan left by
    /// an occurrence-ID change (EventKit to Google, a re-inserted event) is the same meeting
    /// ringing a second time, so it is safe to cancel: the managed alarm still rings.
    static func isDuplicateFire(_ fireDate: Date, of managedFireDates: [Date]) -> Bool {
        managedFireDates.contains { abs($0.timeIntervalSince(fireDate)) <= duplicateFireTolerance }
    }

    /// True when a fixed-schedule alarm's fire time has elapsed and it should be cancelled.
    /// Pass `graceAfterFire` to allow a short post-fire window (e.g. snooze).
    static func isStaleAlarm(fireDate: Date, now: Date = Date(), graceAfterFire: TimeInterval = 0) -> Bool {
        now.timeIntervalSince(fireDate) >= graceAfterFire
    }

    /// Grace after scheduled fire before cancelling a stuck `.countdown`/`.paused` alarm.
    static let countdownCleanupGrace: TimeInterval = 60

    /// Grace after scheduled fire before silencing a stale `.alerting` alarm (snooze window).
    static let alertingCleanupGrace: TimeInterval = 5 * 60

    /// True when an alarm still has meaningful pre-alert countdown time remaining.
    static func hasUpcomingFireDate(_ fireDate: Date, now: Date = Date()) -> Bool {
        fireDate.timeIntervalSince(now) > 1
    }

    /// Calendar alarms should end after the event block finishes, even if still alerting.
    static func isEventEnded(endDate: Date, now: Date = Date()) -> Bool {
        now >= endDate
    }

    /// Grace after the intended fire time before a `.countdown`/`.paused` alarm counts as
    /// stuck. A countdown past its fire time is normally a snooze, so the grace has to
    /// outlast one; cancelling at a flat 60s silently killed every snooze the moment the
    /// app came to the foreground.
    static func snoozeAwareCountdownGrace(snoozeSeconds: TimeInterval) -> TimeInterval {
        max(countdownCleanupGrace, snoozeSeconds + countdownCleanupGrace)
    }

    /// When a `.countdown`/`.paused` alarm past its ring time stops counting as a snooze in
    /// progress. Keyed to the snooze's own end when the snooze intent recorded one: keyed to
    /// the original ring time, a second snooze outlived the grace and was cancelled.
    static func snoozeHoldDeadline(fireDate: Date, snoozedUntil: Date?, snoozeSeconds: TimeInterval) -> Date {
        if let snoozedUntil { return snoozedUntil.addingTimeInterval(countdownCleanupGrace) }
        return fireDate.addingTimeInterval(snoozeAwareCountdownGrace(snoozeSeconds: snoozeSeconds))
    }

    /// When an `.alerting` alarm counts as stale: five minutes after the ring, or after the
    /// re-ring a recorded snooze ends in.
    static func alertingDeadline(fireDate: Date, snoozedUntil: Date?, snoozeSeconds: TimeInterval) -> Date {
        if let snoozedUntil { return snoozedUntil.addingTimeInterval(alertingCleanupGrace) }
        return fireDate.addingTimeInterval(snoozeAwareAlertingGrace(snoozeSeconds: snoozeSeconds))
    }

    /// True when a `.countdown`/`.paused` alarm is a snooze still in progress. A snoozed alarm
    /// has left the desired schedule, which holds only upcoming alarms, but cancelling it
    /// silently kills the snooze.
    static func isSnoozeHold(
        isCountingDown: Bool,
        fireDate: Date?,
        snoozedUntil: Date? = nil,
        now: Date = Date(),
        snoozeSeconds: TimeInterval
    ) -> Bool {
        guard isCountingDown else { return false }
        if let snoozedUntil {
            return now < snoozedUntil.addingTimeInterval(countdownCleanupGrace)
        }
        guard let fireDate, fireDate <= now else { return false }
        return now < snoozeHoldDeadline(fireDate: fireDate, snoozedUntil: nil, snoozeSeconds: snoozeSeconds)
    }

    /// Grace after the intended fire time before an `.alerting` alarm counts as stale when no
    /// snooze was recorded. Covers one snooze from a build that did not record them.
    static func snoozeAwareAlertingGrace(snoozeSeconds: TimeInterval) -> TimeInterval {
        max(alertingCleanupGrace, snoozeSeconds + alertingCleanupGrace)
    }

    /// True when an alarm should go because its event ended. A snooze or ring still held
    /// outlives the event: a short meeting otherwise killed its own alarm.
    static func shouldEndWithEvent(endDate: Date, holdUntil: Date?, now: Date = Date()) -> Bool {
        now >= max(endDate, holdUntil ?? endDate)
    }

    /// True when `fireDate` is the ring an alarm ID already made. Under Apple's documented
    /// timing a window alarm rings its lead early; re-creating it for the same fire date
    /// would ring a second time.
    static func alreadyRang(fireDate: Date, rangFireDate: Date?) -> Bool {
        guard let rangFireDate else { return false }
        return abs(rangFireDate.timeIntervalSince(fireDate)) <= 1
    }

    /// Width for the compact Dynamic Island countdown, keyed to the time left when the
    /// widget renders.
    ///
    /// The timer text reserves its width once per render and AlarmKit re-renders only on
    /// a state change, so the pill cannot shrink mid-countdown. Remaining time only goes
    /// down, though, so sizing from it at render can only ever be too wide, never too
    /// narrow — and every re-render tightens it. Measured at 11pt semibold rounded:
    /// `59:59` is 33pt, `23:59:59` is 51pt.
    static func compactCountdownWidth(remaining: TimeInterval) -> Double {
        if remaining >= 3_600 { return 58 }
        if remaining >= 600 { return 38 }
        return 28
    }

    /// A countdown running past the event's start can only be a snooze: every offset
    /// fires at or before the start.
    static func isSnoozeCountdown(countdownFireDate: Date, eventStart: Date?) -> Bool {
        guard let eventStart else { return false }
        return countdownFireDate > eventStart.addingTimeInterval(1)
    }
}

/// What the test alarm reveals about AlarmKit's countdown timing.
///
/// With a Live Activity lead set, the test alarm is scheduled like a window alarm: `.fixed`
/// eight seconds out with an eight second pre-alert, expected to ring at ~16s because on
/// device the countdown starts *at* the fixed date. Ringing at ~8s means the device follows
/// Apple's documented reading instead, and every window alarm rings its lead early. With
/// Always it is countdown mode, expected at ~8s; ~16s there is the old late behaviour.
nonisolated enum AlarmTimingProbe {
    enum Verdict: Equatable {
        case pending
        case onTime(seconds: Int)
        case early(seconds: Int)
        case countdownStartsAtFireDate(seconds: Int)
        case other(seconds: Int)
    }

    static func verdict(
        scheduledAt: Date,
        preAlert: TimeInterval,
        expectedRing: TimeInterval? = nil,
        observedAt: Date?
    ) -> Verdict {
        guard let observedAt else { return .pending }
        let expected = expectedRing ?? preAlert
        let elapsed = observedAt.timeIntervalSince(scheduledAt)
        let seconds = Int(elapsed.rounded())
        let slack: TimeInterval = 3
        if abs(elapsed - expected) <= slack { return .onTime(seconds: seconds) }
        if expected > preAlert, abs(elapsed - (expected - preAlert)) <= slack { return .early(seconds: seconds) }
        if abs(elapsed - (expected + preAlert)) <= slack { return .countdownStartsAtFireDate(seconds: seconds) }
        return .other(seconds: seconds)
    }
}
