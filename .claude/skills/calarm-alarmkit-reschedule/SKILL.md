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
- **The Live Activity alarm has no schedule** — `schedule: nil`, `preAlert` = seconds until
  fire — so it counts down from now and rings on time. `.fixed` plus a big `preAlert` put a
  9:00 event's countdown on screen at 9:50 heading for 10:14:54 (fixed date + pre-alert).
  AlarmKit stores no fire date for such an alarm, so `AlarmScheduler` keeps one per UUID
  under `CalarmPersistence.Key.countdownTargets`; `intendedFireDate(for:)` reads either.
  `needsReschedule` keys Live Activity on schedule type (`nil` = countdown), not `preAlert`.
- Every other alarm stays `.fixed` with `preAlert: 1` (landscape workaround).
- Settings → Status → **Alarm timing** reports the 8-second test alarm's actual ring time.
  The test alarm is countdown-mode too, so anything but ~8s is a regression. The `.fixed` +
  `preAlert` probe is retired (device measured *Late · 16s*, 2026-09-24; see RESEARCH.md).

## Guard behavior

- `hasAlertingAlarms()` — skip reschedule **only** while `.alerting`.
- **Do not** block on `.countdown`.

## Coordinator + alarmUpdates

- `RescheduleCoordinator` serializes overlapping reschedule/reload tasks.
- `AlarmUpdatesObserver` listens to `AlarmManager.shared.alarmUpdates`.

## Collision policy

`AlarmGrouping` merges every alarm firing in the same minute into **one** AlarmKit alarm,
carried by the primary member's stable ID (titled events lead "Busy" busy-only blocks) and
titled "First + N more". The other members' IDs fall out of the desired set and are cancelled
by `cancelUndesiredAlarms`. AlarmKit exposes no attributes, so each alarm's signature
(`title|ring` or `title|vibrate`, `DesiredInstance.signature`) is stored under
`CalarmPersistence.Key.alarmTitles` and `needsReschedule` compares it. The key and the
`title(for:)`/`setTitle` names predate vibrate mode; the value is not a display title. (This replaced a 2s stagger that rang each same-time event back to back.)

## Vibrate mode

`AlarmSoundPolicy.vibratesNow` (manual setting or `CalarmFocusFilter`) makes every primary
alarm use the silent `calarm-silence.caf` and adds a ringing fallback one minute later, ID
`AlarmSchedulingHelpers.fallbackAlarmID(for:)`, cancelled by the stop and snooze intents.
Fallback IDs are in `alarmEventLookup`, so they are cancelled like any undesired alarm when
vibrate mode turns off. The stored per-alarm signature is title plus sound.

## Stable IDs

`calarm.{occurrenceID}.{offset}` via `EventOccurrenceID.rawValue`.

## Files

- `Calarm/Services/AlarmScheduler.swift`
- `Calarm/Services/RescheduleCoordinator.swift`
- `Calarm/Store/ScheduleStore.swift`
- `Calarm/Models/AlarmGrouping.swift`
- `Calarm/Models/AlarmSoundPolicy.swift`
- `Calarm/Intents/CalarmFocusFilter.swift`
- `CalarmShared/AlarmSchedulingHelpers.swift`

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

1. `shouldTerminateStale` — cancel `.countdown`/`.paused` after `fireDate + snoozeAwareCountdownGrace` (snooze + 60s), not `event.endDate`. A flat 60s killed real snoozes.
2. `cancelUndesiredAlarms` — only preserve `.alerting` within `alertingCleanupGrace` (5 min snooze window).
3. `reconcileOrphanAlarms` — for alarms not in the current lookup: terminate once stale, and
   terminate a *future* orphan only when `AlarmSchedulingHelpers.isDuplicateFire` finds a
   managed alarm within 30s (the same meeting under a changed ID). Other future orphans are
   kept — fail open. Also runs after each reschedule, once replacements exist.
4. `ScheduleStore.refreshOnForeground()` — call `reconcileAlarmLifecycle` **before** EventKit reload.

**Helpers:** `AlarmSchedulingHelpers.isStaleAlarm(fireDate:graceAfterFire:)`, `countdownCleanupGrace`, `alertingCleanupGrace`.

Sources: [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit), [AlarmManager.alarmUpdates](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmupdates), Live Activities HIG, OSS samples (BleepingSwift, ADHDAlarms, alarmkit-patterns).
