//
//  AlarmSoundPolicy.swift
//  Calarm
//

import Foundation

/// Whether alarms ring or only vibrate.
///
/// Vibrate means vibrate only. A ringing fallback a minute later used to follow an
/// undismissed vibration; the owner ruled one ring per chosen offset, so it is gone.
/// `AlarmSchedulingHelpers.fallbackAlarmID` survives only to cancel fallbacks left by
/// earlier builds.
///
/// iOS offers no way to read the Ring/Silent switch, and CALarm is not running when an alarm
/// fires, so "vibrate when the phone is silent" cannot be automatic. Vibrating is chosen
/// instead by a manual setting or by a Focus filter. AlarmKit has no vibrate-only sound
/// either; a silent sound file is the only route, and the system still vibrates.
nonisolated enum AlarmSoundPolicy {
    static let silentSoundName = "calarm-silence.caf"

    static func vibrates(manualSetting: Bool, focusActive: Bool) -> Bool {
        manualSetting || focusActive
    }

    @MainActor static var vibratesNow: Bool {
        vibrates(
            manualSetting: CalarmPersistence.bool(forKey: CalarmPersistence.Key.vibrateInsteadOfRinging),
            focusActive: CalarmPersistence.bool(forKey: CalarmPersistence.Key.focusVibrate)
        )
    }
}
