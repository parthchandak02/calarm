//
//  ScheduleEventSourcePolicy.swift
//  Calarm
//

import Foundation

enum ScheduleEventSourcePolicy {
    static func hasEventSource(eventKitFullAccess: Bool, googleConnected: Bool) -> Bool {
        eventKitFullAccess || googleConnected
    }
}
