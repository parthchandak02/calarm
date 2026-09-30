# Status: where the project stands and what comes next

**Last updated: 2026-09-29** — update this date whenever you change this file.

This is the living "pick up where the last agent left off" document. If you are starting a
session, read this first, then [AGENTS.md](AGENTS.md) for the working rules.

- Durable findings and sources: [RESEARCH.md](RESEARCH.md)
- What changed and when: [CHANGELOG.md](CHANGELOG.md)

---

## Right now

| | |
|---|---|
| **Branch** | `main`, pushed; the only branch in use. Untracked `reference-photos/` is gitignored |
| **Where work happens** | On the Mac mini itself (from 2026-09-27), Xcode 26.6 = the release toolchain. Two clones exist there: `/Volumes/ExternalSSD/Projects/calarm` and `~/projects/calarm` (the one `ship.sh` and herdr use); keep both pulled |
| **Latest build** | `20260929.1707` — `VALID`, `IN_BETA_TESTING` (verified by `ship.sh`) |
| **Tests** | 193 passing (`CalarmTests`, run by `ship.sh` for build 20260928.1333). The iOS 26.5 platform was reinstalled arm64-only on 2026-09-28, with an `iPhone 17` simulator for `ship.sh` |
| **Doctor** | 0 warnings |
| **Google sync** | **Working on device.** Signed in on the phone as the personal account (2026-09-24); returns events, including work-calendar busy blocks via a free/busy share. Client now in project `calarmapp-ios` (2026-09-27); new plist installed in both Mac mini clones, sign-in with the new client works in the Simulator (2026-09-27), **on device not yet retested** |
| **Backend** | None. No Worker, no relay deployed |

The app is installable from TestFlight and works off EventKit alone. Everything in
[The plan](#the-plan) below is about making it *trustworthy*, not about making it work.

---

## Waiting on the owner

**Check the next-alarm board (next build).** Arm an event a few minutes out, background CALarm
for a while, reopen it: the board counts to that ring, not hours ahead. When it rings, the
board moves straight to the following alarm; it must never count to a meeting's start. If
it still reads wrong, Settings → Status → *Share log* right away.

**Check the default-alarm offer (next build).** Settings → Alarms, tap another default: a prompt
names how many armed events use a different time. *Change N events* sets them all (the −10m
rows become the new default); *Only new events* leaves them. The Look row shows an accent
square plus a sun/moon/half icon, and there is no line under the countdown.

**Check the owner-feedback UI round on device (next build).** Home: the countdown has no event
line under it, and day headers are flap tiles that stay opaque when pinned while scrolling (the
Simulator demo list is too short to pin). Settings → Look: Light → System (phone in dark)
turns the open sheet dark at once. Settings → Calendars: "Turn all on/off" in each section, and
the footer says "next 8 days". Test alarm popup says 16 seconds with Island at 5.

**Check the first-run tips and the moved alarm prompt on device (next build).** Delete and
reinstall CALarm (the tips only show on a fresh install). Launch: **no alarm permission prompt**
should appear, and the calendar screen shows a "Start with your calendar" tip. Allow calendar
access; a "Tap the square to arm" tip points at the first upcoming event. Tap the square: iOS
asks to allow alarms, and the event arms once allowed. Then the row, bell and gear tips follow
one at a time. Settings → *Show tips again* brings them back. An existing install updated in
place should show no tips.

**Check the Live Activity lead and the vibrate/snooze fixes (next build, unreleased).** With
Settings → Alarms → Island at **5**:
- Run the test alarm: the card should appear ~8s after the tap, *not* at the tap, and ring at
  ~16s. Settings → Status → Alarm timing should read *On time · 16s*. *Early · 8s* means the
  device follows Apple's docs and every alarm would ring 5 min early — set Island to ALL.
- Arm a real event 15 min out, force-quit CALarm: no card until start − 5 min, then a
  countdown that rings on time.
- Snooze a ringing alarm with the app open, then snooze the re-ring too: each should re-ring
  after its snooze.
- Vibrate on: a real event's alarm should only vibrate — no ring a minute later, dismissed or
  not (the fallback is removed; one ring per chosen offset).

**Check the Live Activity countdown on device (next build).** Build 2129 drew the Lock Screen
card and the compact Island's countdown blank in countdown and paused states; the ringing
state rendered. Cause (inferred, not provable off device): `FlapTimer` set its text with a
UIFont-backed `Font(uiFont)`; now `.custom`. Arm an event, lock the phone, and check: the card
shows the title row and tiles; digits sit on their tiles; after 10:00 or 1:00:00 the left tile
goes blank and the rest stay aligned; the compact Island is a short pill (lit square + tiles). Also check the
in-app countdown's new flip looks right on device.

**Check missed-alarm detection (next build).** Arm an event a few minutes out, lock the phone,
let it ring out without touching it. About 5 minutes after the ring time the row should read
`missed` and Settings → Status → *Missed alarms* should name it. Then arm another and tap
Dismiss: it must *not* show as missed. Also check the Watch/CarPlay Live Activity shows the
meeting title, and the minimal Island (start a timer in Clock too) is a draining ring.

**Live Activity edge cases nobody documents (researched 2026-09-26).** On device: (1) turn
Settings → CALarm → Live Activities **off**, arm an event with Island at 5 — does it ring?
(2) swipe the countdown card away mid-countdown — does it still ring? (3) with the phone
unlocked and in use, how loud is the alert? (4) snooze an alert-only alarm — what shows? (5) is
the countdown on the Watch / Mac menu bar, and does it show a title? See RESEARCH.md § Live
Activity surfaces.

*The vibrate-fallback check is retired*: the fallback was removed (2026-09-25, owner's
one-ring rule). Vibration itself is confirmed (2026-09-24).

**Confirm one ring per minute (build 20260924.1342+).** After installing, open CALarm once. A minute with
several events (e.g. 1:00 PM "Busy" + "Meeting Free Block") should ring once, titled
"<event> + N more", and the list should no longer show a "Busy" block next to a titled event
at the same time.

**Run the vibrate test matrix (next build).** Settings → Status now lists each armed alarm's
sound (`VIB`/`RING`; red = not updated to the current mode) and has *Share log*. For each case,
check Status before the alarm, note what actually happened, then share the log:
1. Manual toggle on, app open → VIB, vibrates. 2. Same with the silent switch off → vibrates.
3. Toggle on, force-quit before the alarm → vibrates. 4. Focus filter on, app open → FOCUS
`on · vibrate`, VIB. 5. Focus turned on with CALarm backgrounded → does a FOCUS line appear
without opening the app? 6. Focus on with CALarm force-quit → expected to ring (known gap).
7. Focus **off** with CALarm force-quit → expected silent (known gap, the dangerous one).
8. A scheduled Focus ending on its own → is the FOCUS `off` line logged? 9. Haptics "Never
Play" → vibration or nothing? 10. Vibrate on, snooze, turn vibrate off before the re-ring.

**Confirm the work free/busy share is allowed.** Work-calendar busy blocks reach the app
through the personal Google account. The owner chose to keep it on and check policy
themselves (2026-09-24). Do not file anything for them.

*Older items below are from builds 1106–1613 and have not been confirmed done.*

**1. Confirm the calendar fix.** (2026-09-24: all 20 EventKit calendars are switched off and
Google supplies events; all-off now reads nothing, so this item is moot unless an iOS-only
calendar is wanted.) Build 1613 changed the per-calendar filter from an
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

## Direction (decided 2026-09-27)

A multi-agent review (UX, engineering, features, adversarial) settled the order: **reliability
fixes → one consolidated on-device check + Gate 1 → push (Gates 2–3) or stop.** No new
features or redesign until Gate 1 has data.

- **Done (unreleased):** four missed-meeting bugs, see CHANGELOG *Unreleased — 2026-09-27*.
- **Next:** ship, then collapse *Waiting on the owner* into one 15-minute checklist that
  doubles as the Gate 1 overnight run; pull the journal. Then a "synced N min ago" line on home.
- **Rejected, with reasons:** Foundation Models for scheduling (a wrong "skip" is a missed
  meeting; rules beat it; see RESEARCH § Apple Intelligence), a database (no bug traced to
  UserDefaults), a global auto-arm default (work busy blocks would all ring; alarm fatigue),
  more screens, travel-time alarms, Control Center control, join-meeting button.
- **Later, if Gate 1 passes:** per-calendar opt-in arm rules (excluding busy-only), Siri
  `ClockIntent` wiring, board-style pass on event detail and Settings de-duplication.

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
- **Google branding:** `parthchandak.info` is verified in Search Console for parth.chandak02@gmail.com (Domain property, via Cloudflare, 2026-09-27). **Never delete its `google-site-verification` TXT records.** Site: `calarm.parthchandak.info` (GitHub Pages, Cloudflare CNAME, DNS only).
- **Delete the old "CALarm iOS" client** in project `useful-field-497119-k5` once sign-in works on device. The `calarmapp-ios` consent screen is already In production.
- **Google data-access verification: submitted 2026-09-27; 2026-09-29 review passed all
  items except the privacy policy** ("no data protection mechanisms for sensitive data").
  `docs/privacy.html` now has a data-protection section; **owner: reply to the Trust and
  Safety email thread saying the policy is updated** (the URL is unchanged, so no console
  edit). Demo video
  (Unlisted) `https://www.youtube.com/watch?v=1O6eJmY1BPc`, recorded per
  [GOOGLE_OAUTH_DEMO.md](docs/app-store/GOOGLE_OAUTH_DEMO.md). Google replies to
  parth.chandak02@gmail.com; until approved, sign-in shows the unverified warning and the
  100-user cap holds.
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
