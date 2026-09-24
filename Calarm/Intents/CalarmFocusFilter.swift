//
//  CalarmFocusFilter.swift
//  Calarm
//

import AppIntents
import Foundation

/// Settings → Focus → a Focus → Focus Filters → CALarm. iOS calls `perform` with the chosen
/// value when the Focus turns on, and with the default when it turns off.
///
/// `LiveActivityIntent` is not decorative: a plain focus filter runs only while the app is
/// in the foreground, and this conformance lets it run in the app's process in the background.
struct CalarmFocusFilter: SetFocusFilterIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "CALarm alarm sound"
    static var description = IntentDescription("Vibrate instead of ringing while this Focus is on.")

    @Parameter(title: "Vibrate instead of ringing", default: false)
    var vibrate: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: vibrate ? "Vibrate instead of ringing" : "Ring as usual")
    }

    func perform() async throws -> some IntentResult {
        await ScheduleStore.applyFocusVibrate(vibrate)
        return .result()
    }
}
