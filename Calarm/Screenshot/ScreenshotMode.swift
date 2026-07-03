//
//  ScreenshotMode.swift
//  Calarm
//

import Foundation

/// Demo / App Store screenshot mode — activated via launch argument `SCREENSHOT_MODE`.
/// Never ships real calendar data; uses `ScreenshotDemoData` only.
enum ScreenshotMode {
    static let launchArgument = "SCREENSHOT_MODE"
    static let sceneArgumentPrefix = "SCREENSHOT_SCENE="

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var scene: Scene {
        let args = ProcessInfo.processInfo.arguments
        guard let raw = args.first(where: { $0.hasPrefix(sceneArgumentPrefix) }) else {
            return .schedule
        }
        let value = String(raw.dropFirst(sceneArgumentPrefix.count))
        return Scene(rawValue: value) ?? .schedule
    }

    enum Scene: String {
        case schedule
        case eventDetail = "event_detail"
        case settings
        case addAlarm = "add_alarm"
    }
}
