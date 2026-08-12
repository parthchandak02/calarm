---
name: calarm-alarmkit-reschedule
description: >-
  CALarm AlarmKit full-reschedule patterns in AlarmScheduler and ScheduleStore.
  Use when editing alarm scheduling, Live Activity assignment, snooze, cancel logic,
  or debugging missed/stale alarms.
---

# CALarm AlarmKit Reschedule

## Golden rule

**Always full-reschedule all events.** Never partial per-event reschedule that leaves other AlarmKit alarms untouched.

## Correct pattern

```swift
rescheduleCoordinator.requestReschedule {
    await performReschedule(force: true)
}
```

Underlying call:

```swift
await alarmScheduler.reschedule(events: events, snoozeSeconds: defaultSnooze.seconds, force: true)
```

## Live Activity assignment

- Compute `nextLiveActivityKey` from **all** instances sorted by `fireDate`.
- Only the earliest upcoming instance gets `withLiveActivity: true`.
- All others get alert-only presentation.

## Guard behavior

- `hasAlertingAlarms()` — skip reschedule **only** while `.alerting`.
- **Do not** block on `.countdown`.

## Coordinator + alarmUpdates

- `RescheduleCoordinator` serializes overlapping reschedule/reload tasks.
- `AlarmUpdatesObserver` listens to `AlarmManager.shared.alarmUpdates`.

## Collision policy

`AlarmSchedulingHelpers.collisionGroupsSortedByFireDate` staggers duplicate fire times by 2s.

## Stable IDs

`calarm.{occurrenceID}.{offset}` via `EventOccurrenceID.rawValue`.

## Files

- `Calarm/Services/AlarmScheduler.swift`
- `Calarm/Services/RescheduleCoordinator.swift`
- `Calarm/Store/ScheduleStore.swift`

## Anti-patterns

- Partial per-event reschedule (stacked Live Activities).
- Raw `Task { reschedule }` without coordinator (races).
