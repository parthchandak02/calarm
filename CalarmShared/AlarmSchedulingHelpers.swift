//
//  AlarmSchedulingHelpers.swift
//  CalarmShared
//

import CryptoKit
import Foundation

enum AlarmSchedulingHelpers {
    static func stableAlarmID(occurrenceID: String, offsetRawValue: String) -> UUID {
        let digest = SHA256.hash(data: Data("calarm.\(occurrenceID).\(offsetRawValue)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
        liveActivityTintKey: String? = nil
    ) -> String {
        let rows = instances.map {
            "\($0.occurrenceID).\($0.offsetRawValue).\(Int($0.fireDate.timeIntervalSince1970))"
        }.sorted()
        return (rows + [
            "la:\(nextLiveActivityKey ?? "none")",
            "snooze:\(snoozeRawValue)",
            "accent:\(accentRawValue)",
            "tint:\(liveActivityTintKey ?? "accent")"
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

/// What the 8-second test alarm reveals about AlarmKit's countdown timing.
///
/// The test alarm deliberately uses a `.fixed` schedule *and* a pre-alert of the same
/// length. Apple documents the countdown as ending at the fixed date, so it should ring
/// ~8s after the tap. If it rings ~16s after, AlarmKit starts the countdown *at* the fixed
/// date instead — the behaviour that put a 9:00 event's countdown on the lock screen at
/// 10:14 with no event there.
nonisolated enum AlarmTimingProbe {
    enum Verdict: Equatable {
        case pending
        case onTime(seconds: Int)
        case countdownStartsAtFireDate(seconds: Int)
        case other(seconds: Int)
    }

    static func verdict(scheduledAt: Date, preAlert: TimeInterval, observedAt: Date?) -> Verdict {
        guard let observedAt else { return .pending }
        let elapsed = observedAt.timeIntervalSince(scheduledAt)
        let seconds = Int(elapsed.rounded())
        let slack: TimeInterval = 3
        if abs(elapsed - preAlert) <= slack { return .onTime(seconds: seconds) }
        if abs(elapsed - 2 * preAlert) <= slack { return .countdownStartsAtFireDate(seconds: seconds) }
        return .other(seconds: seconds)
    }
}
