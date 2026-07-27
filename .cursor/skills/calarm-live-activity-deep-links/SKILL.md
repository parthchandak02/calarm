---
name: calarm-live-activity-deep-links
description: >-
  CALarm Dynamic Island and Lock Screen tap-to-open via calarm:// deep links and
  widgetURL. Use when wiring Live Activity navigation or explaining Island tap behavior.
---

# CALarm Live Activity Deep Links

## Platform behavior (not a bug)

Tapping Dynamic Island / Lock Screen Live Activity **always opens the app** — Apple design. CALarm cannot disable this; use deep links to land on the right screen.

## URL scheme

```
calarm://event?id=<EventKit eventIdentifier>
```

- Registered in `Calarm/Info.plist` (`CFBundleURLTypes`)
- Built by `Calarm/Utilities/CalarmDeepLink.swift`
- Parsed in `ScheduleStore.handleIncomingURL`

## Widget extension

`CalarmWidgetExtensionLiveActivity.swift`:

- `.widgetURL(eventURL(for: context))` on Lock Screen view and `DynamicIsland`
- `eventID` comes from `AlarmAppMetadata` set in `AlarmScheduler`

## App routing

1. `CalarmApp.onOpenURL` → `scheduleStore.handleIncomingURL`
2. Sets `pendingEventDeepLinkID`
3. `ScheduleView.presentPendingEventDeepLinkIfNeeded()` → `EventDetailView`

## Metadata requirement

Alarms scheduled **before** deep-link support lack `eventID` in metadata. User must toggle alarm or pull-to-refresh to reschedule.

## OpenAlarmApp intent

`AlarmAppIntents.swift` — `openAppWhenRun = true` for custom alert "Open" button, **not** for Island tap (system default).

## Test

1. Enable alarm on upcoming event.
2. Wait for Island countdown.
3. Tap pill → app opens to that event's detail.

## Related skill

`calarm-stacked-live-activities` — only one Island pill should be visible.
