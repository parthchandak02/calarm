//
//  AlarmModel.swift
//  Calarm
//
//

import ActivityKit
import AlarmKit
import Combine
import EventKit
import Foundation
import SwiftUI
import os.log

// MARK: - Alarm Data Model (Using AlarmKit schedule-based alarms for future dates)

struct AlarmData: Identifiable, Codable {
    let id: UUID
    var title: String
    var isEnabled: Bool
    var alarmDate: Date // Specific date and time for the alarm
    var soundName: String
    var snoozeEnabled: Bool
    var preAlertMinutes: Int // Minutes before final alert (like 10 min warning)
    var postAlertMinutes: Int // Minutes to keep alert active after countdown ends
    var isFromCalendar: Bool = false // Flag to identify calendar-imported alarms
    var calendarEventId: String? = nil // Original calendar event ID for tracking
    var calendarTitle: String? = nil // Name of the source calendar

    init(id: UUID = UUID(),
         title: String = "Alarm",
         isEnabled: Bool = true,
         alarmDate: Date = Date().addingTimeInterval(3600), // Default 1 hour from now
         soundName: String = "Chime",
         snoozeEnabled: Bool = true,
         preAlertMinutes: Int = 10, // 10 min warning before alarm
         postAlertMinutes: Int = 5, // 5 min alert duration after alarm fires
         isFromCalendar: Bool = false,
         calendarEventId: String? = nil,
         calendarTitle: String? = nil) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.alarmDate = alarmDate
        self.soundName = soundName
        self.snoozeEnabled = snoozeEnabled
        self.preAlertMinutes = preAlertMinutes
        self.postAlertMinutes = postAlertMinutes
        self.isFromCalendar = isFromCalendar
        self.calendarEventId = calendarEventId
        self.calendarTitle = calendarTitle
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

    // Check if alarm is in the past
    var isPastDue: Bool {
        alarmDate < Date()
    }
    
    // Convenience initializer for calendar events
    init(from calendarEvent: CalarmEvent) {
        self.id = UUID(uuidString: calendarEvent.id) ?? UUID()
        self.title = calendarEvent.title
        self.isEnabled = true
        self.alarmDate = calendarEvent.alarmDate
        self.soundName = "Chime"
        self.snoozeEnabled = true
        self.preAlertMinutes = 2 // Short pre-alert for calendar events
        self.postAlertMinutes = 5
        self.isFromCalendar = true
        self.calendarEventId = calendarEvent.originalEventId
        self.calendarTitle = calendarEvent.calendarTitle
    }
}

// MARK: - Weekday Enum

enum Weekday: Int, CaseIterable, Codable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var name: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

// MARK: - AlarmKit Metadata (iOS 26 Beta Compatible)

// iOS 26 AlarmKit requires specific concurrency patterns for Swift 6

// AlarmMetadata implementation following official Apple documentation pattern
// Using nonisolated to avoid actor isolation issues with Sendable conformance
nonisolated struct EmptyAlarmMetadata: AlarmMetadata, Sendable, Codable {
    // Following exact pattern from Apple's CookingData example
    // Simple title property to satisfy AlarmMetadata requirements
    let title: String

    nonisolated init(title: String = "Alarm") {
        self.title = title
    }
}

// Use empty metadata to avoid iOS 26 beta protocol conformance issues
typealias AlarmAppMetadata = EmptyAlarmMetadata

// MARK: - AlarmKit Live Activities (iOS 26)

// AlarmKit handles Live Activities automatically - no manual ActivityAttributes needed
// Manual ActivityKit integration commented out to prevent conflicts with AlarmKit system Live Activities

/*
 // Legacy manual ActivityKit code - replaced by AlarmKit automatic Live Activities
 struct AlarmCountdownAttributes: ActivityAttributes {
     public typealias AlarmCountdownStatus = ContentState

     public struct ContentState: Codable, Hashable {
         var alarmTitle: String
         var remainingTime: ClosedRange<Date>
         var isPaused: Bool
     }

     var alarmId: String
     var originalDuration: Int // Duration in minutes
 }
 */

// MARK: - Alarm Store Manager

@MainActor
class AlarmStore: ObservableObject, CalarmSchedulingDelegate {
    @Published var alarms: [AlarmData] = []
    @Published var calendarService = CalendarService()

    private let userDefaults = UserDefaults.standard
    private let alarmsKey = "SavedAlarms"
    private var cancellables = Set<AnyCancellable>()
    
    // Track alarms that were scheduled in background and need Live Activity initialization
    private let pendingLiveActivitiesKey = "PendingLiveActivities"
    private var pendingLiveActivities: Set<UUID> {
        get {
            let data = userDefaults.data(forKey: pendingLiveActivitiesKey) ?? Data()
            return (try? JSONDecoder().decode(Set<UUID>.self, from: data)) ?? Set<UUID>()
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            userDefaults.set(data, forKey: pendingLiveActivitiesKey)
        }
    }

    init() {
        loadAlarms()
        setupCalendarIntegration()
        
        // Set self as the calendar service delegate
        calendarService.alarmSchedulingDelegate = self
        
        // Process any alarms that were scheduled in background and need Live Activity initialization
        Task {
            await processPendingLiveActivities()
        }
    }

    // MARK: - CRUD Operations

        func addAlarm(_ alarm: AlarmData) {
        alarms.append(alarm)
        saveAlarms()
        
        if alarm.isEnabled {
            Task {
                await scheduleAlarmWithAlarmKit(alarm)
            }
        }
    }

    func updateAlarm(_ alarm: AlarmData) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            saveAlarms()

            Task {
                // Use hierarchical scheduling to maintain proper Live Activity priority
                await rescheduleAllAlarmsHierarchically()
            }
        }
    }

    func deleteAlarm(_ alarm: AlarmData) {
        alarms.removeAll { $0.id == alarm.id }
        saveAlarms()

        Task {
            // Use hierarchical scheduling to update priorities after deletion
            await rescheduleAllAlarmsHierarchically()
        }
    }

    func toggleAlarm(_ alarm: AlarmData) {
        var updatedAlarm = alarm
        let newState = !updatedAlarm.isEnabled
        updatedAlarm.isEnabled = newState
        
        // Log the toggle action
        os_log("🔄 ALARM TOGGLE: '%{public}@' from %{public}@ to %{public}@", log: OSLog.default, type: .default, alarm.title, alarm.isEnabled ? "ON" : "OFF", newState ? "ON" : "OFF")
        print("🔄 ALARM TOGGLE: '\(alarm.title)' from \(alarm.isEnabled ? "ON" : "OFF") to \(newState ? "ON" : "OFF")")
        NSLog("🔄 ALARM TOGGLE: '%@' from %@ to %@", alarm.title, alarm.isEnabled ? "ON" : "OFF", newState ? "ON" : "OFF")
        
        updateAlarm(updatedAlarm) // This will trigger hierarchical rescheduling
    }

    // MARK: - Persistence

    private func saveAlarms() {
        if let encoded = try? JSONEncoder().encode(alarms) {
            userDefaults.set(encoded, forKey: alarmsKey)
        }
    }

    private func loadAlarms() {
        if let data = userDefaults.data(forKey: alarmsKey),
           let decoded = try? JSONDecoder().decode([AlarmData].self, from: data) {
            alarms = decoded
        }
    }



    // MARK: - AlarmKit Integration (Following docs pattern exactly)
    
    // MARK: - Hierarchical Alarm Scheduling
    
    /// Reschedule all alarms with proper hierarchical Live Activity priority
    /// Only the earliest upcoming alarm gets Live Activity countdown display
    private func rescheduleAllAlarmsHierarchically() async {
        // Multiple logging methods to ensure visibility in Xcode console
        os_log("🔄 HIERARCHICAL SCHEDULING: Starting reschedule of all alarms", log: OSLog.default, type: .default)
        print("🔄 HIERARCHICAL SCHEDULING: Starting reschedule of all alarms")
        NSLog("🔄 HIERARCHICAL SCHEDULING: Starting reschedule of all alarms")
        
        // Log current alarm state
        os_log("📋 CURRENT STATE: Total alarms: %d, Enabled: %d", log: OSLog.default, type: .default, alarms.count, alarms.filter(\.isEnabled).count)
        print("📋 CURRENT STATE: Total alarms: \(alarms.count), Enabled: \(alarms.filter(\.isEnabled).count)")
        NSLog("📋 CURRENT STATE: Total alarms: %d, Enabled: %d", alarms.count, alarms.filter(\.isEnabled).count)
        
        // Cancel all existing AlarmKit alarms first
        for alarm in alarms where alarm.isEnabled {
            os_log("❌ CANCEL: Canceling existing alarm: %{public}@ at %{public}@", log: OSLog.default, type: .default, alarm.title, alarm.alarmDate.description)
            print("❌ CANCEL: Canceling existing alarm: '\(alarm.title)' at \(alarm.alarmDate)")
            NSLog("❌ CANCEL: Canceling existing alarm: '%@' at %@", alarm.title, alarm.alarmDate.description)
            cancelAlarmWithAlarmKit(alarm.id)
        }
        
        // Get earliest upcoming alarm (this gets Live Activity priority)
        let sortedAlarms = enabledAlarmsSortedByTime
        guard !sortedAlarms.isEmpty else {
            os_log("⚠️ WARNING: No enabled alarms to schedule", log: OSLog.default, type: .default)
            print("⚠️ WARNING: No enabled alarms to schedule")
            NSLog("⚠️ WARNING: No enabled alarms to schedule")
            return
        }
        
        os_log("📊 ALARM HIERARCHY: Scheduling %d alarms in priority order:", log: OSLog.default, type: .default, sortedAlarms.count)
        print("📊 ALARM HIERARCHY: Scheduling \(sortedAlarms.count) alarms in priority order:")
        NSLog("📊 ALARM HIERARCHY: Scheduling %d alarms in priority order:", sortedAlarms.count)
        
        // Log the hierarchy order
        for (index, alarm) in sortedAlarms.enumerated() {
            let priorityText = index == 0 ? "🥇 PRIORITY (Live Activity)" : "🥈 Background Only"
            os_log("  %d. %{public}@ at %{public}@ - %{public}@", log: OSLog.default, type: .default, index + 1, alarm.title, alarm.alarmDate.description, priorityText)
            print("  \(index + 1). '\(alarm.title)' at \(alarm.alarmDate) - \(priorityText)")
            NSLog("  %d. '%@' at %@ - %@", index + 1, alarm.title, alarm.alarmDate.description, priorityText)
        }
        
        for (index, alarm) in sortedAlarms.enumerated() {
            let isEarliestAlarm = (index == 0)
            
            os_log("⏰ SCHEDULING: Processing alarm %d/%d: '%{public}@' - Live Activity: %{public}@", log: OSLog.default, type: .default, index + 1, sortedAlarms.count, alarm.title, isEarliestAlarm ? "YES" : "NO")
            print("⏰ SCHEDULING: Processing alarm \(index + 1)/\(sortedAlarms.count): '\(alarm.title)' - Live Activity: \(isEarliestAlarm ? "YES" : "NO")")
            NSLog("⏰ SCHEDULING: Processing alarm %d/%d: '%@' - Live Activity: %@", index + 1, sortedAlarms.count, alarm.title, isEarliestAlarm ? "YES" : "NO")
            
            await scheduleIndividualAlarmWithAlarmKit(
                alarm, 
                withLiveActivityPriority: isEarliestAlarm,
                isBackgroundScheduling: false
            )
        }
        
        os_log("✅ HIERARCHICAL COMPLETE: All alarms scheduled with proper priority", log: OSLog.default, type: .default)
        print("✅ HIERARCHICAL COMPLETE: All alarms scheduled with proper priority")
        NSLog("✅ HIERARCHICAL COMPLETE: All alarms scheduled with proper priority")
    }
    
    private func scheduleAlarmWithAlarmKit(_ alarm: AlarmData) async {
        // Always use hierarchical scheduling to maintain proper priority
        await rescheduleAllAlarmsHierarchically()
    }

    /// Schedule individual alarm with optional Live Activity priority
    private func scheduleIndividualAlarmWithAlarmKit(
        _ alarm: AlarmData, 
        withLiveActivityPriority hasLiveActivityPriority: Bool,
        isBackgroundScheduling: Bool
    ) async {
        // Log the scheduling attempt
        os_log("🎯 INDIVIDUAL SCHEDULE: Starting to schedule '%{public}@'", log: OSLog.default, type: .default, alarm.title)
        os_log("   📍 Live Activity Priority: %{public}@", log: OSLog.default, type: .default, hasLiveActivityPriority ? "YES" : "NO")
        os_log("   🕰️ Alarm Date: %{public}@", log: OSLog.default, type: .default, alarm.alarmDate.description)
        print("🎯 INDIVIDUAL SCHEDULE: Starting to schedule '\(alarm.title)'")
        print("   📍 Live Activity Priority: \(hasLiveActivityPriority ? "YES" : "NO")")
        print("   🕰️ Alarm Date: \(alarm.alarmDate)")
        NSLog("🎯 INDIVIDUAL SCHEDULE: Starting to schedule '%@' with Live Activity: %@", alarm.title, hasLiveActivityPriority ? "YES" : "NO")
        
        do {
            // For iOS 26 beta, use metadata type parameter
            typealias AlarmConfiguration = AlarmManager.AlarmConfiguration<AlarmAppMetadata>

            // Create buttons exactly as shown in docs
            let stopButton = AlarmButton(
                text: "Dismiss",
                textColor: .white,
                systemImageName: "stop.circle"
            )

            // Create snooze button for schedule-based alarms
            let snoozeButton = alarm.snoozeEnabled ? AlarmButton(
                text: "Snooze",
                textColor: .white,
                systemImageName: "clock.badge.questionmark"
            ) : nil

            // Create alert presentation for schedule-based alarms (following official docs)
            let alertPresentation = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: alarm.title),
                stopButton: stopButton,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: alarm.snoozeEnabled ? .countdown : nil
            )

            // Create countdown presentation (required for countdown-based alarms)
            let pauseButton = AlarmButton(
                text: "Pause",
                textColor: .red,
                systemImageName: "pause"
            )

            let countdownPresentation = AlarmPresentation.Countdown(
                title: LocalizedStringResource(stringLiteral: alarm.title),
                pauseButton: pauseButton
            )

            // Create paused presentation
            let resumeButton = AlarmButton(
                text: "Resume",
                textColor: .red,
                systemImageName: "play"
            )

            let pausedPresentation = AlarmPresentation.Paused(
                title: LocalizedStringResource(stringLiteral: "Paused"),
                resumeButton: resumeButton
            )

            // Create alarm attributes - conditionally include countdown/paused presentations based on priority
            let metadata = AlarmAppMetadata(title: alarm.title) // Pass actual alarm title
            
            let presentation: AlarmPresentation
            if hasLiveActivityPriority {
                // PRIMARY alarm gets full Live Activity countdown experience
                presentation = AlarmPresentation(
                    alert: alertPresentation,
                    countdown: countdownPresentation,
                    paused: pausedPresentation
                )
                print("  🎯 PRIMARY: Full Live Activity presentations enabled")
            } else {
                // SECONDARY alarms only get alert presentation (no Live Activity)
                presentation = AlarmPresentation(
                    alert: alertPresentation
                    // No countdown/paused = No Live Activity
                )
                print("  📱 SECONDARY: Alert-only (no Live Activity)")
            }
            
            let attributes = AlarmAttributes<AlarmAppMetadata>(
                presentation: presentation,
                metadata: metadata,
                tintColor: Color.red
            )

            // Create sound configuration (following official Apple docs)
            // Note: Sound will be configured in AlarmConfiguration.init

            // Calculate countdown duration from current time to alarm time (proper AlarmKit pattern)
            let countdownSeconds = max(30, alarm.alarmDate.timeIntervalSinceNow) // Ensure at least 30 seconds

            // Create countdown duration with preAlert and postAlert (following official Apple AlarmKit docs)
            let countdownDuration = Alarm.CountdownDuration(
                preAlert: countdownSeconds,
                postAlert: TimeInterval(alarm.postAlertMinutes * 60) // Convert minutes to seconds
            )

            // Create alarm configuration with countdown duration (following official Apple AlarmKit docs)
            let alarmConfiguration = AlarmConfiguration(
                countdownDuration: countdownDuration,
                attributes: attributes
            )

            _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: alarmConfiguration)

            print("✅ Scheduled AlarmKit alarm: '\(alarm.title)' - \(alarm.durationString)")
            print("🎯 Alarm will fire in: \(countdownSeconds) seconds at \(alarm.alarmDate.formatted())")
            print("  📺 Live Activity: \(hasLiveActivityPriority ? "ENABLED" : "DISABLED")")
            
            // If scheduled in background, mark for Live Activity initialization when app comes to foreground
            if isBackgroundScheduling && hasLiveActivityPriority {
                var pending = pendingLiveActivities
                pending.insert(alarm.id)
                pendingLiveActivities = pending
                print("📱 Marked alarm for Live Activity initialization when app comes to foreground")
            }

        } catch {
            print("❌ Failed to schedule AlarmKit alarm: \(error)")
        }
    }
    
    // Legacy method that redirects to hierarchical scheduling
    private func scheduleAlarmWithAlarmKit(_ alarm: AlarmData, isBackgroundScheduling: Bool) async {
        if isBackgroundScheduling {
            // In background, still promote the earliest upcoming alarm so the system can
            // render countdown on Lock Screen/Dynamic Island using system presentation
            // (and Live Activity when allowed).
            let isEarliestUpcoming = (nextUpcomingAlarm?.id == alarm.id)
            await scheduleIndividualAlarmWithAlarmKit(
                alarm,
                withLiveActivityPriority: isEarliestUpcoming,
                isBackgroundScheduling: true
            )
        } else {
            // In foreground, keep full hierarchical reschedule
            await rescheduleAllAlarmsHierarchically()
        }
    }

    private func getSoundIcon(for soundName: String) -> String {
        switch soundName.lowercased() {
        case "bell": "bell"
        case "alarm": "alarm"
        case "horn": "horn.blast"
        case "chime": "bell.circle"
        default: "clock"
        }
    }

    private func cancelAlarmWithAlarmKit(_ alarmId: UUID) {
        Task {
            try? AlarmManager.shared.cancel(id: alarmId)
        }
    }

    // MARK: - Calendar Integration
    
    private func setupCalendarIntegration() {
        // Monitor calendar events and automatically sync with alarms
        calendarService.$calendarEvents
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] calendarEvents in
                Task {
                    await self?.syncCalarms(calendarEvents)
                }
            }
            .store(in: &cancellables)
    }
    
    func requestCalendarAccess() async {
        await calendarService.requestCalendarAccess()
    }
    
    private func syncCalarms(_ calendarEvents: [CalarmEvent]) async {
        // Remove outdated calendar alarms
        let existingCalarms = alarms.filter { $0.isFromCalendar }
        let calendarEventIds = Set(calendarEvents.map { $0.originalEventId })
        
        for existingAlarm in existingCalarms {
            if let eventId = existingAlarm.calendarEventId,
               !calendarEventIds.contains(eventId) {
                // Calendar event was deleted or modified, remove the alarm
                deleteAlarm(existingAlarm)
                print("🗑️ Removed outdated calendar alarm: \(existingAlarm.title)")
            }
        }
        
        // Add new calendar alarms or update existing ones
        for calendarEvent in calendarEvents {
            let eventId = calendarEvent.originalEventId
            
            // Check if we already have an alarm for this calendar event
            if let existingAlarm = alarms.first(where: { alarm in
                alarm.isFromCalendar && alarm.calendarEventId == eventId
            }) {
                // Update existing alarm with new calendar event data
                let baseAlarm = AlarmData(from: calendarEvent)
                let updatedAlarm = AlarmData(
                    id: existingAlarm.id, // Preserve the existing ID
                    title: baseAlarm.title,
                    isEnabled: existingAlarm.isEnabled, // Preserve enabled state
                    alarmDate: baseAlarm.alarmDate,
                    soundName: baseAlarm.soundName,
                    snoozeEnabled: baseAlarm.snoozeEnabled,
                    preAlertMinutes: baseAlarm.preAlertMinutes,
                    postAlertMinutes: baseAlarm.postAlertMinutes,
                    isFromCalendar: baseAlarm.isFromCalendar,
                    calendarEventId: baseAlarm.calendarEventId,
                    calendarTitle: baseAlarm.calendarTitle
                )
                
                // Check if the alarm time actually changed
                if existingAlarm.alarmDate != updatedAlarm.alarmDate ||
                   existingAlarm.title != updatedAlarm.title {
                    print("📅🔄 Updating calendar alarm: \(existingAlarm.title)")
                    print("  Old time: \(existingAlarm.alarmDate.formatted())")
                    print("  New time: \(updatedAlarm.alarmDate.formatted())")
                    
                    // Update the alarm (this will cancel and reschedule the individual alarm)
                    updateAlarm(updatedAlarm)
                }
            } else {
                // Create new alarm from calendar event
                let newAlarm = AlarmData(from: calendarEvent)
                addAlarm(newAlarm)
                print("📅➕ Added calendar alarm: \(newAlarm.title) - \(newAlarm.durationString)")
            }
        }
    }
    
    func refreshCalendarEvents() async {
        await calendarService.loadCalendarEvents()
    }
    
    // MARK: - Force Refresh for External Changes
    
    func forceRefreshCalendarData() async {
        print("🔄 Force refreshing calendar data to detect external changes...")
        
        // Save current state for comparison
        let previousCalarms = calendarAlarms
        let previousCount = previousCalarms.count
        
        // Force reload calendar events from system
        await calendarService.loadCalendarEvents()
        
        // Check if any calendar alarms have changed
        let newCalarms = calendarAlarms
        let newCount = newCalarms.count
        
        // Compare event details to detect changes
        var hasChanges = (previousCount != newCount)
        
        if !hasChanges {
            // Check if any individual alarm details changed (time, title, etc.)
            for newAlarm in newCalarms {
                if let previousAlarm = previousCalarms.first(where: { $0.calendarEventId == newAlarm.calendarEventId }) {
                    if previousAlarm.alarmDate != newAlarm.alarmDate ||
                       previousAlarm.title != newAlarm.title {
                        hasChanges = true
                        print("📅🔄 Detected change in calendar alarm: \(newAlarm.title)")
                        print("  Previous: \(previousAlarm.alarmDate.formatted())")
                        print("  New: \(newAlarm.alarmDate.formatted())")
                        break
                    }
                } else {
                    hasChanges = true
                    print("📅➕ Detected new calendar alarm: \(newAlarm.title)")
                    break
                }
            }
        }
        
        if hasChanges {
            print("✅ Calendar changes detected - refreshing alarms and Live Activities")
            
            // Process any pending Live Activities that might have been affected
            await processPendingLiveActivities()
        } else {
            print("📅 No calendar changes detected")
        }
    }
    
    // Get calendar vs manual alarms separately, sorted by earliest first
    var calendarAlarms: [AlarmData] {
        alarms.filter { $0.isFromCalendar }.sorted { $0.alarmDate < $1.alarmDate }
    }
    
    var manualAlarms: [AlarmData] {
        alarms.filter { !$0.isFromCalendar }.sorted { $0.alarmDate < $1.alarmDate }
    }
    
    // Get all enabled alarms sorted by time (earliest first)
    var enabledAlarmsSortedByTime: [AlarmData] {
        alarms.filter { $0.isEnabled }.sorted { $0.alarmDate < $1.alarmDate }
    }
    
    // Get the next upcoming alarm (earliest enabled alarm)
    var nextUpcomingAlarm: AlarmData? {
        enabledAlarmsSortedByTime.first
    }

    // MARK: - Live Activity Management (AlarmKit)

    // AlarmKit in iOS 26 handles Live Activities automatically when scheduling alarms
    // Manual ActivityKit integration removed to prevent conflicts with system Live Activities
    
    // MARK: - Live Activity Management
    
    func processPendingLiveActivitiesOnForeground() async {
        await processPendingLiveActivities()
    }
    
    private func processPendingLiveActivities() async {
        let pending = pendingLiveActivities
        guard !pending.isEmpty else {
            print("📱 No pending Live Activities to process")
            return
        }
        
        print("📱 Processing \(pending.count) pending Live Activities...")
        
        for alarmId in pending {
            if let alarm = alarms.first(where: { $0.id == alarmId && $0.isEnabled }) {
                print("📱 Re-scheduling alarm with Live Activity: \(alarm.title)")
                
                // Cancel and re-schedule to trigger Live Activity in foreground context
                cancelAlarmWithAlarmKit(alarm.id)
                await scheduleAlarmWithAlarmKit(alarm, isBackgroundScheduling: false)
                
                // Remove from pending list
                var pendingSet = pendingLiveActivities
                pendingSet.remove(alarmId)
                pendingLiveActivities = pendingSet
            }
        }
        
        print("✅ Finished processing pending Live Activities")
    }
    
    // MARK: - CalarmSchedulingDelegate
    
    func scheduleAlarmsForCalendarEvents(_ events: [CalarmEvent]) async {
        print("🔄⏰ Background scheduling alarms for \(events.count) calendar events...")
        
        var scheduled = 0
        var updated = 0
        var skipped = 0
        
        for calendarEvent in events {
            // Check if we already have an alarm for this calendar event
            if let existingAlarm = alarms.first(where: { $0.calendarEventId == calendarEvent.originalEventId }) {
                // Update existing alarm if needed
                let updatedAlarm = AlarmData(
                    id: existingAlarm.id,
                    title: calendarEvent.title,
                    isEnabled: existingAlarm.isEnabled,
                    alarmDate: calendarEvent.alarmDate,
                    soundName: existingAlarm.soundName,
                    snoozeEnabled: existingAlarm.snoozeEnabled,
                    preAlertMinutes: existingAlarm.preAlertMinutes,
                    postAlertMinutes: existingAlarm.postAlertMinutes,
                    isFromCalendar: true,
                    calendarEventId: calendarEvent.originalEventId,
                    calendarTitle: calendarEvent.calendarTitle
                )
                
                if existingAlarm.alarmDate != updatedAlarm.alarmDate || existingAlarm.title != updatedAlarm.title {
                    // Update alarm data without triggering normal UI-based scheduling
                    if let index = alarms.firstIndex(where: { $0.id == updatedAlarm.id }) {
                        alarms[index] = updatedAlarm
                        saveAlarms()
                        
                        // Cancel and reschedule with background mode
                        cancelAlarmWithAlarmKit(updatedAlarm.id)
                        if updatedAlarm.isEnabled {
                            await scheduleAlarmWithAlarmKit(updatedAlarm, isBackgroundScheduling: true)
                        }
                    }
                    updated += 1
                    print("📅🔄 Updated alarm: \(updatedAlarm.title)")
                } else {
                    skipped += 1
                }
            } else {
                // Create new alarm with background scheduling
                let newAlarm = AlarmData(from: calendarEvent)
                alarms.append(newAlarm)
                saveAlarms()
                
                if newAlarm.isEnabled {
                    await scheduleAlarmWithAlarmKit(newAlarm, isBackgroundScheduling: true)
                }
                scheduled += 1
                print("📅➕ Scheduled new alarm: \(newAlarm.title)")
            }
        }
        
        print("✅⏰ Background alarm scheduling complete: \(scheduled) new, \(updated) updated, \(skipped) unchanged")

        // Ensure only the earliest enabled alarm has Live Activity priority
        await enforceLiveActivityHierarchyInBackground()
    }
    
    func cancelAlarmsForDeletedEvents(_ deletedEventIds: [String]) async {
        print("🗑️⏰ Canceling alarms for \(deletedEventIds.count) deleted events...")
        
        var cancelled = 0
        for eventId in deletedEventIds {
            if let alarm = alarms.first(where: { $0.calendarEventId == eventId }) {
                deleteAlarm(alarm)
                cancelled += 1
                print("🗑️ Cancelled alarm for deleted event: \(alarm.title)")
            }
        }
        
        print("✅🗑️ Cancelled \(cancelled) alarms for deleted events")

        // Recompute hierarchy after deletions
        await enforceLiveActivityHierarchyInBackground()
    }

    // MARK: - Background Hierarchy Enforcement

    private func enforceLiveActivityHierarchyInBackground() async {
        // Determine current order
        let sorted = enabledAlarmsSortedByTime
        guard !sorted.isEmpty else { return }

        print("🧭 Enforcing background Live Activity hierarchy…")

        for (index, alarm) in sorted.enumerated() {
            let shouldHaveLiveActivity = (index == 0)
            // Cancel first to avoid duplicated schedules
            cancelAlarmWithAlarmKit(alarm.id)
            await scheduleIndividualAlarmWithAlarmKit(
                alarm,
                withLiveActivityPriority: shouldHaveLiveActivity,
                isBackgroundScheduling: true
            )
        }

        print("✅ Enforced background hierarchy (earliest has Live Activity)")
    }
}
