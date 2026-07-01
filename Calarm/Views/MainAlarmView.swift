//
//  MainAlarmView.swift
//  Calarm
//
//

import AlarmKit
import EventKit
import SwiftUI

struct MainAlarmView: View {
    @EnvironmentObject var alarmStore: AlarmStore
    @State private var isAddingAlarm = false
    @State private var editingAlarm: AlarmData?
    @State private var showingCalendarPermissionAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Calendar permission banner
                    if alarmStore.calendarService.authorizationStatus != .fullAccess {
                        calendarAccessBanner
                    }
                    
                    if alarmStore.alarms.isEmpty {
                        emptyStateView
                    } else {
                        alarmListView
                    }
                }
            }
            .navigationTitle("Alarms")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        // Calendar sync button
                        Button(action: {
                            Task {
                                if alarmStore.calendarService.authorizationStatus == .fullAccess {
                                    await alarmStore.refreshCalendarEvents()
                                } else {
                                    await alarmStore.requestCalendarAccess()
                                }
                            }
                        }) {
                            Image(systemName: alarmStore.calendarService.authorizationStatus == .fullAccess ? "calendar.badge.checkmark" : "calendar")
                                .font(.title2)
                                .foregroundColor(alarmStore.calendarService.authorizationStatus == .fullAccess ? .green : .orange)
                        }
                        
                        // Add manual alarm button
                        Button(action: {
                            isAddingAlarm = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                    }
                }

                if !alarmStore.alarms.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingAlarm) {
            AddEditAlarmView(alarmStore: alarmStore)
        }
        .sheet(item: $editingAlarm) { alarm in
            AddEditAlarmView(alarmStore: alarmStore, editingAlarm: alarm)
        }
    }

    // MARK: - Calendar Access Banner
    
    private var calendarAccessBanner: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar Integration")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Grant calendar access to automatically create alarms from events with 'alarm#' in notes")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Button("Grant Access") {
                    Task {
                        await alarmStore.requestCalendarAccess()
                    }
                }
                .font(.caption)
                .foregroundColor(.orange)
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "alarm")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("No Alarms")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("Add an alarm or grant calendar access to import events")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Alarm List View

    private var alarmListView: some View {
        List {
            // Calendar Alarms Section
            if !alarmStore.calendarAlarms.isEmpty {
                Section(header: 
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.green)
                        Text("Calendar Alarms")
                            .foregroundColor(.green)
                        Spacer()
                        Text("\(alarmStore.calendarAlarms.count)")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                ) {
                    ForEach(alarmStore.calendarAlarms) { alarm in
                        AlarmRowView(
                            alarm: alarm,
                            onToggle: {
                                alarmStore.toggleAlarm(alarm)
                            },
                            onEdit: {
                                // Calendar alarms should not be editable
                                // Instead, show info about the source event
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            
            // Manual Alarms Section
            if !alarmStore.manualAlarms.isEmpty {
                Section(header: 
                    HStack {
                        Image(systemName: "alarm")
                            .foregroundColor(.orange)
                        Text("Manual Alarms")
                            .foregroundColor(.orange)
                        Spacer()
                        Text("\(alarmStore.manualAlarms.count)")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                ) {
                    ForEach(alarmStore.manualAlarms) { alarm in
                        AlarmRowView(
                            alarm: alarm,
                            onToggle: {
                                alarmStore.toggleAlarm(alarm)
                            },
                            onEdit: {
                                editingAlarm = alarm
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteManualAlarms)
                }
            }
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helper Methods

    private func deleteAlarms(offsets: IndexSet) {
        for index in offsets {
            alarmStore.deleteAlarm(alarmStore.alarms[index])
        }
    }
    
    private func deleteManualAlarms(offsets: IndexSet) {
        let manualAlarms = alarmStore.manualAlarms
        for index in offsets {
            alarmStore.deleteAlarm(manualAlarms[index])
        }
    }
}

// MARK: - Alarm Row View

struct AlarmRowView: View {
    let alarm: AlarmData
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                // Duration display (following AlarmKit countdown pattern)
                Text(alarm.durationString)
                    .font(.system(size: 50, weight: .thin, design: .default))
                    .foregroundColor(alarm.isEnabled ? .white : .gray)
                    .minimumScaleFactor(0.5) // Allow text to scale down to 50% if needed
                    .lineLimit(1) // Keep it on one line
                    .scaledToFit() // Scale to fit available space

                // Title and source info
                HStack(spacing: 8) {
                    Text(alarm.title)
                        .font(.body)
                        .foregroundColor(alarm.isEnabled ? .white : .gray)

                    Text("•")
                        .foregroundColor(.gray)

                    if alarm.isFromCalendar {
                        Text("from \(alarm.calendarTitle ?? "Calendar")")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Alarm")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                }
            }
            .layoutPriority(1) // Give the text section higher priority

            Spacer()

            // Toggle switch
            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .orange))
            .fixedSize() // Prevent the toggle from being compressed
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}

// MARK: - Preview

#Preview {
    MainAlarmView()
}
