//
//  MorningSyncScheduler.swift
//  Calarm
//

import BackgroundTasks
import Foundation

enum MorningSyncScheduler {
    static let morningTaskIdentifier = "com.calarmapp.calarm.morning-sync"
    static let hourlyTaskIdentifier = "com.calarmapp.calarm.hourly-sync"

    static func register(reloadHandler: @escaping () async -> Void) {
        register(taskIdentifier: morningTaskIdentifier, reloadHandler: reloadHandler)
        register(taskIdentifier: hourlyTaskIdentifier, reloadHandler: reloadHandler)
    }

    static func scheduleNext() {
        scheduleMorningRefresh()
        scheduleHourlyRefresh()
    }

    private static func register(taskIdentifier: String, reloadHandler: @escaping () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }
            Task {
                await reloadHandler()
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
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func scheduleHourlyRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: hourlyTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
