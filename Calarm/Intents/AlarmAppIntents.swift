//
//  AlarmAppIntents.swift
//  Calarm
//

import AlarmKit
import AppIntents
import Foundation

// MARK: - Shared helpers

private enum AlarmIntentSupport {
    static func uuid(from alarmID: String) -> UUID? {
        UUID(uuidString: alarmID)
    }
}

// MARK: - Open App Intent

public struct OpenAlarmApp: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Open Calarm"
    public static var description = IntentDescription("Opens Calarm")
    public static var openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    public init(alarmID: String) {
        self.alarmID = alarmID
    }

    public init() {
        alarmID = ""
    }

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - Snooze Alarm Intent

public struct SnoozeAlarmIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Snooze Alarm"
    public static var description = IntentDescription("Snoozes the alarm for the configured duration")
    public static var openAppWhenRun = false

    @Parameter(title: "Alarm ID")
    public var alarmID: String

    public init(alarmID: String) {
        self.alarmID = alarmID
    }

    public init() {
        alarmID = ""
    }

    public func perform() async throws -> some IntentResult {
        // AlarmKit handles .countdown secondary behavior; intent satisfies configuration contract.
        guard let id = AlarmIntentSupport.uuid(from: alarmID) else { return .result() }
        try? AlarmManager.shared.countdown(id: id)
        return .result()
    }
}

// MARK: - Stop Alarm Intent

public struct StopAlarmIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Dismiss Alarm"
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

    public func perform() async throws -> some IntentResult {
        guard let id = AlarmIntentSupport.uuid(from: alarmID) else { return .result() }
        try? AlarmManager.shared.stop(id: id)
        return .result()
    }
}

// MARK: - Pause Alarm Intent

public struct PauseAlarmIntent: LiveActivityIntent {
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

    public func perform() async throws -> some IntentResult {
        guard let id = AlarmIntentSupport.uuid(from: alarmID) else { return .result() }
        try? AlarmManager.shared.pause(id: id)
        return .result()
    }
}

// MARK: - Resume Alarm Intent

public struct ResumeAlarmIntent: LiveActivityIntent {
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

    public func perform() async throws -> some IntentResult {
        guard let id = AlarmIntentSupport.uuid(from: alarmID) else { return .result() }
        try? AlarmManager.shared.resume(id: id)
        return .result()
    }
}
