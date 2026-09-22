# CALarm UI Improvement Backlog

Agent-maintained backlog from UI audits (Aug 2026). Pick items by priority; mark done in commit messages.

## P0 — Non-native / broken feel

| # | Change | Files | Notes |
|---|--------|-------|-------|
| 1 | Unify screen horizontal inset to 20pt (or migrate all to 16) | `CalarmTheme.swift`, `ScheduleView.swift`, `SettingsSheet.swift`, `EventDetailView.swift` | Schedule at 16; settings at 20+16 |
| 2 | Replace Event Detail "Done" with system back | `EventDetailView.swift` | Pushed via `navigationDestination`, not sheet |
| 3 | `NavigationLink` + disclosure on event rows | `ScheduleView.swift` EventRow | Replace middle-column `onTapGesture` |
| 4 | Toolbar icons 44×44 pt | `CalarmComponents.swift` `CalarmToolbarIconButton`, bell menu in `ScheduleHeaderBar` | Currently 34×34 |
| 5 | Complete sheet chrome everywhere | `AlarmOffsetListPicker.swift` | Add nav style, toolbar chrome, presentationBackground, drag indicator |

## P1 — Consistency

| # | Change | Files |
|---|--------|-------|
| 6 | Reuse `SettingsSectionHeader` for schedule day headers | `ScheduleView.swift:280-285`, `CalarmComponents.swift` |
| 7 | Add `destructive` + `warning` to `CalarmTheme` | `CalarmTheme.swift`, `SettingsSheet.swift`, `EventDetailView.swift`, `ScheduleView.swift` |
| 8 | Standardize row vertical padding (12 or 14) | `SettingsSheet.swift`, `CalarmComponents.swift` |
| 9 | Shared primary/secondary/destructive button styles | New in `CalarmComponents.swift`; replace `ScheduleView` `.borderedProminent` |
| 10 | Pick one next-alarm signal | `ScheduleView.swift` banner vs NEXT chip vs row highlight |
| 11 | Named accent surface opacities | `CalarmTheme.swift` — `accentSubtle`, `accentSelected` |
| 12 | Consolidate bell menu into `CalarmToolbarIconButton` | `CalarmComponents.swift:51-61` |
| 13 | Shared toggle row wrapper | `SettingsSheet.swift` calendar toggles |
| 14 | Unify dismiss button styling (Done vs Cancel) | `SettingsSheet`, `EventDetailView`, `AlarmOffsetListPicker` |

## P2 — Polish & accessibility

| # | Change | Files |
|---|--------|-------|
| 15 | `ContentUnavailableView` for empty schedule + access prompt | `ScheduleView.swift` |
| 16 | Settings `.presentationDetents([.medium, .large])` | `SettingsSheet.swift` |
| 17 | VoiceOver labels on event rows | `ScheduleView.swift` EventRow |
| 18 | Tab bar accessibility traits | `CalarmComponents.swift` `SettingsTabBar` |
| 19 | Haptics on alarm toggle | `ScheduleView.swift` EventRow |
| 20 | Reduce Motion for tab animation | `SettingsTabBar` |
| 21 | Inline refresh indicator when list populated | `ScheduleView.swift` |
| 22 | Expand remove-alarm hit target to 44pt | `EventDetailView.swift` |
| 23 | Fix font token honesty | `CalarmFont.swift` — remove fake semibold names or add real weights |
| 24 | Single `@Environment(\.calarmTheme)` in EventRow | `ScheduleView.swift:390-392` |

## P3 — Nice to have

| # | Change |
|---|--------|
| 25 | Swipe actions on event rows (toggle alarm) |
| 26 | EventKit calendar color dot on events |
| 27 | iPad `NavigationSplitView` |
| 28 | Dynamic Type snapshot tests at AX sizes |
| 29 | Semantic colors in asset catalog |

## What works well (do not regress)

- Geist Pixel brand on wordmark, times, body copy
- `CalarmTheme` semantic color model + 8 user accents
- `SettingsOptionList` / `SettingsOptionRow` card vocabulary
- Per-controller nav bar theming (`CalarmNavigationStyle`) — no global UIKit appearance pollution
- Schedule UX: time column, bell targets, custom header
- Root theme injection in `CalarmApp`
- Accessibility identifiers for UI tests
- 16pt corner radius + stroke grouped card family

## File reference index

```
CalarmFont.swift              — typography tokens
CalarmTheme.swift             — colors + spacing constants
CalarmComponents.swift        — shared primitives, tab bar, settings rows
CalarmNavigationStyle.swift   — UIKit nav bar bridge
ScheduleView.swift            — main list, banners, EventRow
SettingsSheet.swift           — tabbed settings
EventDetailView.swift         — event detail + alarms
AlarmOffsetListPicker.swift   — offset picker sheet
```
