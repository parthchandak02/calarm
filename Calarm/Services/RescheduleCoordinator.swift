//
//  RescheduleCoordinator.swift
//  Calarm
//

import Foundation

struct RescheduleSummary: Equatable {
    let finishedAt: Date
    let scheduledCount: Int
    let failureCount: Int
    let skippedDuringAlerting: Bool
}

@MainActor
final class RescheduleCoordinator {
    private var generation: UInt64 = 0
    private var inFlightTask: Task<Void, Never>?
    private(set) var lastSummary: RescheduleSummary?
    private var debounceTask: Task<Void, Never>?

    func requestReschedule(
        debounceNanoseconds: UInt64 = 75_000_000,
        operation: @escaping () async -> RescheduleSummary
    ) {
        debounceTask?.cancel()
        debounceTask = Task {
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await perform(operation: operation)
        }
    }

    func requestRescheduleImmediate(operation: @escaping () async -> RescheduleSummary) async {
        await perform(operation: operation)
    }

    private func perform(operation: @escaping () async -> RescheduleSummary) async {
        generation &+= 1
        let token = generation
        inFlightTask?.cancel()
        inFlightTask = Task {
            let summary = await operation()
            guard !Task.isCancelled, token == generation else { return }
            lastSummary = summary
        }
        await inFlightTask?.value
    }
}
