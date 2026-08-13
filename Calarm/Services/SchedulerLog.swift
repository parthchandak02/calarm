//
//  SchedulerLog.swift
//  Calarm
//

import Foundation
import os

enum SchedulerLog {
    private static let log = Logger(subsystem: "com.calarmapp.calarm", category: "scheduler")

    static func info(_ message: String) {
        log.info("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        log.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        log.error("\(message, privacy: .private)")
    }

    static func errorDetail(_ message: String) {
        log.error("\(message, privacy: .private)")
    }
}

struct ScheduleFailure: Identifiable, Equatable {
    let id = UUID()
    let occurrenceID: String
    let eventTitle: String
    let offsetTitle: String
    let message: String
}
