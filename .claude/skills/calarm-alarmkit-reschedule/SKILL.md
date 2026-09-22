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

## AlarmKit platform lessons

- Countdown presentation requires a widget Live Activity or iOS may dismiss alarms.
- Alerting UI is system-owned; countdown/paused UI lives in the widget.
- Stable UUID; cancel/stop before replace; log cancel failures.
- `preAlert: nil` means no countdown (not `0`).
- **AlarmKit does not wake the app** — reconcile stale/orphan alarms on foreground, reschedule, and `alarmUpdates` (Apple: [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)).
- Observe `alarmUpdates`.
- Do **not** defer reschedule on `.countdown` — only hard-skip on `.alerting`.

## Stale / delayed alarm cleanup

**Symptom:** Alarms fire hours after the event (e.g. 10:00 alarm on a 10:00–16:00 meeting rings at 16:00).

**Root cause:** Keeping `.countdown`/`.paused` alarms alive until `event.endDate` instead of fire time. AlarmKit holds the alarm until the event block ends.

**Fix (AlarmScheduler):**

1. `shouldTerminateStale` — cancel `.countdown`/`.paused` after `fireDate + countdownCleanupGrace` (60s), not `event.endDate`.
2. `cancelUndesiredAlarms` — only preserve `.alerting` within `alertingCleanupGrace` (5 min snooze window).
3. `reconcileOrphanAlarms` — terminate AlarmKit alarms not in current schedule lookup (dropped events, ID migrations).
4. `ScheduleStore.refreshOnForeground()` — call `reconcileAlarmLifecycle` **before** EventKit reload.

**Helpers:** `AlarmSchedulingHelpers.isStaleAlarm(fireDate:graceAfterFire:)`, `countdownCleanupGrace`, `alertingCleanupGrace`.

Sources: [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit), [AlarmManager.alarmUpdates](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmupdates), Live Activities HIG, OSS samples (BleepingSwift, ADHDAlarms, alarmkit-patterns).
