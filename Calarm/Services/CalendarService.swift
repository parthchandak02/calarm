//
//  CalendarService.swift
//  Calarm
//
//

import EventKit
import Foundation
import Combine
import BackgroundTasks
import UIKit
import UserNotifications

// MARK: - Calendar Alarm Scheduling Delegate

protocol CalarmSchedulingDelegate: AnyObject {
    func scheduleAlarmsForCalendarEvents(_ events: [CalarmEvent]) async
    func cancelAlarmsForDeletedEvents(_ deletedEventIds: [String]) async
}

// MARK: - Calendar Service

@MainActor
class CalendarService: ObservableObject {
    @Published var calendarEvents: [CalarmEvent] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    
    private let eventStore = EKEventStore()
    private var cancellables = Set<AnyCancellable>()
    
    // Background task identifiers
    static let calendarRefreshTaskID = "pchandak.calarm.calendarRefresh"
    static let alarmSchedulingTaskID = "pchandak.calarm.alarmScheduling"
    static let liveActivityTriggerTaskID = "pchandak.calarm.liveActivityTrigger"
    
    // Delegate for alarm scheduling
    weak var alarmSchedulingDelegate: CalarmSchedulingDelegate?
    
    // Notification service for automatic triggering
    private let notificationService = CalendarNotificationService()
    
    // Regex pattern to match alarm text like "alarm2", "alarm15", etc.
    private let alarmPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "alarm(\\d+)", options: .caseInsensitive)
        } catch {
            fatalError("Invalid regex pattern: \(error)")
        }
    }()
    
    init() {
        setupBackgroundTasks()
        setupCalendarChangeMonitoring()
        checkAuthorizationStatus()
        // Load events initially if we already have authorization
        if authorizationStatus == .fullAccess {
            Task {
                await loadCalendarEvents()
            }
        }
    }
    
    deinit {
        // Cancel any pending reload task to prevent memory leaks
        reloadTask?.cancel()
        print("🗑️ CalendarService deinitalized, reload task cancelled")
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }
    
    func requestCalendarAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                authorizationStatus = granted ? .fullAccess : .denied
                if granted {
                    Task {
                        await loadCalendarEvents()
                    }
                }
            }
        } catch {
            print("❌ Failed to request calendar access: \(error)")
            await MainActor.run {
                authorizationStatus = .denied
            }
        }
    }
    
    // MARK: - Background Processing
    
    private func setupBackgroundTasks() {
        print("🔧 Setting up background task handlers...")
        
        // Register background refresh task handler
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.calendarRefreshTaskID,
            using: nil
        ) { [weak self] task in
            self?.handleCalendarRefreshTask(task as! BGAppRefreshTask)
        }
        
        // Register alarm scheduling task handler  
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.alarmSchedulingTaskID,
            using: nil
        ) { [weak self] task in
            self?.handleAlarmSchedulingTask(task as! BGProcessingTask)
        }
        
        print("✅ Background task handlers setup complete")
    }
    
    private func handleCalendarRefreshTask(_ task: BGAppRefreshTask) {
        print("🔄📅 Background calendar refresh task started")
        
        // Schedule the next background refresh
        scheduleBackgroundRefresh()
        
        task.expirationHandler = {
            print("⚠️📅 Background calendar refresh task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            await self.performBackgroundCalendarRefresh(task: task)
        }
    }
    
    private func handleAlarmSchedulingTask(_ task: BGProcessingTask) {
        print("🔄⏰ Background alarm scheduling task started")
        
        task.expirationHandler = {
            print("⚠️⏰ Background alarm scheduling task expired")
            task.setTaskCompleted(success: false)
        }
        
        Task {
            await self.performBackgroundAlarmScheduling(task: task)
        }
    }
    
    @MainActor
    private func performBackgroundCalendarRefresh(task: BGAppRefreshTask) async {
        print("📅🔄 Performing background calendar refresh...")
        
        guard authorizationStatus == .fullAccess else {
            print("❌ Calendar access not granted for background refresh")
            task.setTaskCompleted(success: false)
            return
        }
        
        let previousEvents = calendarEvents
        await loadCalendarEvents()
        
        // Check if events changed and need alarm scheduling
        let hasChanges = hasEventContentChanged(previous: previousEvents, new: calendarEvents)
        
        if hasChanges {
            print("📅🔔 Calendar changes detected in background, scheduling alarm processing...")
            scheduleAlarmProcessingTask()
        }
        
        print("✅📅 Background calendar refresh completed")
        task.setTaskCompleted(success: true)
    }
    
    @MainActor
    private func performBackgroundAlarmScheduling(task: BGProcessingTask) async {
        print("⏰🔄 Performing background alarm scheduling...")
        
        guard let delegate = alarmSchedulingDelegate else {
            print("❌ No alarm scheduling delegate available")
            task.setTaskCompleted(success: false)
            return
        }
        
        // Schedule alarms for all current calendar events
        await delegate.scheduleAlarmsForCalendarEvents(calendarEvents)
        
        print("✅⏰ Background alarm scheduling completed")
        task.setTaskCompleted(success: true)
    }
    
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.calendarRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅📅 Background calendar refresh scheduled")
        } catch {
            print("❌ Failed to schedule background calendar refresh: \(error)")
        }
    }
    
    func scheduleAlarmProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: Self.alarmSchedulingTaskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30) // 30 seconds from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅⏰ Background alarm processing task scheduled")
        } catch {
            print("❌ Failed to schedule background alarm processing: \(error)")
        }
    }
    
    // MARK: - Calendar Monitoring
    
    @MainActor
    private var reloadTask: Task<Void, Never>?
    
    private func setupCalendarChangeMonitoring() {
        // Monitor calendar changes using NotificationCenter
        print("🔧 Setting up calendar change monitoring...")
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(750), scheduler: DispatchQueue.main) // Optimal debounce timing based on research
            .sink { [weak self] notification in
                print("📅🔄 Calendar database changed! Notification: \(notification)")
                
                // Cancel any existing reload task to prevent race conditions
                self?.reloadTask?.cancel()
                
                // Start new reload task with proper cancellation handling
                self?.reloadTask = Task { @MainActor in
                    guard let self = self else { return }
                    
                    // Check if task was cancelled before proceeding
                    guard !Task.isCancelled else {
                        print("📅⚠️ Calendar reload task was cancelled")
                        return
                    }
                    
                    print("📅🔄 Starting calendar event reload...")
                    await self.loadCalendarEvents()
                    
                    // Verify task wasn't cancelled during execution
                    if !Task.isCancelled {
                        print("📅✅ Calendar event reload completed successfully")
                    }
                }
            }
            .store(in: &cancellables)
        
        print("✅ Calendar change monitoring setup complete")
    }
    
    // MARK: - Event Loading
    
    /// Manual refresh method that can be called from UI
    func refreshCalendarEvents() async {
        print("📅🔄 Manual calendar refresh requested")
        await loadCalendarEvents()
    }
    
    func loadCalendarEvents() async {
        guard authorizationStatus == .fullAccess else {
            print("❌ Calendar access not granted")
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        // Fetch events for the next 7 days
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate) ?? startDate
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        var calendarAlarmEvents: [CalarmEvent] = []
        
        print("📅 Checking \(events.count) events for alarm patterns...")
        
        for event in events {
            print("📅🔍 Event: '\(event.title ?? "Untitled")' at \(event.startDate)")
            
            if let alarmMinutes = extractAlarmMinutes(from: event) {
                let alarmDate = event.startDate.addingTimeInterval(-TimeInterval(alarmMinutes * 60))
                
                // Only include future alarms
                if alarmDate > Date() {
                    let calendarEvent = CalarmEvent(
                        id: UUID().uuidString, // Generate new ID for our alarm
                        title: event.title ?? "Untitled Event",
                        startDate: event.startDate,
                        endDate: event.endDate,
                        location: event.location,
                        notes: event.notes,
                        alarmMinutes: alarmMinutes,
                        calendarTitle: event.calendar.title,
                        originalEventId: event.eventIdentifier
                    )
                    calendarAlarmEvents.append(calendarEvent)
                    
                    print("📅✅ Added alarm: '\(event.title ?? "")' - \(alarmMinutes) min before (\(alarmDate))")
                } else {
                    print("📅⏰ Skipped past alarm: '\(event.title ?? "")' - alarm was at \(alarmDate)")
                }
            } else {
                print("📅⚪ No alarm pattern in: '\(event.title ?? "Untitled")'")
            }
        }
        
        await MainActor.run {
            let previousCount = self.calendarEvents.count
            let previousEventIds = Set(self.calendarEvents.map { $0.originalEventId ?? $0.id })
            let newEventIds = Set(calendarAlarmEvents.map { $0.originalEventId ?? $0.id })
            
            // Check for meaningful changes beyond just count
            let hasChanges = previousCount != calendarAlarmEvents.count || 
                           previousEventIds != newEventIds ||
                           self.hasEventContentChanged(previous: self.calendarEvents, new: calendarAlarmEvents)
            
            self.calendarEvents = calendarAlarmEvents
            self.isLoading = false
            
            print("📅📊 Calendar events updated: \(previousCount) → \(calendarAlarmEvents.count) alarm events")
            
            if hasChanges {
                print("📅🔔 Meaningful calendar changes detected, triggering alarm sync...")
                print("  - Count changed: \(previousCount != calendarAlarmEvents.count)")
                print("  - Event IDs changed: \(previousEventIds != newEventIds)")
                
                // Send automatic notification trigger for Live Activity initialization
                Task {
                    await self.notificationService.sendCalendarUpdateNotification(
                        eventCount: calendarAlarmEvents.count,
                        isBackgroundUpdate: true
                    )
                }
                
                // Trigger alarm scheduling for updated events
                Task {
                    await self.alarmSchedulingDelegate?.scheduleAlarmsForCalendarEvents(self.calendarEvents)
                    
                    // Cancel alarms for deleted events
                    let deletedEventIds = previousEventIds.subtracting(newEventIds)
                    if !deletedEventIds.isEmpty {
                        await self.alarmSchedulingDelegate?.cancelAlarmsForDeletedEvents(Array(deletedEventIds))
                    }
                }
                
                // Schedule background processing for future updates
                self.scheduleBackgroundRefresh()
            } else {
                print("📅⚪ No meaningful calendar changes detected, skipping alarm sync")
            }
        }
    }
    
    // MARK: - Change Detection
    
    private func hasEventContentChanged(previous: [CalarmEvent], new: [CalarmEvent]) -> Bool {
        // Create lookup dictionaries for efficient comparison
        let previousLookup = Dictionary(uniqueKeysWithValues: previous.map { ($0.originalEventId ?? $0.id, $0) })
        let newLookup = Dictionary(uniqueKeysWithValues: new.map { ($0.originalEventId ?? $0.id, $0) })
        
        // Check if any event times or alarm minutes changed
        for (eventId, newEvent) in newLookup {
            if let previousEvent = previousLookup[eventId] {
                // Compare key properties that affect alarm scheduling
                if previousEvent.startDate != newEvent.startDate ||
                   previousEvent.alarmMinutes != newEvent.alarmMinutes ||
                   previousEvent.title != newEvent.title {
                    print("📅🔍 Event content changed for: \(newEvent.title)")
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Alarm Pattern Parsing
    
    private func extractAlarmMinutes(from event: EKEvent) -> Int? {
        // Check title for alarm pattern
        if let title = event.title {
            if let minutes = extractMinutesFromText(title) {
                return minutes
            }
        }
        
        // Check notes for alarm pattern
        if let notes = event.notes {
            if let minutes = extractMinutesFromText(notes) {
                return minutes
            }
        }
        
        return nil
    }
    
    private func extractMinutesFromText(_ text: String) -> Int? {
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = alarmPattern.matches(in: text, options: [], range: range)
        
        for match in matches {
            if match.numberOfRanges > 1 {
                let captureGroupRange = match.range(at: 1)
                if let range = Range(captureGroupRange, in: text) {
                    let minutesString = String(text[range])
                    if let minutes = Int(minutesString) {
                        return minutes
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    func getCalendarEventById(_ id: String) -> CalarmEvent? {
        return calendarEvents.first { $0.id == id }
    }
    
    func getEventsByDateRange(start: Date, end: Date) -> [CalarmEvent] {
        return calendarEvents.filter { event in
            event.alarmDate >= start && event.alarmDate <= end
        }
    }
}

// MARK: - Calendar Notification Service

@MainActor
class CalendarNotificationService: ObservableObject {
    
    init() {
        requestNotificationPermissions()
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("📱 Notification permissions granted for automatic triggering")
            } else {
                print("⚠️ Notification permissions denied - automatic triggering will be limited")
            }
        }
    }
    
    func sendCalendarUpdateNotification(eventCount: Int, isBackgroundUpdate: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = "📅 Calendar Updated"
        content.body = "Found \(eventCount) upcoming events. Live Activities refreshed automatically."
        content.sound = .none // Silent notification
        content.badge = NSNumber(value: eventCount)
        
        // Add action to trigger app opening
        let openAction = UNNotificationAction(
            identifier: "REFRESH_LIVE_ACTIVITIES",
            title: "Refresh Live Activities",
            options: [.foreground] // This brings app to foreground
        )
        
        let category = UNNotificationCategory(
            identifier: "CALENDAR_UPDATE",
            actions: [openAction],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = "CALENDAR_UPDATE"
        
        // Add custom data for processing
        content.userInfo = [
            "action": "refresh_live_activities",
            "eventCount": eventCount,
            "isBackgroundUpdate": isBackgroundUpdate,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // Schedule immediate delivery
        let request = UNNotificationRequest(
            identifier: "calendar_update_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📱 Sent automatic calendar update notification")
            
            // Also schedule a background task to trigger Live Activity refresh
            await scheduleAutomaticLiveActivityRefresh()
            
        } catch {
            print("❌ Failed to send calendar update notification: \(error)")
        }
    }
    
    private func scheduleAutomaticLiveActivityRefresh() async {
        // Schedule a BGContinuedProcessingTask for iOS 26
        let request = BGAppRefreshTaskRequest(identifier: CalendarService.liveActivityTriggerTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5) // 5 seconds from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📱 Scheduled automatic Live Activity refresh task")
        } catch {
            print("❌ Failed to schedule Live Activity refresh task: \(error)")
        }
    }
    
    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == "CALENDAR_UPDATE" else {
            return
        }
        
        switch response.actionIdentifier {
        case "REFRESH_LIVE_ACTIVITIES":
            print("📱 User triggered Live Activity refresh from notification")
            // This will be handled by the app delegate when it brings app to foreground
            
        case UNNotificationDefaultActionIdentifier:
            print("📱 User tapped notification - app will come to foreground")
            // App automatically processes pending Live Activities when coming to foreground
            
        default:
            break
        }
    }
}