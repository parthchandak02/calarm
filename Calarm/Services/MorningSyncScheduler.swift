//
//  MorningSyncScheduler.swift
//  Calarm
//

import BackgroundTasks
import Foundation

enum MorningSyncScheduler {
  static let taskIdentifier = "com.calarmapp.calarm.morning-sync"

  static func register(reloadHandler: @escaping () async -> Void) {
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

  static func scheduleNext() {
    let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = Calendar.current.nextDate(
      after: Date(),
      matching: DateComponents(hour: 6, minute: 0),
      matchingPolicy: .nextTime
    )
    try? BGTaskScheduler.shared.submit(request)
  }
}
