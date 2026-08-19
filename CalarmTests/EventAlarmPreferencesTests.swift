import XCTest
@testable import Calarm

final class EventAlarmPreferencesTests: XCTestCase {
    @MainActor
    func testPauseAndResumePreservesMultipleOffsets() {
        let prefs = EventAlarmPreferences()
        let occurrenceID = "test.event_1234567890"

        prefs.setAlarmOffsets([.tenMinutes, .thirtyMinutes], for: occurrenceID)
        XCTAssertEqual(prefs.alarmOffsets(for: occurrenceID), [.tenMinutes, .thirtyMinutes])

        prefs.pauseAlarms(for: occurrenceID)
        XCTAssertTrue(prefs.alarmOffsets(for: occurrenceID).isEmpty)
        XCTAssertTrue(prefs.hasPausedAlarms(for: occurrenceID))

        prefs.resumeAlarms(for: occurrenceID, defaultOffset: .noAlarm)
        XCTAssertEqual(prefs.alarmOffsets(for: occurrenceID), [.tenMinutes, .thirtyMinutes])
        XCTAssertFalse(prefs.hasPausedAlarms(for: occurrenceID))
    }

    @MainActor
    func testResumeWithoutPausedUsesDefaultOffset() {
        let prefs = EventAlarmPreferences()
        let occurrenceID = "test.event_999"

        prefs.setAlarmOffsets([], for: occurrenceID)
        prefs.resumeAlarms(for: occurrenceID, defaultOffset: .fiveMinutes)
        XCTAssertEqual(prefs.alarmOffsets(for: occurrenceID), [.fiveMinutes])
    }

    /// Empty `ekEvents` means no matching window events; bare legacy keys must stay.
    /// (EKEvent matching/copy path needs EventKit fixtures; not covered here.)
    @MainActor
    func testMigrateLegacyKeysPreservesBareKeyWhenNoMatchingEvents() {
        let legacyKey = "legacy-series-id-only"
        XCTAssertTrue(EventOccurrenceID.isLegacyBareIdentifier(legacyKey))

        let prefs = EventAlarmPreferences()
        prefs.setAlarmOffsets([.tenMinutes], for: legacyKey)
        defer { prefs.removeOverride(for: legacyKey) }

        prefs.migrateLegacyKeys(for: [])

        let stored = CalarmPersistence.decode(
            [String: EventOverride].self,
            forKey: CalarmPersistence.Key.eventOverrides
        )
        XCTAssertEqual(stored?[legacyKey]?.alarmOffsets, [AlarmOffsetOption.tenMinutes.rawValue])
    }
}
