//
//  MorningSyncScheduler.swift
//  Calarm
//

import BackgroundTasks
import Foundation

/// Background refresh for the two windows that matter: first thing in the morning, and
/// hourly thereafter.
///
/// **Registration must happen from `didFinishLaunchingWithOptions`, not from
/// `ScheduleStore.bootstrap()`.** `BGTaskScheduler.register` is documented as required
/// before launch returns, and `bootstrap()` runs from a SwiftUI `.task` — after. Getting
/// this wrong is silent: the handlers are never installed, so neither task ever runs, and
/// the app appears to simply never sync in the background.
///
/// Because registration now happens before the store exists, the store hands its reload
/// closure over separately via `setReloadHandler`. A task that somehow fires before that
/// happens reports failure rather than a successful empty sync, so iOS retries.
enum MorningSyncScheduler {
    static let morningTaskIdentifier = "com.calarmapp.calarm.morning-sync"
    static let hourlyTaskIdentifier = "com.calarmapp.calarm.hourly-sync"

    @MainActor private static var reloadHandler: (() async -> Void)?

    /// Call from `didFinishLaunchingWithOptions`. Installs both launch handlers.
    static func registerHandlers() {
        register(taskIdentifier: morningTaskIdentifier)
        register(taskIdentifier: hourlyTaskIdentifier)
    }

    /// Call once the store is ready. Separate from registration on purpose — see the
    /// type doc comment.
    @MainActor
    static func setReloadHandler(_ handler: @escaping () async -> Void) {
        reloadHandler = handler
    }

    static func scheduleNext() {
        scheduleMorningRefresh()
        scheduleHourlyRefresh()
    }

    private static func register(taskIdentifier: String) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }
            Task { @MainActor in
                guard let handler = reloadHandler else {
                    SchedulerLog.warning("bg task \(taskIdentifier) fired before the store was ready")
                    refreshTask.setTaskCompleted(success: false)
                    scheduleNext()
                    return
                }
                await handler()
                refreshTask.setTaskCompleted(success: true)
                scheduleNext()
            }
        }
    }

    private static func scheduleMorningRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: morningTaskIdentifier)
        request.earliestBeginDate = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 6, minute: 0),
            matchingPolicy: .nextTime
        )
        submit(request)
    }

    private static func scheduleHourlyRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: hourlyTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        submit(request)
    }

    /// Logged rather than swallowed. A `try?` here is how "background sync never ran"
    /// stays undiagnosable from the outside: submission can fail for a missing
    /// `BGTaskSchedulerPermittedIdentifiers` entry, or because the user switched
    /// Background App Refresh off, and both look identical to a task that simply was
    /// never granted time.
    private static func submit(_ request: BGAppRefreshTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            SchedulerLog.warning("bg submit failed for \(request.identifier): \(error.localizedDescription)")
        }
    }
}
