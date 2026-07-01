//
//  AlarmAppIntents.swift
//  Calarm
//
//

import AlarmKit
import AppIntents
import Foundation

// MARK: - Open App Intent (Following AlarmKit docs)

public struct OpenAlarmApp: LiveActivityIntent {
    public func perform() async throws -> some IntentResult {
        .result()
    }

    public static var title: LocalizedStringResource = "Open Alarm App"
    public static var description = IntentDescription("Opens the Alarm app")
    public static var openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    public init(alarmID: String) {
        self.alarmID = alarmID
    }

    public init() {
        alarmID = ""
    }
}

// MARK: - Snooze Alarm Intent

public struct SnoozeAlarmIntent: LiveActivityIntent {
    public func perform() async throws -> some IntentResult {
        // Handle snooze logic here
        print("⏰ Snoozing alarm: \(alarmID)")
        return .result()
    }

    public static var title: LocalizedStringResource = "Snooze Alarm"
    public static var description = IntentDescription("Snoozes the alarm for 9 minutes")
    public static var openAppWhenRun = false

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    @Parameter(title: "Snooze Duration")
    public var snoozeDuration: Int

    public init(alarmID: String, snoozeDuration: Int = 540) { // 9 minutes default
        self.alarmID = alarmID
        self.snoozeDuration = snoozeDuration
    }

    public init() {
        alarmID = ""
        snoozeDuration = 540
    }
}

// MARK: - Stop Alarm Intent

public struct StopAlarmIntent: LiveActivityIntent {
    public func perform() async throws -> some IntentResult {
        // Handle stop logic here
        print("🛑 Stopping alarm: \(alarmID)")
        return .result()
    }

    public static var title: LocalizedStringResource = "Stop Alarm"
    public static var description = IntentDescription("Stops the active alarm")
    public static var openAppWhenRun = false

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    public init(alarmID: String) {
        self.alarmID = alarmID
    }

    public init() {
        alarmID = ""
    }
}

// MARK: - Pause Alarm Intent

public struct PauseAlarmIntent: LiveActivityIntent {
    public func perform() async throws -> some IntentResult {
        // Handle pause logic here
        print("⏸️ Pausing alarm: \(alarmID)")
        return .result()
    }

    public static var title: LocalizedStringResource = "Pause Alarm"
    public static var description = IntentDescription("Pauses the alarm countdown")
    public static var openAppWhenRun = false

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    public init(alarmID: String) {
        self.alarmID = alarmID
    }

    public init() {
        alarmID = ""
    }
}

// MARK: - Resume Alarm Intent

public struct ResumeAlarmIntent: LiveActivityIntent {
    public func perform() async throws -> some IntentResult {
        // Handle resume logic here
        print("▶️ Resuming alarm: \(alarmID)")
        return .result()
    }

    public static var title: LocalizedStringResource = "Resume Alarm"
    public static var description = IntentDescription("Resumes the paused alarm countdown")
    public static var openAppWhenRun = false

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    public init(alarmID: String) {
        self.alarmID = alarmID
    }

    public init() {
        alarmID = ""
    }
}
