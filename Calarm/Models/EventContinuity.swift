//
//  EventContinuity.swift
//  Calarm
//

import Foundation

/// Occurrence IDs embed the start time, so a moved meeting, an event re-created by another
/// tool (Focus Block Creator inserts then removes), or an EventKit copy replaced by its
/// Google twin arrives under a new ID. Its per-event alarm setting stayed on the old ID and
/// the new one fell back to the default, usually "No alarm": an armed meeting went silent.
nonisolated enum EventContinuity {
    struct Occurrence: Equatable, Sendable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date

        var baseIdentifier: String? {
            EventOccurrenceID(rawValue: id)?.eventIdentifier
        }
    }

    /// How far a meeting may move and still be matched by its underlying event. EventKit
    /// gives every occurrence of a recurring series the same identifier, so an unbounded match
    /// handed a deleted occurrence's setting to one a week away.
    static let maximumMove: TimeInterval = 24 * 60 * 60

    /// Old ID → new ID for each removed occurrence that reappeared.
    ///
    /// `removed`: occurrences gone this sync that were armed. Only armed settings travel: a
    /// wrong carry then adds a ring, never silences a meeting. `added`: occurrences that
    /// appeared this sync; `unconfigured`: every current occurrence with no setting of its
    /// own, including one that appeared a sync earlier, as when a copy is inserted before the
    /// original is removed.
    ///
    /// Same underlying event first (EventKit and Google keep it across a move), nearest start
    /// within `maximumMove`; else same title in the same minute, the two sources' clocks
    /// differing by fractions of a second. An occurrence that has already ended left because
    /// it is over, not because it moved.
    static func carriedSettings(
        removed: [Occurrence],
        added: [Occurrence],
        unconfigured: [Occurrence],
        now: Date
    ) -> [String: String] {
        var taken = Set<String>()
        var result: [String: String] = [:]
        let addedIDs = Set(added.map(\.id))

        for old in removed where old.endDate > now {
            let sameEvent = unconfigured.filter {
                addedIDs.contains($0.id)
                    && !taken.contains($0.id)
                    && $0.baseIdentifier != nil
                    && $0.baseIdentifier == old.baseIdentifier
                    && abs($0.startDate.timeIntervalSince(old.startDate)) <= maximumMove
            }
            let match = sameEvent.min {
                abs($0.startDate.timeIntervalSince(old.startDate))
                    < abs($1.startDate.timeIntervalSince(old.startDate))
            } ?? unconfigured.first {
                !taken.contains($0.id)
                    && $0.title == old.title
                    && abs($0.startDate.timeIntervalSince(old.startDate)) < 60
            }
            guard let match else { continue }
            result[old.id] = match.id
            taken.insert(match.id)
        }
        return result
    }
}
