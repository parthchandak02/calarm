//
//  AlarmSoundPolicy.swift
//  Calarm
//

import Foundation

/// Whether alarms ring or only vibrate, and the safety net behind vibrating.
///
/// iOS offers no way to read the Ring/Silent switch, and CALarm is not running when an alarm
/// fires, so "vibrate when the phone is silent" cannot be automatic. Vibrating is chosen
/// instead by a manual setting or by a Focus filter. AlarmKit has no vibrate-only sound
/// either; a silent sound file is the only route, and the system still vibrates.
nonisolated enum AlarmSoundPolicy {
    static let silentSoundName = "calarm-silence.caf"

    /// A vibrating alarm is easy to miss, and a missed meeting is this app's worst outcome,
    /// so a normal ringing alarm follows unless the vibration is dismissed or snoozed first.
    static let fallbackDelay: TimeInterval = 60

    static func vibrates(manualSetting: Bool, focusActive: Bool) -> Bool {
        manualSetting || focusActive
    }

    static func fallbackFireDate(after fireDate: Date) -> Date {
        fireDate.addingTimeInterval(fallbackDelay)
    }

    /// The fallback for an alarm firing at `anchor`, or nil. The anchor may already be in the
    /// past — that alarm is vibrating right now and its fallback is still ahead. A fallback on
    /// the minute of an upcoming alarm is dropped; that alarm's own fallback covers it.
    static func fallbackFireDate(anchor: Date, upcomingFireDates: [Date], now: Date) -> Date? {
        let fireDate = fallbackFireDate(after: anchor)
        let minute = { (date: Date) in Int(date.timeIntervalSince1970 / 60) }
        guard fireDate > now, !upcomingFireDates.map(minute).contains(minute(fireDate)) else { return nil }
        return fireDate
    }

    @MainActor static var vibratesNow: Bool {
        vibrates(
            manualSetting: CalarmPersistence.bool(forKey: CalarmPersistence.Key.vibrateInsteadOfRinging),
            focusActive: CalarmPersistence.bool(forKey: CalarmPersistence.Key.focusVibrate)
        )
    }
}
