//
//  AlarmUpdatesObserver.swift
//  Calarm
//

import AlarmKit
import Foundation

@MainActor
final class AlarmUpdatesObserver {
    var onAlarmsChanged: (([Alarm]) -> Void)?
    private var observationTask: Task<Void, Never>?

    func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.onAlarmsChanged?(alarms)
                }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    deinit {
        observationTask?.cancel()
    }
}
