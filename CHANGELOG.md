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

## Unreleased — 2026-09-25

### Added

- **First-run tips.** New installs get Apple TipKit tips that point at the real controls,
  one at a time: arm square → tap a row → bell → gear, plus an inline tip on the calendar
  access screen. Each tip disappears once its action is done (or on its ×). Anyone who has
  used CALarm before (a permission already asked, Google connected, or any saved preference)
  skips them. **Settings → Show tips again** brings them all back without a relaunch.
  Styled with CALarm's fonts and theme (`Calarm/Views/CalarmTips.swift`).

- **The Live Activity now appears only shortly before each alarm** (Settings → Alarms →
  *Island · min before ring*: ALL / 10 / 5 / 2, default 5). Every upcoming alarm gets its own
  window instead of the next one counting down for hours: it is scheduled `.fixed(ring − L)`
  with a pre-alert of L, which on device starts the card at ring − L and rings at the ring
  time (`CalarmShared/LiveActivityWindow.swift`). Windows are clipped to the previous ring so
  cards never overlap. ALL keeps the old behaviour exactly. On a device that follows Apple's
  documented timing instead, alarms would ring L early, never late; the test alarm measures
  which (it now rings at ~16s with a lead set, *Early · 8s* if the device follows the docs).

### Changed

- **The alarm permission prompt waits for the first armed alarm**, not app launch. The arm
  tip explains it first. Any reschedule with an armed event (bulk arm, event detail, a default
  offset) and the test alarm also ask, so no armed alarm is left without permission.
- **Vibrate means vibrate only: the ringing fallback is gone.** Owner's rule: exactly one ring
  per chosen offset (an event at 12:45 with −1m rings at 12:44 only). The fallback a minute
  after an undismissed vibration was a second ring, and it could ring after a dismiss: while
  vibrating, a just-fired alarm still anchored it, and a reschedule in that minute re-created it
  after the stop intent had cancelled it. Every reconcile now cancels fallbacks left by earlier
  builds, including those of events no longer listed; the stop and snooze intents still cancel
  them for one release.

### Fixed

- **Snoozing could silently cancel the snooze**, in ring mode too. A snoozed alarm is no longer
  in the upcoming schedule, so the app's AlarmKit observer cancelled it as undesired. The snooze
  intent now records when the snooze ends (`Key.snoozedUntil`), and cleanup holds the alarm
  until 60s after that, so a second snooze survives too (keyed to the first ring it was
  cancelled at 9:06 after a 9:00 ring). A ringing alarm is held five minutes past the ring or
  the snooze it follows, and a short event no longer ends its own snooze or ring
  (`AlarmSchedulingHelpers.shouldEndWithEvent`).
- **A missing stored ring time made cleanup read a window's card time as its ring time** and
  cancel it early. The fallback reading is now fixed date + pre-alert, and stored ring times are
  no longer pruned when reading AlarmKit's alarms throws.
- **A forced reschedule under a second before an alarm cancelled it** without replacing it; the
  too-soon check now comes first.
- **An alarm that already rang is not re-armed for the same fire date** (`Key.rangFireDates`),
  so if a device follows Apple's documented timing a window alarm rings early once, not twice.
- **Live Activity digits drifted off their tiles and truncated (`44:5…`).** Geist Pixel's
  digits are proportional (a `4` is 40% wider than a `1`) with no tabular figures, and the
  system draws the timer as one string. The Lock Screen and expanded Island digits are now SF
  Mono (owner's pick); labels stay pixel. Cells size from the widest digit, rounded up.
- **The compact Island was wider than Apple's 230pt compact width at 10 min or more left.** The
  compact timer drops its tiles and tracking and sits 2pt from the camera. iOS widens the
  leading side to match the trailing, so each point saved there saves ~1.75pt of pill.
  Simulator harness: dropping tiles measured 237 → 225pt at 45 min; the margin change is unmeasured.
- **A failed read of AlarmKit's alarms made the reschedule cancel and recreate everything**,
  ringing alarms included. It now leaves them armed and reports a failure so it retries.
- **A snooze recorded the setting's length, not the alarm's**, so changing the snooze while an
  alarm rang made cleanup cancel the snooze before it re-rang.

## Build 20260924.2243 — 2026-09-24

### Changed

- **The next-alarm countdown flips like a real split-flap board.** Each tile is two halves:
  the old top half falls forward on the midline hinge and the new bottom half lands with a
  small settle, darkening as each turns edge-on (500 ms, `FlipTile`). Reduce Motion swaps
  without motion. Tuned by the owner in `notes/ui-redesign/flip.html`.
- **Live Activity tiles look mechanical when still:** a lighter upper flap, a darker lower
  one, a hinge gap and a drop shadow. They cannot flip: iOS ticks the timer text itself.

### Fixed

- **The Live Activity countdown was blank on device.** In build 2129 the Lock Screen card was
  an empty black box and the compact Island showed no time while counting down or paused;
  only the ringing state drew. `FlapTimer` set its font with `Font(UIFont)`, which the
  widget renderer does not draw; it now uses `.custom`, as every view that rendered does.
- **The compact Island stretched into a long pill.** `FlapTimer` gave the timer text
  `.fixedSize()`, and timer text asks for the width of the longest value it could show. It is
  now framed to its tiles' exact width, as the pre-2129 countdown was. Regression from 241078d.
  The compact Island's leading side is the lit square instead of the title, which cost ~64pt
  and truncated anyway (owner's call).

## Build 20260924.2129 — 2026-09-24

### Changed

- **The Live Activity and Dynamic Island are a flight board.** The countdown is Geist Pixel
  digits on split-flap tiles with HRS / MIN / SEC under them on the Lock Screen, pixel labels
  (`STANDUP · 9:00 AM`, `RINGS 8:50 AM`, `SNOOZED`, `PAUSED`), a black card, the title in the
  compact Island and a lit square as the minimal Island. The widget now bundles its own copy
  of the font. Option B of three mocked in the owner's `notes/ui-redesign/live-activity.html`.

## Build 20260924.2104 — 2026-09-24

### Changed

- **The next-alarm countdown is a full flight board**, `DD:HH:MM:SS` with DAYS / HRS / MIN /
  SEC under each pair, flipping every second (was `MM:SS` or `H:MM` with a unit).
- **Day headers pop:** white pixel text on a flap tile, a size below the countdown.
- **Settings is tinted** with a wash of the accent from the top, so it reads as a different
  place from the schedule. The nav bar is transparent there so the wash runs under it.

### Fixed

- **Screenshot mode lost its demo schedule** a beat after launch: the real calendar status
  arrived and replaced the faked full access, and foregrounding reloaded real (empty) data.

## Build 20260924.2036 — 2026-09-24

### Changed

- **Settings is a departure board.** The custom four-tab bar is gone. Settings opens at half
  height on four lines that show their current state: *Alarms −10m · 5m · ring*, *Calendars
  3 of 5 · Google*, *Look*, and *Status all good / N issues*. Each pushes to its own page:
  - **Alarms:** flap tiles replace ~15 list rows, with a plain-English summary sentence.
  - **Calendars:** one line per calendar with the lit square and its upcoming event count.
  - **Look:** a live row and Island preview, accent squares, and appearance tiles.
  - **Status:** an activity log, newest first: `RESCHED`, `SYNC`, `RANG`, `SNOOZED`,
    `DISMISSED`, `FOCUS`, `TEST`, `FAIL`. Current problems are pinned on top as `NOW` lines
    with their fix, and the raw checks are one dim line at the bottom. The log is new
    (`ActivityLog`, on-device only, 7 days, repeats within 10 minutes collapse). The owner
    picked it over the verdict layout.
  The 8-second test alarm sits on the root and Status. Chosen from options mocked in the
  owner's `notes/ui-redesign/settings.html` (2026-09-24).

### Fixed

- **iOS calendar colours were never read.** `CalendarSummary.colorHex` held a description of
  the colour components rather than a hex string; it now uses `CalendarColor.hexString`.

---

## Build 20260924.1948 — 2026-09-24

### Changed

- **The schedule is a departure board.** One split-flap countdown to the next ring replaces
  the banner, NEXT capsule and tinted row that all said the same thing. Each event is one line
  (time, title in SF Mono, short offset like `−10m`, a lit square that glows when armed, with a
  haptic). Day headers read `TODAY · WED 24`; started events dim. Toolbar buttons are Liquid
  Glass. Chosen from five directions (owner, 2026-09-24).
- **The default accent is amber `#FFB000`** (was orange); Amber moved first in the picker.
  A chosen accent is kept.

### Fixed

- **Switching every iOS calendar off read all of them.** `filteredCalendars()` fell back to
  "every calendar" when nothing was left on, so with all 20 off the phone still loaded 37
  EventKit events and could ring for calendars the owner had turned off. All off now reads
  none, as the switches say.
- **The test alarm rang at ~16s instead of 8s.** It was deliberately `.fixed` plus a pre-alert
  to probe AlarmKit's timing; the device has answered (*Late · 16s*, RESEARCH.md), so it now
  uses countdown mode like the Live Activity alarm and rings on time.
- **RESEARCH.md's whole AlarmKit section had been deleted** by the edit that removed the
  employer section (`858f891`), a slice that ran to the wrong `---`. Restored.

---

## Build 20260924.1743 — 2026-09-24

### Changed

- **The ship script is generic.** `scripts/ship-on-mini.sh` is now `scripts/ship-testflight.sh`:
  it runs on any Mac holding the signing identity, at the Mac or over SSH, and unlocks the
  keychain only when needed (always over SSH). The owner's machine and exact command live in
  one place, AGENTS.md § Owner's setup.
- **History rewritten (force-pushed 2026-09-24).** Old revisions no longer carry the ASC key
  ID, tester-group ID, `/Users/…` paths, the work email, or employer policy and tool names
  (those lines read `[redacted]`); every commit is authored and committed by the owner's
  personal address. **All commit hashes changed**; the ones quoted in this file were remapped.
  Details and how to update a clone: SECURITY.md. The employer notes moved to the gitignored
  `notes/`.
- **No personal values in scripts.** The ASC key ID default in `configure-credentials.sh`
  (now discovered from `~/Keys/AuthKey_*.p8`), the tester-group ID default in
  `add-testflight-internal-group.sh` (now required from `fastlane/.env`), the team ID in
  `.env.example`, and `/Users/...` paths in the icon scripts and two docs are gone.

---

## Build 20260924.1518 — 2026-09-24

A three-way audit (docs, code review, build/config) after the day's builds.

### Fixed

- **The vibrate fallback was cancelled the moment its vibration started.** Desired alarms
  were built from future fire times only, so once the vibrating alarm fired, its fallback was
  "undesired" and the reconcile its own alerting triggered cancelled it. Alarms that fired
  within the last minute now still anchor their fallback (`AlarmSoundPolicy.fallbackFireDate
  (anchor:upcomingFireDates:now:)`).
- **Snoozing a vibrating alarm left the post-snooze vibration with no fallback.**
  `SnoozeAlarmIntent` now moves the fallback to snooze end + 60s
  (`AlarmScheduler.moveFallbackAfterSnooze`), and reconcile leaves a fallback alone while its
  vibrating alarm is ringing or snoozed.
- **An orphan could be cancelled against an alarm that would never ring.** The duplicate check
  counted fallbacks and alarms about to be cancelled; it now counts desired primaries only.
- **A Focus change could be lost to suspension.** `applyFocusVibrate` awaits the reschedule.
- **The list could hide the busy block responsible for an alarm** when its titled twin had
  alarms off. It now stays unless the twin also rings.
- Settings → Status showed "Unknown" for a calendar permission not yet asked.
- `ship.sh all` still used the broken fastlane `upload_beta` lane; it now uses `release.sh`.
- `ship-remote.sh` rebases the stamp commit before pushing, so a push to `main` during the
  build no longer strands the mini.
- **Shipping is one command, `ssh -t macmini-remote '~/projects/calarm/scripts/ship-on-mini.sh'`.** `scripts/ship-on-mini.sh` updates
  itself from `main`, prompts for the keychain, ships, waits for `IN_BETA_TESTING` in ASC before recording anything, and `scripts/record-build.sh`
  writes the build into STATUS and CHANGELOG, so no agent follow-up is needed. Timed steps,
  full log in the mini's `build/logs/`. The short-lived local wrapper `scripts/ship-remote.sh`
  is gone.

### Added

- Privacy manifest declares `SystemBootTime` (`35F9.1`) for the alarm journal's
  `systemUptime`.
- `reference-photos/` is gitignored.

### Removed

- All ten `origin/cursor/*` branches (2026-08-12..21), at the owner's request; `main` is the
  only branch. Nine held unmerged commits, unreviewed. Final tips, for recovery while GitHub
  still has the objects: `alarm-persistence-countdown-fix-b61b` 052ad9f, `calendar-live-activity-color-ece7` 09dc63e, `consolidated-release-86bd` 0779934, `dynamic-island-width-fix-597e` 4aef4e7, `google-calendar-sync-b61b` 4cdedbf, `ios-ui-design-skill-597e` 0b4e1f3, `p0-ui-fixes-b7e6` 0779934, `review-fixes-ece7` 9ab74c3, `settings-tabs-design-597e` c64e210, `testflight-ship-aec2` 3ec54e6.

### Changed

- Docs and skills brought in line with the day's code: the ship flow is
  `scripts/ship-on-mini.sh`, orphan and signature semantics, vibrate-mode known problems,
  Google sign-in confirmed on device.

`CalarmTests` — 102 passing (4 new).

---

## Build 20260924.1447 — 2026-09-24

### Added

- **Vibrate instead of ringing.** Settings → Alarms → Alarm sound, or automatically while a
  chosen Focus is on (Settings → Focus → a Focus → Focus Filters → CALarm, via
  `CalarmFocusFilter`). A vibrating alarm uses the bundled silent sound
  `calarm-silence.caf`; AlarmKit has no vibrate-only option. **A ringing fallback follows one
  minute later** unless the vibration is dismissed or snoozed (the stop and snooze intents
  cancel it by `AlarmSchedulingHelpers.fallbackAlarmID`). A fallback that would land on
  another alarm's minute is dropped; that alarm's own fallback covers it. The test alarm uses
  the current sound mode, so it doubles as the vibration check.
  `CalarmTests/AlarmSoundPolicyTests.swift` — 4 tests. `73032a3`

---

## Build 20260924.1342 — 2026-09-24

### Changed

- **Alarms in the same minute ring once.** The same meeting reaches the app through several
  calendars under different titles — "Busy" from the work calendar's free/busy share next
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
`e4e9434`.

### Changed (tooling)

- Ship with `./scripts/ship-remote.sh`, which commits the build stamp to `main` (`a4d6f47`).
  Stamps: 1342 `2ae2fb7`, 1447 `a2b14bd`.

---

## Build 20260924.1039 — 2026-09-24

Stamp not committed to `main`; this build predates `ship-remote.sh`.

### Fixed

- **Every alarm rang twice, back to back.** When a meeting's occurrence ID changed — EventKit
  events swapped for their Google copies once Google sign-in returned events, the Focus Block
  Creator re-inserting an event, or a reload cancelled before `cancelRemoved` finished — the
  old AlarmKit alarm became an orphan, and `reconcileOrphanAlarms` kept every *future* orphan
  until it fired, alongside the new alarm for the same meeting. An orphan is now cancelled
  when a managed alarm fires within 30s of it; orphans at their own time are still kept, so
  a meeting briefly missing from a fetch still rings. The orphan pass also runs after each
  reschedule, once the replacement exists, and `cancelRemoved` no longer stops on task
  cancellation. `78b1a08` `CalarmTests/AlarmSchedulingHelpersTests.swift` — 2 tests.

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
  `4cd7e9f`

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
  is also the likely root of the "stuck countdown" hours-late fires patched in `813c3cb`.
  `2a44b76`
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
  26.6, whose SDK lacks it, and the first ship attempt failed its Release build. `4261c91`
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
  existing allow-list. Anything unrecognised defaults to visible. `b04f698`
- **The Dynamic Island countdown stretched the pill.** The compact region asked for a flat
  58pt regardless of format; `m:ss` needs 38pt, so the digits sat ~31pt short of the pill's
  right edge. Width is now derived from the format, and the format from the countdown's
  *total* duration rather than the time remaining at render — the widget body renders once
  and the system animates the digits from there. `dd6d82c`

### Added

- Settings → Calendar reports how many calendars are switched off and offers a one-tap
  reset. The Events-loaded diagnostic reports enabled-of-total (`4/9 cals`). `b04f698`
- `CalarmTests/CalendarFilterPreferencesTests.swift` — 6 tests covering the deny-list
  semantics and the allow-list migration, including the case where EventKit has not
  answered yet. `b04f698`

---

## Build 20260922.1501 — 2026-09-22

Deploy-pipeline repair. Three separate defects, all with the same signature: a green
success message and a build that reached no tester.

### Fixed

- **`release.sh` exited non-zero after a successful upload.** `find build/export` fails
  under `set -euo pipefail` when the directory does not exist — and with
  `destination: upload` xcodebuild writes no IPA, so it never does. The script died before
  reaching the branch that handles exactly that case, taking every chained step with it.
  `bc2f4cb`
- **`ship.sh beta` used the broken path.** It called `fastlane ios upload_beta`, which
  builds through gym; gym never received the App Store Connect API key auth that
  `release.sh` passes to xcodebuild, so it failed with *No Accounts / No signing
  certificate iOS Distribution*. Now calls `./release.sh`. `bc2f4cb`
- **Group assignment raced App Store Connect processing.** `asc builds add-groups --latest`
  resolves to the newest *processed* build, which right after an upload is the previous
  one — so it re-assigned an already-distributed build and stranded the new one. Now polls
  for the stamped `CURRENT_PROJECT_VERSION` before assigning. `e137a14`
- **EventKit events vanished when Google returned nothing.** `reload()` suppressed mirrored
  EventKit events whenever Google was merely *connected*, so a Google fetch that silently
  returned nothing emptied the schedule. Suppression now requires Google to have actually
  returned events. `285da3f`
- **The settings tab bar squared off its own rounded corners.** The selected tab painted an
  unclipped rectangle inside a 16pt rounded container. `fe1b498`

---

## Build 20260922.1332 — 2026-09-22

### Added

- **Alarm journal.** Records intended versus actual fire times so alarm reliability can be
  measured rather than guessed at — the instrumentation Gate 1 in
  [STATUS.md](STATUS.md) depends on. Writes to both `os.Logger`
  (`subsystem: com.calarmapp.calarm`, `category: alarmjournal`) and UserDefaults.
  `CalarmShared/AlarmJournal.swift` is a pure reconciler with 10 tests; the IO side is
  `Calarm/Services/AlarmJournalStore.swift`. Reconciles on launch, because `alarmUpdates`
  is in-process and cannot observe a fire that happened while the app was dead. `c157712`
- **`preAlert: 1` on alarms without a Live Activity.** A one-second pre-alert, and not a
  cosmetic one: AlarmKit alarms fail to present when the foregrounded app is in landscape,
  and Apple's own Reminders works around it the same way. `12f570c`
- `HANDOFF.md` and `PLAN.md` — architecture research, since merged into
  [RESEARCH.md](RESEARCH.md). `f56eb6c`

### Fixed

Five calendar sync bugs in one commit (`efc14bd`) — each is written up with its evidence in
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

- Stale AlarmKit alarms firing hours after their events. `813c3cb`
- Calendar color hex byte rounding in a unit test. `b123216`

### Added

- Optional calendar-color tint for the Live Activity and Dynamic Island. `58f9ccc`

---

## 2026-08-19

### Fixed

- AlarmKit reschedule races and stale Dynamic Island countdown UX. `543c2f5`

### Changed

- TestFlight ship skips Simulator boots on this Mac (RAM constraint). `dec2f5e`

---

## 2026-08-13

### Added

- **Google Calendar direct sync** with EventKit merge — the architectural choice that
  [RESEARCH.md](RESEARCH.md) later found Fantastical also made, and every indie competitor
  did not. `1379e64`, `8fd5fb8`
- Agent skills, then under `.cursor/skills/` — moved to `.claude/skills/` on 2026-09-22. `8fd5fb8`

---

## 2026-08-12

### Fixed

- Alarm persistence, Dynamic Island theme, countdown sizing. `3dd20aa`
- Stacked countdown notifications. `693c86f`

---

## 2026-07-26

### Added

- Alarm scheduling fixes, the release pipeline, and the first Cursor skills. `5256d47`

---

## 2026-07-03

### Added

- App Store publishing scaffold, screenshot automation, GitHub Pages. `adb6b65`, `f933f26`
- Durable local preferences via `CalarmPersistence`. `f671987`

### Security

- Git history purged of personal data; `SECURITY.md` added. `e985c69`, `4e15b00`

### Changed

- Bundle ID switched to `com.calarmapp.calarm`. `8553176`

---

## 2026-06-30

### Added

- Initial app: AlarmKit alarms with Live Activities. `171d7bd`
