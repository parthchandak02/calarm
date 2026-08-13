//
//  CalendarSource.swift
//  Calarm
//

import Foundation

/// Where a schedule row originated.
enum CalendarSource: String, Codable, Sendable, Equatable {
    case eventKit
    case google
}
