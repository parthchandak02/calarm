import Foundation
import Testing

struct AlarmSchedulingHelpersTests {

    @Test func isStaleAlarmAfterGrace() {
        let fire = Date(timeIntervalSince1970: 1_000_000)
        let now = fire.addingTimeInterval(AlarmSchedulingHelpers.countdownCleanupGrace + 1)
        #expect(AlarmSchedulingHelpers.isStaleAlarm(fireDate: fire, now: now))
    }

    @Test func isNotStaleBeforeGrace() {
        let fire = Date(timeIntervalSince1970: 1_000_000)
        let now = fire.addingTimeInterval(AlarmSchedulingHelpers.countdownCleanupGrace - 1)
        #expect(!AlarmSchedulingHelpers.isStaleAlarm(fireDate: fire, now: now))
    }
}
