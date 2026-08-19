---
name: calarm-stacked-live-activities
description: >-
  Diagnose and fix CALarm stacked Dynamic Island / Lock Screen Live Activity cards
  with out-of-order countdown times. Use when user reports multiple CALarm pills,
  non-sequential timers, or Island clutter.
---

# CALarm Stacked Live Activities

## Symptom

Multiple CALarm countdown cards in Dynamic Island or notification stack with times that are **not** in fire-date order (e.g. 17:03, 21:33, 16:43).

## Root cause

Partial per-event reschedule left **old Live Activities running** when a different event became "next." iOS displays Activities in **creation order**, not chronological order.

## Fix (code)

1. Remove per-event-only reschedule paths.
2. Always full `reschedule(events:force:true)` after any alarm change.
3. Assign `withLiveActivity: true` to exactly **one** instance (earliest `fireDate`).

## Fix (user device)

1. Force-quit CALarm.
2. Reopen (triggers `reload()` + full reschedule).
3. Confirm only **one** Island pill for the next alarm.

## Verify

- Enable alarms on 3+ events one-by-one → still only 1 Dynamic Island countdown.
- `./deploy.sh status` or `monitor` for ActivityKit logs.

## Intended product behavior

- Exactly **one** countdown presentation / Live Activity for the earliest `fireDate`.
- Tap opens app via `calarm://event?id=` deep link (see `calarm-live-activity-deep-links` skill).
- Multiple Live Activities collapse to minimal Island and look stacked.

## Regression guard

- Never reintroduce `reschedule(event:among:)` without rescheduling all other events' AlarmKit state.
- Countdown defer in `ScheduleStore` is a regression (do not reintroduce).

Sources: Apple AlarmKit docs, Live Activities HIG, OSS samples (BleepingSwift, ADHDAlarms, alarmkit-patterns).
