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

- `LiveActivityWindow.plans(fireDates:lead:now:)` gives every upcoming primary a
  `LiveActivityPlan`; `DesiredInstance.plan` carries it. Lead L comes from Settings → Alarms →
  Island (`LiveActivityLead`, `CalarmPersistence.Key.liveActivityLeadMinutes`, default 5).
- **`.fixedWindow(start:preAlert:)`** — `.fixed(ring − L)` + `preAlert: L`. On device the
  countdown starts *at* the fixed date (9:00 event counting at 9:50 toward 10:14:54; test alarm
  *Late · 16s*, 2026-09-24), so the card shows at ring − L and rings on time. Under Apple's
  documented reading it would ring L early — fail-open, never late.
- Effective lead is `min(L, ring − previous ring)`, so windows never overlap. The first alarm
  already inside its window (+10s margin) gets **`.countdownNow`** (`schedule: nil`, pre-alert
  = time left); a later one gets `.alertOnly`. Lead ALL = old behaviour: next alarm
  `.countdownNow`, rest `.alertOnly`.
- **`.alertOnly`** — `.fixed(ring)` with `preAlert: 1` (landscape workaround). Fallbacks too.
- Every Live Activity plan stores the ring time under `CalarmPersistence.Key.countdownTargets`;
  `intendedFireDate(for:)` prefers it over the fixed date (`LiveActivityWindow.resolvedFireDate`).
  Without a target it reads fixed date + pre-alert. Stored state is pruned only after a successful
  `AlarmManager.shared.alarms` read.
- `needsReschedule` asks `LiveActivityWindow.existingSatisfies`: a started window satisfies
  `.countdownNow` to the same ring, so the hand-over is not churn; windows match within 0.5s.
- The fingerprint includes `lead:N`; changing the lead forces a full reschedule.
- Settings → Status → **Alarm timing**: with a lead set the test alarm is a window
  (`.fixed(+8s)` + 8s, expected ~16s; ~8s = *Early*, the device follows the docs). With ALL it
  is countdown mode, expected ~8s.

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

`AlarmSoundPolicy.vibratesNow` (manual setting or `CalarmFocusFilter`) makes every alarm use
the silent `calarm-silence.caf`. **Nothing else: one ring per chosen offset** (owner's rule,
2026-09-25). The ringing fallback earlier builds armed a minute later is gone;
`AlarmSchedulingHelpers.fallbackAlarmID(for:)` survives only so `cancelLegacyFallbacks()`
(every reconcile), `cancelUndesiredAlarms` (fallback IDs stay in `alarmEventLookup`), the stop
and snooze intents, and `cancel(occurrenceID:offset:)` can remove leftovers. Drop those after a
release. The stored per-alarm signature is title plus sound.

## Snooze holds

A snoozed alarm (`.countdown`/`.paused`, ring time passed) is not in the desired set, which
holds upcoming alarms only. `SnoozeAlarmIntent` records `Key.snoozedUntil` (now + snooze)
**before** `countdown(id:)`; `holdUntil(for:)` keeps the alarm until snoozedUntil + 60s
(`snoozeHoldDeadline`), or a ringing one until 5 min past the ring or snooze end
(`alertingDeadline`). Without a record, the old rule keyed to the ring time applies. Event end
never cuts a hold short (`shouldEndWithEvent`). Stop, cancel and terminate clear the record.

`Key.rangFireDates` remembers the fire date each alarm ID rang for (alarm updates, stop and
snooze intents); `desiredInstances` skips an ID that already rang for its fire date.

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
- `CalarmShared/LiveActivityWindow.swift`

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

1. `shouldTerminateStale` — cancel `.countdown`/`.paused`/`.alerting` once `holdUntil(for:)` passes (see Snooze holds), not at `event.endDate`. A flat 60s killed real snoozes.
2. `cancelUndesiredAlarms` — keep an undesired alarm only while `holdUntil(for:)` holds it; legacy fallbacks always go.
3. `reconcileOrphanAlarms` — for alarms not in the current lookup: terminate once stale, and
   terminate a *future* orphan only when `AlarmSchedulingHelpers.isDuplicateFire` finds a
   managed alarm within 30s (the same meeting under a changed ID). Other future orphans are
   kept — fail open. Also runs after each reschedule, once replacements exist.
4. `ScheduleStore.refreshOnForeground()` — call `reconcileAlarmLifecycle` **before** EventKit reload.

**Helpers:** `AlarmSchedulingHelpers.isStaleAlarm(fireDate:graceAfterFire:)`, `countdownCleanupGrace`, `alertingCleanupGrace`.

Sources: [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit), [AlarmManager.alarmUpdates](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmupdates), Live Activities HIG, OSS samples (BleepingSwift, ADHDAlarms, alarmkit-patterns).
