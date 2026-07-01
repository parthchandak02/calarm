//
//  CalarmEvent.swift
//  Calarm
//
//

import Foundation

// MARK: - Calendar Event with Alarm Info

struct CalarmEvent: Identifiable, Codable {
    let id: String // Event identifier
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let alarmMinutes: Int // Extracted from alarm text (e.g., 15 from "alarm15")
    let calendarTitle: String
    let originalEventId: String // For tracking the source event
    
    var alarmDate: Date {
        startDate.addingTimeInterval(-TimeInterval(alarmMinutes * 60))
    }
    
    var durationString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        
        // If alarm is today, show just time
        if Calendar.current.isDate(alarmDate, inSameDayAs: Date()) {
            return formatter.string(from: alarmDate)
        } else {
            // If alarm is future date, show date + time
            formatter.dateStyle = .short
            return formatter.string(from: alarmDate)
        }
    }
}