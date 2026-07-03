//
//  ScreenshotTests.swift
//  CalarmUITests
//

import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let simulator = ProcessInfo().environment["SIMULATOR_DEVICE_NAME"] ?? ""
        if simulator.isEmpty {
            throw XCTSkip("Screenshots require an iOS Simulator.")
        }
    }

    func test01Schedule() throws {
        try capture(scene: "schedule", name: "01_Schedule")
    }

    func test02EventAlarms() throws {
        try capture(scene: "event_detail", name: "02_Event_Alarms")
    }

    func test03Settings() throws {
        try capture(scene: "settings", name: "03_Settings")
    }

    func test04AddAlarmPicker() throws {
        try capture(scene: "add_alarm", name: "04_Add_Alarm")
    }

    private func capture(scene: String, name: String) throws {
        let app = XCUIApplication()
        setupSnapshot(app)

        app.launchArguments += [
            ScreenshotMode.launchArgument,
            "\(ScreenshotMode.sceneArgumentPrefix)\(scene)"
        ]
        app.launch()

        let readyID: String
        switch scene {
        case "schedule":
            readyID = "schedule.list"
        case "event_detail", "add_alarm":
            readyID = "event.detail"
        case "settings":
            readyID = "settings.sheet"
        default:
            readyID = "schedule.screen"
        }

        let ready = app.descendants(matching: .any).matching(identifier: readyID).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 15), "Expected \(readyID) for scene \(scene)")
        snapshot(name, timeWaitingForIdle: 0)
    }
}

/// Mirror of app launch-argument constants for UI tests.
private enum ScreenshotMode {
    static let launchArgument = "SCREENSHOT_MODE"
    static let sceneArgumentPrefix = "SCREENSHOT_SCENE="
}
