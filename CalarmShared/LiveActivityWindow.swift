//
//  LiveActivityWindow.swift
//  CalarmShared
//

import Foundation

/// How long before an alarm rings its Live Activity appears. `always` is the original
/// behaviour: the next alarm counts down from the moment it is scheduled.
nonisolated enum LiveActivityLead: Int, CaseIterable, Codable {
    case always = 0
    case ten = 10
    case five = 5
    case two = 2

    static let defaultLead: LiveActivityLead = .five

    var seconds: TimeInterval? {
        self == .always ? nil : TimeInterval(rawValue * 60)
    }

    var title: String {
        self == .always ? "Always" : "\(rawValue) minutes before"
    }
}

/// How one primary alarm is handed to AlarmKit.
nonisolated enum LiveActivityPlan: Equatable {
    /// `.fixed(fireDate)` with a one second pre-alert and no countdown presentation.
    case alertOnly
    /// `schedule: nil`, counting down from now.
    case countdownNow(preAlert: TimeInterval)
    /// `.fixed(start)` with `preAlert`. On device the countdown starts *at* the fixed date and
    /// rings `preAlert` later, so the card appears at `start` and rings at the fire date. Under
    /// Apple's documented reading it would ring at `start` instead: early, never late.
    case fixedWindow(start: Date, preAlert: TimeInterval)

    var showsLiveActivity: Bool { self != .alertOnly }
}

nonisolated enum LiveActivityWindow {
    /// Scheduling a `.fixed` date this close to now risks it passing before AlarmKit takes it.
    static let margin: TimeInterval = 10
    static let dateTolerance: TimeInterval = 0.5
    static let alertOnlyPreAlert: TimeInterval = 1

    /// One plan per fire date, in the same order. Each window ends where it rings and starts no
    /// earlier than the previous alarm's ring, so two cards never overlap.
    static func plans(
        fireDates: [Date],
        lead: LiveActivityLead,
        now: Date,
        margin: TimeInterval = margin
    ) -> [LiveActivityPlan] {
        guard let leadSeconds = lead.seconds else {
            return fireDates.enumerated().map { index, fireDate in
                index == 0 ? .countdownNow(preAlert: fireDate.timeIntervalSince(now)) : .alertOnly
            }
        }
        return fireDates.enumerated().map { index, fireDate in
            let effective = index == 0
                ? leadSeconds
                : min(leadSeconds, fireDate.timeIntervalSince(fireDates[index - 1]))
            guard effective >= 1 else { return .alertOnly }
            let remaining = fireDate.timeIntervalSince(now)
            if remaining <= effective + margin {
                return index == 0 ? .countdownNow(preAlert: remaining) : .alertOnly
            }
            return .fixedWindow(start: fireDate.addingTimeInterval(-effective), preAlert: effective)
        }
    }

    /// Whether an alarm AlarmKit already holds does what `plan` asks, so it can be left alone.
    /// A window that has started, or is about to, is as good as a countdown to the same ring.
    static func existingSatisfies(
        plan: LiveActivityPlan,
        fireDate: Date,
        existingFixedDate: Date?,
        existingPreAlert: TimeInterval?,
        storedTarget: Date?,
        now: Date = Date()
    ) -> Bool {
        let close = { (a: Date?, b: Date) in a.map { abs($0.timeIntervalSince(b)) <= dateTolerance } ?? false }
        let hasCountdown = existingFixedDate == nil || (existingPreAlert ?? 0) > alertOnlyPreAlert + dateTolerance
        switch plan {
        case .alertOnly:
            return storedTarget == nil && !hasCountdown && close(existingFixedDate, fireDate)
        case .countdownNow:
            let started = existingFixedDate.map { $0 <= now.addingTimeInterval(margin) } ?? true
            return hasCountdown && started && close(storedTarget, fireDate)
        case .fixedWindow(let start, let preAlert):
            guard let existingPreAlert, close(existingFixedDate, start) else { return false }
            return abs(existingPreAlert - preAlert) <= dateTolerance && close(storedTarget, fireDate)
        }
    }

    /// The ring time of an alarm: the stored target when one was saved (every Live Activity
    /// alarm). Without one, a window's fixed date plus its pre-alert: the fixed date is when
    /// the card appears, and reading it as the ring had cleanup cancel the alarm early.
    static func resolvedFireDate(fixedDate: Date?, preAlert: TimeInterval?, storedTarget: Date?) -> Date? {
        if let storedTarget { return storedTarget }
        guard let fixedDate else { return nil }
        let preAlert = preAlert ?? 0
        return fixedDate.addingTimeInterval(preAlert > alertOnlyPreAlert + dateTolerance ? preAlert : 0)
    }
}
