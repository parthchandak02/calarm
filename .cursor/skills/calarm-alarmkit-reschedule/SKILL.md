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
await alarmScheduler.reschedule(
    events: events,
    snoozeSeconds: defaultSnooze.seconds,
    force: true
)
```

Call from: `reload()`, `toggleAlarm`, `addAlarmOffset`, `removeAlarmOffset`, `updateDefaultAlarmOffset`, `setAllAlarmsEnabled`, `updateDefaultSnooze`.

## Live Activity assignment

- Compute `nextLiveActivityKey` from **all** instances sorted by `fireDate`.
- Only the earliest upcoming instance gets `withLiveActivity: true`.
- All others get alert-only `AlarmPresentation` (no countdown Live Activity UI).

## Guard behavior

- `hasAlertingAlarms()` — skip reschedule **only** while `.alerting` (actively ringing).
- **Do not** block on `.countdown` — calendar changes must reschedule during countdown.

## Cancel removed events

On `reload()`, call `cancelRemoved(eventIDs:)` for calendar IDs that disappeared before rescheduling.

## Stable IDs

Alarm UUID = SHA256 prefix of `calarm.{eventID}.{offset.rawValue}`. Required for idempotent cancel/schedule.

## Files

- `Calarm/Services/AlarmScheduler.swift`
- `Calarm/Store/ScheduleStore.swift`
- `Calarm/Intents/AlarmAppIntents.swift`

## Anti-patterns

- `reschedule(event:among:)` that only touches one event (causes stacked Live Activities).
- `reload()` with `force: false` while any countdown exists (silently skips updates).
