import XCTest
@testable import Calarm

final class SettingsSummaryTests: XCTestCase {
    private func input(
        alarmsDenied: Bool = false,
        hasEventSource: Bool = true,
        googleSyncError: String? = nil,
        failures: Int = 0,
        late: Int? = nil
    ) -> StatusVerdict.Input {
        StatusVerdict.Input(
            alarmsDenied: alarmsDenied,
            hasEventSource: hasEventSource,
            googleSyncError: googleSyncError,
            scheduleFailureCount: failures,
            firstScheduleFailure: failures > 0 ? "Standup: busy" : nil,
            timingLateSeconds: late
        )
    }

    func testLeadTiles() {
        XCTAssertEqual(SettingsSummary.leadTile(.always), "ALL")
        XCTAssertEqual(SettingsSummary.leadTile(.ten), "10")
        XCTAssertEqual(SettingsSummary.leadTile(.two), "2")
    }

    func testEarlyTestAlarmIsAProblem() {
        var early = input()
        early.timingEarlySeconds = 8
        early.timingExpectedSeconds = 16
        let problem = StatusVerdict.problems(for: early).first
        XCTAssertEqual(problem?.title, "Test alarm rang early")
        XCTAssertEqual(problem?.detail, "Rang at 8s instead of 16s · set Island to ALL")
    }

    func testAlarmsLine() {
        XCTAssertEqual(SettingsSummary.alarmsLine(offset: .tenMinutes, snooze: .fiveMinutes, vibrates: false), "−10m · 5m · ring")
        XCTAssertEqual(SettingsSummary.alarmsLine(offset: .noAlarm, snooze: .oneMinute, vibrates: true), "off · 1m · vibrate")
    }

    func testAlarmsSentenceMentionsFallbackOnlyWhenVibrating() {
        let ringing = SettingsSummary.alarmsSentence(offset: .tenMinutes, snooze: .fiveMinutes, vibrates: false)
        XCTAssertEqual(ringing, "New events ring 10 minutes before. Snooze waits 5 minutes.")
        XCTAssertTrue(SettingsSummary.alarmsSentence(offset: .noAlarm, snooze: .fiveMinutes, vibrates: true)
            .hasSuffix("Alarms vibrate instead of ringing."))
    }

    func testCalendarsLine() {
        XCTAssertEqual(SettingsSummary.calendarsLine(enabled: 3, total: 5, googleConnected: true), "3 of 5 · Google")
        XCTAssertEqual(SettingsSummary.calendarsLine(enabled: 0, total: 0, googleConnected: false), "none")
    }

    func testHealthyStatusIsAllGood() {
        let problems = StatusVerdict.problems(for: input())
        XCTAssertTrue(problems.isEmpty)
        XCTAssertEqual(StatusVerdict.headline(for: problems), "ALL GOOD")
        XCTAssertEqual(StatusVerdict.subline(for: problems, hasUpcomingAlarm: true), "Alarms will ring.")
    }

    func testDeniedAlarmsBlockRinging() {
        let problems = StatusVerdict.problems(for: input(alarmsDenied: true))
        XCTAssertEqual(problems.map(\.fix), [.openSystemSettings])
        XCTAssertEqual(StatusVerdict.subline(for: problems, hasUpcomingAlarm: true), "Alarms will not ring until this is fixed.")
    }

    func testSyncFailureDoesNotBlockRinging() {
        let problems = StatusVerdict.problems(for: input(googleSyncError: "token expired", late: 16))
        XCTAssertEqual(problems.map(\.fix), [.retrySync, .runTestAlarm])
        XCTAssertEqual(StatusVerdict.headline(for: problems), "2 PROBLEMS")
        XCTAssertEqual(StatusVerdict.subline(for: problems, hasUpcomingAlarm: true), "Alarms will still ring.")
    }

    func testScheduleFailureTitleCountsAlarms() {
        XCTAssertEqual(StatusVerdict.problems(for: input(failures: 3)).first?.title, "3 alarms couldn’t be scheduled")
    }
}
