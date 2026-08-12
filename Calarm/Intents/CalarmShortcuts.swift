//
//  CalarmShortcuts.swift
//  Calarm
//

import AppIntents

struct OpenScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Today's Schedule"
    static var description = IntentDescription("Open CALarm to your upcoming calendar events.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct CalarmShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenScheduleIntent(),
            phrases: [
                "Show my schedule in \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Today's Schedule",
            systemImageName: "calendar"
        )
    }
}
