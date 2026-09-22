---
name: calarm-occurrence-identity
description: >-
  CALarm per-occurrence event IDs for recurring calendar events. Use when editing
  ScheduleEvent identity, EventAlarmPreferences keys, deep links, or AlarmKit stable IDs.
---

# CALarm Occurrence Identity

## Canonical ID

`EventOccurrenceID` in `CalarmShared/EventOccurrenceID.swift`:

```
{eventIdentifier}_{startDate.timeIntervalSince1970}
```

Use for: `ScheduleEvent.id`, preference keys, `stableAlarmID`, deep links.

## Deep links

`calarm://event?id={eventIdentifier}&start={unixTimestamp}`

Legacy `calarm://event?id={bareIdentifier}` still resolves to first matching occurrence.

## Migration

`EventAlarmPreferences.migrateLegacyKeys(for:)` copies bare `eventIdentifier` overrides to each in-window occurrence, then deletes legacy keys.

## Recurring events

Each EKEvent row in the fetch window is a distinct occurrence — independent alarm toggles and AlarmKit UUIDs.
