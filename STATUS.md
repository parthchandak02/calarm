# Status: where the project stands and what comes next

**Last updated: 2026-09-24** — update this date whenever you change this file.

This is the living "pick up where the last agent left off" document. If you are starting a
session, read this first, then [AGENTS.md](AGENTS.md) for the working rules.

- Durable findings and sources: [RESEARCH.md](RESEARCH.md)
- What changed and when: [CHANGELOG.md](CHANGELOG.md)

---

## Right now

| | |
|---|---|
| **Branch** | `main`, pushed; the only branch in use. Untracked `reference-photos/` is gitignored |
| **Latest build** | `20260924.1447` — `VALID`, `IN_BETA_TESTING` (vibrate mode). `main` is ahead of it with the audit fixes below, unshipped |
| **Tests** | 102 passing (`CalarmTests`, 2026-09-24) |
| **Doctor** | 0 warnings |
| **Google sync** | **Working on device.** Signed in on the phone as the personal account (2026-09-24); returns events, including `work account` busy blocks via a free/busy share. Plist + `Config/Google.local.xcconfig` are local on this Mac and `macmini-remote` |
| **Backend** | None. No Worker, no relay deployed |

The app is installable from TestFlight and works off EventKit alone. Everything in
[The plan](#the-plan) below is about making it *trustworthy*, not about making it work.

---

## Waiting on the owner

**Ship the audit fixes.** `main` carries fixes found on 2026-09-24 that matter for vibrate
mode — above all, the ringing fallback was cancelled the moment its vibration started
whenever CALarm was resident. Ship before relying on vibrate mode.

**Verify vibrate mode on device (after that ship).** Turn on Settings → Alarms → Vibrate
instead of ringing, then Settings → Status → Test alarm. It should vibrate with no sound (the
test alarm has no fallback). Then leave a **real event's** vibrating alarm undismissed: a
normal ring should follow a minute later. Snooze one: a ring should follow a minute after the
snooze ends if that is missed too. If the test
alarm makes a sound or stays silent without vibrating, the silent-sound approach fails on this
iOS version (see RESEARCH.md § Alarm sound and vibration).

**Confirm one ring per minute (build 20260924.1342+).** After installing, open CALarm once. A minute with
several events (e.g. 1:00 PM "Busy" + "Meeting Free Block") should ring once, titled
"<event> + N more", and the list should no longer show a "Busy" block next to a titled event
at the same time.

**Test the Focus filter with CALarm force-quit.** Add CALarm to a Focus, force-quit the app,
turn the Focus on, and fire the next alarm. If it rings instead of vibrating, the Focus change
did not reach a terminated app (RESEARCH.md § Known problems) — expected, but confirm.

[redacted]
through the personal Google account. The owner chose to keep it on and check policy
themselves (2026-09-24). Do not file anything for them.

*Older items below are from builds 1106–1613 and have not been confirmed done.*

**0. Measure AlarmKit's countdown timing (build 20260923.1106 or later).** Keep CALarm open,
tap **Settings → Status → Test alarm**, and read **Alarm timing**. *On time · 8s* means iOS
follows Apple's docs and the phantom 9:00→10:14 countdown needs another explanation;
*Late · 16s* confirms iOS starts `.fixed` countdowns at the fixed date, which the new
countdown-mode Live Activity alarm already sidesteps. (Already strongly indicated: the 8:59
alarm on 2026-09-23 never rang — see RESEARCH.md.) Either way, record it in RESEARCH.md.
Then watch the next real alarm: the lock-screen card should read *Starts <time>* and ring on
time.

**1. Confirm the calendar fix.** Build 1613 changed the per-calendar filter from an
allow-list to a deny-list. The previous build reported `ek 40 · google off · 4 cals`,
meaning the filter was cutting the schedule down to 4 calendars. Open **Settings →
Calendar**; if calendars are switched off, tap **Turn all calendars back on**. Then
**Settings → Status → Events loaded** should read something like `ek 78 · google off ·
all 9 cals`.

If a calendar is still missing after that, it is a different cause — most likely it holds
only all-day events, which the app skips by design.

**2. Confirm the Dynamic Island fix.** Fire the 8-second test alarm on the phone. The
countdown should sit against the right edge of the pill. This could not be verified on this
machine: the app blocks test alarms on Simulator, and the Simulator app is missing from
this Xcode install.

**3. Gate 1 data is accumulating.** The alarm journal has been recording since build 1332
(2026-09-22). Retrieve it with:

```bash
log show --predicate 'subsystem == "com.calarmapp.calarm" AND category == "alarmjournal"' --last 7d --info
```

---

## The plan

Three gates, in order. **Each can invalidate an entire branch of the work**, which is why
they come before more code. The evidence behind each is in [RESEARCH.md](RESEARCH.md).

### Gate 1 — Does AlarmKit fire reliably on this phone? (BLOCKING)

The dominant risk. A production dataset of ~13,000 firings shows 10–15% landing in the
wrong window, and the late-firing report covers iOS 27.0 RC.

Harness: arm ~10 alarms across a day and **overnight on a locked, uncharged phone** — the
condition every report points at. The alarm journal (shipped in build 1332) records
intended versus actual.

Constraints the harness must respect, all discovered in research:

- `alarmUpdates` is **in-process**. It cannot observe a fire on a phone where calarm has
  been killed since midnight. Reconcile **on next launch**, which `AlarmJournalStore` does.
- `try? AlarmManager.shared.alarms` **cannot distinguish "framework broken" from "nothing
  scheduled"**. Hence the durable intent ledger.
- AlarmKit **silently deletes spent one-shot alarms**. Disappearance is normal, not a miss.
- AlarmKit **rejects `schedule` for a UUID it already holds** — cancel before re-scheduling.
- **Cancelling a ringing alarm silently ends the wake-up**, so a naive "reconcile everything
  on launch" pass is dangerous — launch-during-ringing is a likely state.
- `maximumLimitReached` is real. Budget alarm slots.

Check two cheap unknowns in the same run: whether any alarm armed *before* the iOS 27
upgrade is silently dead (FB21273655), and AlarmKit's practical scheduling horizon and
concurrent-alarm ceiling. Beacon shipped *"improved alarm persistence for events further
than 1 month away"*, so a real horizon problem exists.

- **Fires reliably** → proceed. Freshness is the real problem and the plan holds.
- **Reproduces** → stop and fix the alert layer first. `preAlert: 1` is already shipped;
  next would be verifying the widget extension's entitlements, then a redundant pre-alarm
  notification. Sync work moves to the back.

**No open-source project computes `actualFireDate − intendedFireDate`. Gate 1 is original
work.**

### Gate 2 — Can a Notification Service Extension arm an alarm while the app is dead? (~1 afternoon)

Compile-time is proven clear — there are zero `iOSApplicationExtension, unavailable` markers
in AlarmKit's interface, and a real `schedule()` call typechecks under
`-application-extension`. Three runtime questions remain:

1. Does `AlarmManager.shared.schedule()` succeed inside an NSE? Distinguish **throws**,
   **silently no-ops**, and **works** — watch Console for `alarmd`, `apsd`, and the
   extension process.
2. Does `authorizationState` resolve for an extension caller? `NSAlarmKitUsageDescription`
   lives in the *app's* Info.plist. If the NSE reports `.notDetermined` while the app
   reports `.authorized`, the path is dead.
3. Same two questions for the **widget extension**, which given AlarmKit's structural
   coupling to a widget may be the intended call site.

Prerequisite: **App Groups**, since a shared container is the only sanctioned NSE↔app IPC.
Set file protection to `.completeUntilFirstUserAuthentication` or container writes fail on a
cold-booted locked phone.

- **Yes** → complete solution; a calendar change re-arms alarms with the app never opened.
- **No** → the visible push still delivers a tappable "your schedule changed" banner and the
  app re-arms on tap. Most of the value, a fraction of the work.

### Gate 3 — Stand up the Worker and measure edit-to-buzz (~2 hrs)

Single-tenant Worker, personal Google account. **First action, before any code:** one
`events.watch` call against a `*.workers.dev` URL, to settle whether Google accepts it.

Then measure the full chain — calendar mutation → webhook → OAuth refresh → `events.list` →
JWT sign → APNs → device — and confirm <60s. **Log each hop separately**, since the two
Google round trips are the suspect, not the webhook. Run it ~100 times across a day.

**Nobody has published this number. It would be the first public data.**

---

## After the gates

1. **Short-horizon arming** (24–48h) plus a visible "synced N min ago". Highest value per
   hour in the project, no infrastructure, nothing that rots, and no gate depends on it.
2. Rip out GoogleSignIn/AppAuth; point at the Worker read endpoint.
3. Push handler + APNs device-token registration.
4. Whatever gate 1 forces on the alert layer.
5. **Swift 6 migration.** `SWIFT_VERSION` is 5.0. Existing warnings show what is coming:
   four isolation errors in `AlarmAppIntents.swift` and four captured-`self` errors in
   `GoogleAuthManager.swift`.
6. **App Groups.** The entitlements file has exactly one key, `com.apple.developer.siri`,
   and the widget extension has **no entitlements file at all**. Gate 2 depends on this.
7. **Wire the two Siri schemas.** `AppSchema.ClockIntent`'s `DismissAlarmIntent` and
   `SnoozeAlarmIntent` map onto intents calarm already has. Close to free.

## Owner actions, not agent actions

These need credentials or console access an agent should not have:

- ~~Consent screen "In production"~~ — already was (External, 1/100 user cap, unverified).
- ~~`REVERSED_CLIENT_ID` URL scheme~~ — done 2026-09-23 via `Config/Calarm.xcconfig`.
- **Google verification** before any public release: calendar read is a sensitive scope, so
  unverified means a warning screen and a lifetime 100-user cap.
- **Cloudflare account** — existing or new? Free tier suffices.

## Open questions

1. **Does the multi-user pivot come back?** The Worker survives it; per-user Apps Script
   deployments do not. Cheaper to know before the Worker is written.
2. **Given the competitive field, is the goal still to build this?** Six apps shipped this a
   year ago. The honest case for yes: almost none of them do push, and the reconciliation
   problem that consumed Beacon's entire first year is exactly what a server-side change
   feed solves. The honest case for no: KeyAlarm is $0.99. See
   [RESEARCH.md § Competitive landscape](RESEARCH.md#competitive-landscape).
3. **What should the visible push say?** A visible push is mandatory for the NSE to run, so
   its text is the only lever left. It should say *what changed* — information the alarm
   itself cannot carry. Note the tension: a banner plus an alarm is two interruptions for
   one meeting.
4. **The name `Calarm` is already taken on the App Store.** Matters only if this ever ships
   publicly.

## Known local environment problems

- **`Simulator.app` is missing from this Xcode install**, and the simulator MCP integration
  reports Xcode "not selected" even though `xcode-select -p` prints the path it asks for.
  Consequence: an agent on this machine can build and run tests but **cannot drive the UI or
  verify anything visual**. Repairing the Xcode install would remove that blind spot.
- **`macmini-remote` is on macOS 26.5.2 with Xcode 26.6.** Xcode 27 needs macOS 26.6+, and
  FileVault is on, so the macOS update's restart could strand the machine at the unlock
  screen without physical or Screen Sharing access. Deferred until someone can reach it.
- **The `asc` API key's role cannot read `/builds/{id}/betaGroups`** — returns 403. Verify
  TestFlight distribution via `internalBuildState` instead, which is the state TestFlight
  actually gates on.
