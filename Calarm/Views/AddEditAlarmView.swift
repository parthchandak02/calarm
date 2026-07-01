//
//  AddEditAlarmView.swift
//  Calarm
//
//

import SwiftUI

struct AddEditAlarmView: View {
    @ObservedObject var alarmStore: AlarmStore
    @Environment(\.dismiss) private var dismiss

    // Editing state
    let editingAlarm: AlarmData?

    // Form state (using AlarmKit schedule pattern for future dates)
    @State private var title = "Title"
    @State private var alarmDate = Date().addingTimeInterval(60) // Default to 1 minute from now for fast testing
    @State private var preAlertMinutes = 10
    @State private var postAlertMinutes = 5
    @State private var soundName = "Chime"
    @State private var snoozeEnabled = true

    // UI state
    @State private var showingSoundPicker = false

    init(alarmStore: AlarmStore, editingAlarm: AlarmData? = nil) {
        self.alarmStore = alarmStore
        self.editingAlarm = editingAlarm

        if let alarm = editingAlarm {
            _title = State(initialValue: alarm.title)
            _alarmDate = State(initialValue: alarm.alarmDate)
            _preAlertMinutes = State(initialValue: alarm.preAlertMinutes)
            _postAlertMinutes = State(initialValue: alarm.postAlertMinutes)
            _soundName = State(initialValue: alarm.soundName)
            _snoozeEnabled = State(initialValue: alarm.snoozeEnabled)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Alarm Time Picker
                    alarmTimePickerSection

                    // Settings List
                    settingsList
                }
            }
            .navigationTitle(editingAlarm == nil ? "Add Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAlarm()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showingSoundPicker) {
            SoundPickerView(selectedSound: $soundName)
        }
    }

    // MARK: - Alarm Time Picker Section

    private var alarmTimePickerSection: some View {
        VStack(spacing: 20) {
            Text("Alarm Time")
                .font(.headline)
                .foregroundColor(.white)

            DatePicker("Select alarm time", selection: $alarmDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical) // Calendar-style with today highlighted
                .colorScheme(.dark)
                .accentColor(.red)
                .background(Color.black)
                .foregroundColor(.white)
                .preferredColorScheme(.dark)
                .environment(\.colorScheme, .dark)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }

    // MARK: - Settings List (Following AlarmKit countdown pattern)

    private var settingsList: some View {
        VStack(spacing: 0) {
            // Single Compact Settings Card
            VStack(spacing: 0) {
                // Title Row
                HStack {
                    Text("Title")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    Spacer()
                    TextField("Title", text: $title)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .background(Color.gray.opacity(0.3))

                // Sound Row
                Button(action: {
                    showingSoundPicker = true
                }) {
                    HStack {
                        Text("Sound")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        Spacer()
                        Text(soundName)
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()
                    .background(Color.gray.opacity(0.3))

                // Snooze Row
                HStack {
                    Text("Snooze")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    Spacer()
                    Toggle("", isOn: $snoozeEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .orange))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .background(Color.gray.opacity(0.3))

                // Pre-Alert Row
                HStack {
                    Text("Pre-Alert")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    Spacer()
                    Picker("", selection: $preAlertMinutes) {
                        ForEach([5, 10, 15, 30], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .background(Color.gray.opacity(0.3))

                // Alert Duration Row
                HStack {
                    Text("Duration")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                    Spacer()
                    Picker("", selection: $postAlertMinutes) {
                        ForEach([1, 5, 10, 15], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func saveAlarm() {
        // Ensure alarm time is in the future (at least 30 seconds from now)
        let now = Date()
        let minimumFutureTime = now.addingTimeInterval(30) // 30 seconds buffer
        let validAlarmDate = alarmDate < minimumFutureTime ? minimumFutureTime : alarmDate

        let alarm = AlarmData(
            title: title.isEmpty ? "Title" : title,
            isEnabled: true,
            alarmDate: validAlarmDate,
            soundName: soundName,
            snoozeEnabled: snoozeEnabled,
            preAlertMinutes: preAlertMinutes,
            postAlertMinutes: postAlertMinutes
        )

        if let editingAlarm {
            let updatedAlarm = AlarmData(
                id: editingAlarm.id,
                title: title.isEmpty ? "Title" : title,
                isEnabled: editingAlarm.isEnabled,
                alarmDate: validAlarmDate,
                soundName: soundName,
                snoozeEnabled: snoozeEnabled,
                preAlertMinutes: preAlertMinutes,
                postAlertMinutes: postAlertMinutes
            )
            alarmStore.updateAlarm(updatedAlarm)
        } else {
            alarmStore.addAlarm(alarm)
        }

        dismiss()
    }
}

// MARK: - Duration Quick Selection View

struct DurationQuickSelectView: View {
    @Binding var countdownMinutes: Int
    @Environment(\.dismiss) private var dismiss

    private let presetDurations = [
        (title: "5 minutes", minutes: 5),
        (title: "10 minutes", minutes: 10),
        (title: "15 minutes", minutes: 15),
        (title: "30 minutes", minutes: 30),
        (title: "1 hour", minutes: 60),
        (title: "2 hours", minutes: 120),
        (title: "4 hours", minutes: 240),
        (title: "8 hours", minutes: 480)
    ]

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            List {
                ForEach(presetDurations, id: \.minutes) { preset in
                    Button(action: {
                        countdownMinutes = preset.minutes
                        dismiss()
                    }) {
                        HStack {
                            Text(preset.title)
                                .foregroundColor(.white)
                            Spacer()
                            if countdownMinutes == preset.minutes {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .listRowBackground(Color.gray.opacity(0.1))
                }
            }
            .listStyle(InsetGroupedListStyle())
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Duration Presets")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sound Picker View

struct SoundPickerView: View {
    @Binding var selectedSound: String
    @Environment(\.dismiss) private var dismiss

    private let availableSounds = [
        "Chime", "Bell", "Alarm", "Horn", "Digital", "Classic", "Radar", "Sci-Fi", "Signal"
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                List {
                    ForEach(availableSounds, id: \.self) { sound in
                        Button(action: {
                            selectedSound = sound
                            dismiss()
                        }) {
                            HStack {
                                Text(sound)
                                    .foregroundColor(.white)
                                Spacer()
                                if selectedSound == sound {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .listRowBackground(Color.gray.opacity(0.1))
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Sound")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddEditAlarmView(alarmStore: AlarmStore())
}
