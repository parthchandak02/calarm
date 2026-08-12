---
name: calarm-live-activity-deep-links
description: >-
  CALarm Dynamic Island and Lock Screen tap-to-open via calarm:// deep links and
  widgetURL. Use when wiring Live Activity navigation or explaining Island tap behavior.
---

# CALarm Live Activity Deep Links

## Platform behavior (not a bug)

Tapping Dynamic Island / Lock Screen Live Activity **always opens the app** — Apple design. Use deep links to land on the right occurrence.

## URL scheme

```
calarm://event?id=<eventIdentifier>&start=<unixTimestamp>
```

- Shared builder: `CalarmShared/CalarmDeepLink.swift`
- `occurrenceID` = `EventOccurrenceID.rawValue` stored in `AlarmAppMetadata.eventID`
- Legacy `?id=` only (no `start`) resolves to first matching occurrence

## Widget extension

`CalarmWidgetExtensionLiveActivity.swift` — `.widgetURL(CalarmDeepLink.eventURL(occurrenceID:))`

## App routing

1. `CalarmApp.onOpenURL` → `handleIncomingURL` → `pendingEventDeepLinkID` + `pendingDeepLinkRoute`
2. `ScheduleView.presentPendingEventDeepLinkIfNeeded()` → `EventDetailView`
3. Missing event → alert + clear pending link

## Metadata migration

`occurrenceMetadataMigrationDone` flag triggers one `reschedule(force: true)` on first launch after upgrade.

## Related skills

- `calarm-stacked-live-activities` — one Island pill
- `calarm-occurrence-identity` — occurrence ID format
