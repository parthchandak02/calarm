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

    /// What the activity log and Status say, including which switch asked for vibration.
    static func label(manualSetting: Bool, focusActive: Bool) -> String {
        switch (manualSetting, focusActive) {
        case (false, false): "ring"
        case (true, false): "vibrate · setting"
        case (false, true): "vibrate · focus"
        case (true, true): "vibrate · setting + focus"
        }
    }

    /// The sound an alarm was scheduled with, read from its stored `title|ring` or
    /// `title|vibrate` signature. Nil for an alarm scheduled without one, like the test alarm.
    static func vibrates(signature: String?) -> Bool? {
        guard let signature else { return nil }
        if signature.hasSuffix("|vibrate") { return true }
        if signature.hasSuffix("|ring") { return false }
        return nil
    }

    @MainActor static var vibratesNow: Bool {
        vibrates(manualSetting: manualSetting, focusActive: focusActive)
    }

    @MainActor static var labelNow: String {
        label(manualSetting: manualSetting, focusActive: focusActive)
    }

    @MainActor private static var manualSetting: Bool {
        CalarmPersistence.bool(forKey: CalarmPersistence.Key.vibrateInsteadOfRinging)
    }

    @MainActor private static var focusActive: Bool {
        CalarmPersistence.bool(forKey: CalarmPersistence.Key.focusVibrate)
    }
}
