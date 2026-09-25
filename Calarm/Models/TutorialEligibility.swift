//
//  TutorialEligibility.swift
//  Calarm
//

import Foundation

/// Decides whether first-run tips belong on this install. Anyone who has already been
/// through a permission prompt or saved a preference has used CALarm before the tips
/// existed, and should not be walked through it again.
nonisolated enum TutorialEligibility {
    struct Signals: Equatable {
        var alarmPermissionAsked: Bool
        var calendarPermissionAsked: Bool
        var googleConnected: Bool
        var hasSavedPreferences: Bool
    }

    static func isReturningUser(_ signals: Signals) -> Bool {
        signals.alarmPermissionAsked
            || signals.calendarPermissionAsked
            || signals.googleConnected
            || signals.hasSavedPreferences
    }
}
