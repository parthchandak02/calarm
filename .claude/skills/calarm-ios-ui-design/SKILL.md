---
name: calarm-ios-ui-design
description: >-
  CALarm iOS UI consistency, HIG alignment, and design-system rules. Use when
  editing views, adding screens, polishing UX, or reviewing UI changes in
  Calarm/Views/, CalarmTheme, CalarmFont, or CalarmComponents.
---

# CALarm iOS UI Design

## Read this first

CALarm has a **pixel-branded alarm app** look: Geist Pixel wordmark + body, semantic
`CalarmTheme` colors, grouped bordered cards, and custom schedule chrome. New UI must
**extend existing tokens and components** — do not introduce one-off spacing, fonts, or
button styles.

Full prioritized backlog: [BACKLOG.md](BACKLOG.md)

---

## Brand vs native (CALarm rule)

| Use Geist Pixel (`CalarmFont`) | Use system SF / symbols |
|-------------------------------|-------------------------|
| Wordmark, screen titles, body copy, settings labels, schedule times | SF Symbol icons (toolbar, bells, empty-state heroes) |
| Section headers (uppercase + tracking) | `.monospacedDigit()` on countdowns/times |
| Tab bar labels, option rows | — |

**Do not** add fake weight tokens (`bodyMedium` == `body` today). Prefer real
`.weight(.semibold)` when hierarchy needs emphasis.

**Preserve:** custom schedule header, 78pt time column, 44pt bell toggle, NEXT capsule,
next-alarm banner — tune them to the grid, don't remove them.

---

## Design tokens (source of truth)

### Files

| File | Owns |
|------|------|
| `Calarm/Views/CalarmTheme.swift` | Colors, appearance, spacing constants |
| `Calarm/Views/CalarmFont.swift` | Geist Pixel scale |
| `CalarmShared/CalarmAccent.swift` | User accent palette |
| `Calarm/Views/CalarmComponents.swift` | Shared UI primitives |

### Spacing — use these, not ad hoc values

| Token | Value | Use |
|-------|-------|-----|
| `CalarmTheme.rowPaddingH` | 16 | Schedule list, banners, header |
| Screen horizontal (target) | **20** | Settings, event detail outer padding |
| Section gap | **28** | Between settings/event sections |
| Inline gap | **8–12** | Within rows and HStacks |
| `CalarmTheme.bellTapSize` | **44** | Minimum tap target for alarm bell |
| Minimum touch (all controls) | **44** | Toolbar icons, tab buttons, remove actions |

**Known inconsistency to fix, not extend:** schedule list inset is 16pt; settings rows
sit at 36pt (20 outer + 16 inner). New work should converge on **20pt screen edge** +
**16pt row inner** OR migrate schedule to match.

### Radii & surfaces

| Token | Value |
|-------|-------|
| `CalarmTheme.cornerRadius` | 16 — grouped cards, tab bar, option lists |
| `CalarmTheme.surfaceStroke` | 1pt border on grouped containers |
| Selected row tint | `theme.accent.opacity(0.10–0.12)` |
| Subtle accent banner | `theme.accent.opacity(0.08)` |

Add named theme opacities (`accentSubtle`, `accentSelected`) instead of new magic numbers.

### Colors — always via `CalarmTheme`

Never hardcode `.red`, `.orange` for status. Add semantic tokens:

- `destructive` — disconnect, remove alarm, past event
- `warning` — too soon, permission issues

Resolve theme once: `@Environment(\.calarmTheme)` at screen level. Avoid recomputing
via `themeStore.theme(colorScheme:)` in child rows.

---

## Component catalog (reuse before inventing)

| Component | Use for |
|-----------|---------|
| `CALarmWordmark` | Schedule header title |
| `ScheduleHeaderBar` | Schedule top chrome |
| `CalarmToolbarIconButton` | 44×44 toolbar actions (fix size if still 34) |
| `SettingsOptionList` | Bordered grouped card |
| `SettingsOptionRow` | Single-select option with checkmark |
| `SettingsSectionHeader` | Uppercase section label |
| `SettingsTabBar` | Settings tab navigation |
| `AccentColorDot` | Accent picker swatch |
| `AlarmOffsetListPicker` | Offset selection sheet |

**Extend these** for toggles, diagnostics rows, and event alarm rows — don't fork a
fourth row style.

---

## iOS HIG checklist (apply on every UI change)

### Navigation

- **Pushed views** → system back chevron. **No "Done"** on `navigationDestination` screens
  (`EventDetailView` today violates this).
- **Sheets** → trailing "Done" or "Cancel" in accent/`textSecondary` consistently.
- Root schedule may keep custom header; compensate with clear hierarchy and a11y headers.

### Touch targets

- All tappable icons: **≥ 44×44 pt** frame + `contentShape(Rectangle())`.
- Toolbar buttons: use shared `CalarmToolbarIconButton` at 44pt, not 34pt.

### Lists & settings

- Prefer extending `SettingsOptionList` / `Form` sections over manual `Divider` loops.
- One section header component for schedule day headers **and** settings sections.
- Event rows: `NavigationLink` or clear chevron for drill-in; group VO label
  (time + title + alarm state).

### Sheets

Every modal sheet must match `SettingsSheet` chrome:

```swift
.calarmNavigationStyle(theme: theme)
.calarmToolbarChrome(theme: theme)
.presentationBackground(theme.background)
.presentationDragIndicator(.visible)
// Consider: .presentationDetents([.medium, .large])
```

`AlarmOffsetSelectionSheet` is missing several of these today.

### Empty & loading states

- Use `ContentUnavailableView` + action button (themed), not one-off `VStack` heroes.
- Show refresh progress when reloading with existing list data.

### Accessibility

- Add `accessibilityIdentifier` for new interactive regions (`settings.tab.*`, `*.screen`).
- Selected rows: `.accessibilityAddTraits(.isSelected)`.
- Tab bar: tab traits / grouped labels.
- Respect `@Environment(\.accessibilityReduceMotion)` — skip tab animations when enabled.
- Optional: `.sensoryFeedback(.selection)` on alarm toggle and option pick.

### Information hierarchy

- **One** "next alarm" indicator at a time (banner OR row highlight OR NEXT chip — not all three).
- Stack permission/error banners with priority; don't compete with schedule content.

---

## UI change workflow for agents

1. **Read** affected view + `CalarmComponents.swift` + this skill.
2. **Reuse** existing components/tokens; if spacing differs from table above, align to target.
3. **Check HIG checklist** (navigation model, 44pt targets, sheet chrome, a11y).
4. **Avoid anti-patterns** (see BACKLOG.md § Anti-patterns).
5. **Verify** in light + dark + at least one non-orange accent.
6. **Do not** change unrelated screens in the same PR.

---

## Priority backlog (summary)

### P0 — feels non-native

1. Unify horizontal content inset (16 vs 36pt effective)
2. Event detail: back chevron instead of Done; `NavigationLink` on schedule rows
3. Enlarge toolbar controls to 44pt
4. Complete sheet chrome on all modals

### P1 — consistency

5. Single `SettingsSectionHeader` for schedule day headers
6. Named destructive/warning theme colors
7. Standardize row vertical padding (pick 12 or 14)
8. One primary/secondary/destructive button pattern (replace `.borderedProminent` outliers)
9. Consolidate next-alarm UI to one signal

### P2 — polish

10. Medium + large settings detents
11. Rich VoiceOver labels on event rows
12. Haptics on alarm toggle
13. Refresh indicator when list has data
14. Honest font tokens or real semibold weights

Details and file references: [BACKLOG.md](BACKLOG.md)

---

## Anti-patterns (never add)

- Ad hoc `.padding(.horizontal, 20)` without using a named screen inset constant
- New section header styling in a view file
- `.borderedProminent` on one screen and plain custom buttons elsewhere
- Hardcoded `.red` / `.orange` status colors
- 34pt toolbar hit areas
- "Done" on pushed navigation destinations
- Duplicate next-alarm indicators
- Manual divider stitching when `SettingsOptionList` or `Form` Section fits
- Second theme resolution path in child views

---

## AlarmKit / Island

- One compact Island Live Activity; multiple become minimal/stacked.
- Compact: icon + `monospacedDigit` countdown; avoid empty expanded regions stretching the pill.
- Lock Screen and Island must share the same expired/hide rule.
- Live Activities for defined start/end (hours not days).

Sources: Apple AlarmKit docs, Live Activities HIG, OSS samples (BleepingSwift, ADHDAlarms, alarmkit-patterns).

## Related skills

- `calarm-trust-diagnostics` — permission banners, test alarm, failure surfacing
- `calarm-live-activity-deep-links` — Dynamic Island / lock screen UI behavior
