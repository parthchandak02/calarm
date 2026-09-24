# Changelog

What changed, when, and why. Newest first.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project has
no public releases yet, so entries are grouped by **TestFlight build** rather than by
semantic version — the build number is the only identifier a tester can see, and it is
stamped into `CURRENT_PROJECT_VERSION` by `scripts/stamp-build-version.sh`.

Every entry names the commits behind it. Prefer reading the commit messages for detail;
this file exists so an agent can see the shape of the project's history without running
`git log` and reconstructing intent from subject lines.

**When you change something, add an entry here.** See [AGENTS.md](AGENTS.md) for the rule.

---

## Unreleased — 2026-09-24

### Changed

- **Alarms in the same minute ring once.** The same meeting reaches the app through several
  calendars under different titles — "Busy" from the `work account` free/busy share next
  to the titled invite, a flight from both Flighty and Gmail — so title-and-minute dedup never
  paired them, and each rang 2s after the last. `AlarmGrouping` now merges every alarm firing
  in the same minute into one AlarmKit alarm titled "First + N more"; titled events lead busy
  blocks. No event is hidden from alarming. The 2s collision stagger is gone. Each alarm's
  scheduled title is stored (`Key.alarmTitles`) so a group gaining a member reschedules.
- **The schedule hides a busy-only block when a titled event starts the same minute.** List
  only; the block still counts towards the grouped alarm. `ScheduleEvent.isBusyOnly` is new.

### Fixed

- A row whose reminder had passed said "Reminder passed" twice.

`CalarmTests/AlarmGroupingTests.swift` — 4 tests; `ScheduleEventSourcePolicyTests` — 3 more.

---

## Build 20260924.1039 — 2026-09-24

### Fixed

- **Every alarm rang twice, back to back.** When a meeting's occurrence ID changed — EventKit
  events swapped for their Google copies once Google sign-in returned events, the Focus Block
  Creator re-inserting an event, or a reload cancelled before `cancelRemoved` finished — the
  old AlarmKit alarm became an orphan, and `reconcileOrphanAlarms` kept every *future* orphan
  until it fired, alongside the new alarm for the same meeting. An orphan is now cancelled
  when a managed alarm fires within 30s of it; orphans at their own time are still kept, so
  a meeting briefly missing from a fetch still rings. The orphan pass also runs after each
  reschedule, once the replacement exists, and `cancelRemoved` no longer stops on task
  cancellation. `e2a1ad9` `CalarmTests/AlarmSchedulingHelpersTests.swift` — 2 tests.

---

## Build 20260923.1426 — 2026-09-23

### Added

- **Google Calendar sign-in is wired end to end.** iOS OAuth client "CALarm iOS" created in
  project `useful-field-497119-k5` (consent screen already *In production*, External, so no
  7-day token expiry; unverified, so a warning screen and a 100-user cap). The sign-in
  callback scheme — the missing `REVERSED_CLIENT_ID` in `CFBundleURLTypes` that meant sign-in
  had never completed — now comes from `$(GOOGLE_REVERSED_CLIENT_ID)`, set by the committed
  `Config/Calarm.xcconfig` and overridden by a gitignored `Config/Google.local.xcconfig`.
- `scripts/setup-google-oauth.sh <client plist>` installs the plist and writes that local
  xcconfig; run once per building Mac. `ship.sh doctor` warns when it has not been run.
  `3c3cea3`

### Fixed

- **Google calendars subscribed after first sign-in were hidden.** Same allow-list bug as the
  EventKit filter in build 1613; now a deny-list with a migration.
  `CalarmTests/GoogleCalendarPreferencesTests.swift` — 4 tests.

---

## Build 20260923.1106 — 2026-09-23

A phantom countdown: at 9:50 the lock screen counted down a 9:00 event toward 10:14:54, a
time with no event. No snooze was pressed, and no offset of a 9:00 event lands on 10:14:54;
the fixed fire date (8:59) *plus* the pre-alert does.

### Fixed

- **The Live Activity alarm rang late by its own pre-alert.** It was `.fixed(fireDate)` with
  `preAlert` = seconds until fire. Apple documents that as counting down *to* the fixed date;
  on device it behaved as counting down *from* it. It is now a countdown-mode alarm
  (`schedule: nil`), which starts now and rings after `preAlert` under either reading. This
  is also the likely root of the "stuck countdown" hours-late fires patched in `ea79c68`.
  `70fbe13`
- **Opening the app killed a real snooze.** Countdowns past their fire time were cancelled
  after 60s; the grace is now snooze length + 60s.
- **The Dynamic Island countdown was wider than needed.** Width now follows time remaining
  at render — 28pt under 10 min, 38pt under an hour, 58pt above. It still cannot shrink
  mid-countdown; AlarmKit does not re-render between state changes.

### Added

- Live Activity shows **"Starts 9:00 AM"**, or **"Snoozed · starts 9:00 AM"**, so a
  countdown that outlives its meeting explains itself.
- Paused Live Activity shows the time left instead of the bare word "Paused".
- iOS 27: a width-limited Island (landscape) shows an icon instead of digits.
- **Settings → Status → Alarm timing** reports when the 8-second test alarm actually rang
  (~8s on time, ~16s means iOS starts `.fixed` countdowns at the fixed date).
- `CalarmTests/CountdownPresentationTests.swift` — 8 tests.

### Changed

- The iOS 27 width-limited check compiles only under Swift 6.4. The release Mac runs Xcode
  26.6, whose SDK lacks it, and the first ship attempt failed its Release build. `a57d5f2`
- `ship.sh beta` runs the unit tests once. The `| xcbeautify || xcodebuild test` fallback
  re-ran the suite whenever xcbeautify was missing — which it is on the release Mac — or a
  test failed.

### Removed

- The widget's `isActivityExpired` check. It read the clock only at render, and Live
  Activities have no timeline, so it could never hide anything on time.

---

## Build 20260922.1613 — 2026-09-22

Two user-reported bugs, both found to have real causes rather than cosmetic ones.

### Fixed

- **The per-calendar filter hid calendars it had never seen.** It stored an *allow-list*,
  so a calendar subscribed after the list was written — or one whose EventKit identifier
  changed on an account resync — was absent from the list and silently excluded from the
  schedule. Now stores the calendars you switch *off*, with a migration that inverts any
  existing allow-list. Anything unrecognised defaults to visible. `d5bbb47`
- **The Dynamic Island countdown stretched the pill.** The compact region asked for a flat
  58pt regardless of format; `m:ss` needs 38pt, so the digits sat ~31pt short of the pill's
  right edge. Width is now derived from the format, and the format from the countdown's
  *total* duration rather than the time remaining at render — the widget body renders once
  and the system animates the digits from there. `17b9a00`

### Added

- Settings → Calendar reports how many calendars are switched off and offers a one-tap
  reset. The Events-loaded diagnostic reports enabled-of-total (`4/9 cals`). `d5bbb47`
- `CalarmTests/CalendarFilterPreferencesTests.swift` — 6 tests covering the deny-list
  semantics and the allow-list migration, including the case where EventKit has not
  answered yet. `d5bbb47`

---

## Build 20260922.1501 — 2026-09-22

Deploy-pipeline repair. Three separate defects, all with the same signature: a green
success message and a build that reached no tester.

### Fixed

- **`release.sh` exited non-zero after a successful upload.** `find build/export` fails
  under `set -euo pipefail` when the directory does not exist — and with
  `destination: upload` xcodebuild writes no IPA, so it never does. The script died before
  reaching the branch that handles exactly that case, taking every chained step with it.
  `6b879ff`
- **`ship.sh beta` used the broken path.** It called `fastlane ios upload_beta`, which
  builds through gym; gym never received the App Store Connect API key auth that
  `release.sh` passes to xcodebuild, so it failed with *No Accounts / No signing
  certificate iOS Distribution*. Now calls `./release.sh`. `6b879ff`
- **Group assignment raced App Store Connect processing.** `asc builds add-groups --latest`
  resolves to the newest *processed* build, which right after an upload is the previous
  one — so it re-assigned an already-distributed build and stranded the new one. Now polls
  for the stamped `CURRENT_PROJECT_VERSION` before assigning. `08ecf1c`
- **EventKit events vanished when Google returned nothing.** `reload()` suppressed mirrored
  EventKit events whenever Google was merely *connected*, so a Google fetch that silently
  returned nothing emptied the schedule. Suppression now requires Google to have actually
  returned events. `b08db48`
- **The settings tab bar squared off its own rounded corners.** The selected tab painted an
  unclipped rectangle inside a 16pt rounded container. `8a2d0e1`

---

## Build 20260922.1332 — 2026-09-22

### Added

- **Alarm journal.** Records intended versus actual fire times so alarm reliability can be
  measured rather than guessed at — the instrumentation Gate 1 in
  [STATUS.md](STATUS.md) depends on. Writes to both `os.Logger`
  (`subsystem: com.calarmapp.calarm`, `category: alarmjournal`) and UserDefaults.
  `CalarmShared/AlarmJournal.swift` is a pure reconciler with 10 tests; the IO side is
  `Calarm/Services/AlarmJournalStore.swift`. Reconciles on launch, because `alarmUpdates`
  is in-process and cannot observe a fire that happened while the app was dead. `ab95c17`
- **`preAlert: 1` on alarms without a Live Activity.** A one-second pre-alert, and not a
  cosmetic one: AlarmKit alarms fail to present when the foregrounded app is in landscape,
  and Apple's own Reminders works around it the same way. `2281589`
- `HANDOFF.md` and `PLAN.md` — architecture research, since merged into
  [RESEARCH.md](RESEARCH.md). `493b682`

### Fixed

Five calendar sync bugs in one commit (`443feec`) — each is written up with its evidence in
[RESEARCH.md § Fixed and verified](RESEARCH.md#fixed-and-verified):

- Background sync was registered too late to exist. `BGTaskScheduler` handlers must be
  registered before `didFinishLaunchingWithOptions` returns; registration happened from a
  SwiftUI `.task`. The 6am and hourly syncs were written correctly and had **never been
  installed**.
- The same meeting could produce two alarms when a Google account was added to iOS as a
  generic CalDAV entry.
- The incremental Google sync was structurally undefined — its sync token was minted from a
  request carrying parameters Google forbids alongside a `syncToken`.
- Every calendar ID was double percent-encoded, which broke every Google holiday calendar.
- Focus blocks would have fired alarms. `eventType` was decoded nowhere.

---

## Build 20260821.2037 — 2026-08-21

### Fixed

- Stale AlarmKit alarms firing hours after their events. `ea79c68`
- Calendar color hex byte rounding in a unit test. `6965b69`

### Added

- Optional calendar-color tint for the Live Activity and Dynamic Island. `09dc63e`

---

## 2026-08-19

### Fixed

- AlarmKit reschedule races and stale Dynamic Island countdown UX. `c25e229`

### Changed

- TestFlight ship skips Simulator boots on this Mac (RAM constraint). `96ceb3a`

---

## 2026-08-13

### Added

- **Google Calendar direct sync** with EventKit merge — the architectural choice that
  [RESEARCH.md](RESEARCH.md) later found Fantastical also made, and every indie competitor
  did not. `85fff46`, `dfb0e93`
- Agent skills, then under `.cursor/skills/` — moved to `.claude/skills/` on 2026-09-22. `dfb0e93`

---

## 2026-08-12

### Fixed

- Alarm persistence, Dynamic Island theme, countdown sizing. `8a52a86`
- Stacked countdown notifications. `4ddb51e`

---

## 2026-07-26

### Added

- Alarm scheduling fixes, the release pipeline, and the first Cursor skills. `af0d149`

---

## 2026-07-03

### Added

- App Store publishing scaffold, screenshot automation, GitHub Pages. `571cf69`, `449a4b8`
- Durable local preferences via `CalarmPersistence`. `f671987`

### Security

- Git history purged of personal data; `SECURITY.md` added. `e985c69`, `83fbe1c`

### Changed

- Bundle ID switched to `com.calarmapp.calarm`. `8e0a7ce`

---

## 2026-06-30

### Added

- Initial app: AlarmKit alarms with Live Activities. `171d7bd`
