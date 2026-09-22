---
name: calarm-trust-diagnostics
description: >-
  CALarm trust UX — permission banners, schedule failure surfacing, diagnostics settings,
  test alarm, next-alarm header. Use when editing permission or support-facing UI.
---

# CALarm Trust & Diagnostics

## Surfaces

| Surface | When |
|---------|------|
| AlarmKit denied banner | `ScheduleView` when `alarmAuthorization == .denied` |
| Schedule failure banner | `scheduleFailures` after reschedule |
| Next alarm strip | `nextUpcomingAlarm` in schedule header |
| Settings diagnostics | Calendar/alarm status, next ring, last reschedule, test alarm |

## Test alarm

Settings → Diagnostics → **Test alarm (8 seconds)**. Device only; Simulator shows explanation.

## Logging

`SchedulerLog` (`os.Logger`, subsystem `com.calarmapp.calarm`, category `scheduler`).

## Bulk enable

When default is **No alarm**, confirm before applying 10-minute fallback.
