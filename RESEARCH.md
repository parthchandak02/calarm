# Research: verified facts, disproved claims, and the architecture question

Durable findings for calarm. This is the **do-not-re-research** file — everything here was
read against a primary source or is explicitly labelled otherwise. It supersedes the
earlier `HANDOFF.md` (September audit) and `PLAN.md` (architecture plan), which were merged
into this document on 2026-09-22.

For *what is happening right now* see [STATUS.md](STATUS.md).
For *what changed when* see [CHANGELOG.md](CHANGELOG.md).
For *how to work in this repo* see [AGENTS.md](AGENTS.md).

**Evidence labels**, used throughout:

| Label | Meaning |
|---|---|
| **CONFIRMED** | Primary source read directly — SDK interface, Apple doc, vendor doc, source code |
| **REPORTED** | Secondhand; credible but uncorroborated |
| **INFERRED** | Reasoning from evidence, flagged as reasoning |

**Provenance caveat.** Some vendor pages were fetched through a summarizing layer, so a few
quoted strings are near-verbatim rather than guaranteed character-exact. Apple
documentation, Apple Developer Forums, GitHub source and the `itunes.apple.com/lookup` API
were read directly. Re-read the source URL before citing any quote externally.

---

## Settled decisions

**Extend this repo, do not rewrite it.** The expensive part — AlarmKit lifecycle
reconciliation — is done and done well, surrounded by a complete release pipeline, accurate
privacy manifests and a coherent design system. Rewriting means re-earning several bug-fix
cycles documented in the commits, the code comments and the twelve skills in `.claude/skills/`.

**calarm is the iPhone app. `predecessor iOS target` is retired.** A separate AlarmKit + Live Activity +
EventKit target was built in the predecessor app repo and abandoned; the two were substantially the
same app and calarm was far ahead. Do not resurrect it. The parts worth stealing are named
under [Worth stealing from predecessor iOS target](#worth-stealing-from-zpingios).

[redacted]
[redacted]

---

[redacted]

**Read this before proposing anything that touches the work calendar.** Verified against
[redacted]

[redacted]

[redacted]
> applications, in properly enrolled devices."

And the Apple setup guide is explicit:

> "You will need to install Gmail and Google Calendar to access email and calendar. You
> will not be able to manage it with Apple Mail/Calendar app."

Two consequences:

[redacted]
[redacted]
[redacted]
[redacted]
   added to iOS Settings → Calendar. The Google Calendar iOS app keeps its own private
   store and does not write to the iOS calendar database.

**Do not propose reading the work calendar from the phone without the owner clearing it
[redacted]

What *is* sanctioned: the Mac. predecessor app on macOS reads the work calendar through `gws`,
[redacted]
may use. `gws` is a Node.js CLI and **cannot run on iOS** under any configuration.

---

## AlarmKit

### What the SDK actually provides

Read from the iOS 27.0 SDK `AlarmKit.swiftinterface`. **CONFIRMED.**

- **There is no pre-fire hook. Nothing wakes the app when an alarm fires.** The complete
  observation surface is `alarms` (synchronous snapshot), `alarmUpdates` (an **in-process**
  `AsyncSequence` — it needs your process already alive and iterating),
  `authorizationUpdates`, and tap-driven `stopIntent` / `secondaryIntent`.
- iOS 27 added exactly one thing: `appEntityIdentifier: AppIntents.EntityIdentifier?` on
  `AlarmConfiguration.init/timer/alarm`. Siri/Spotlight entity linkage, not a callback.
- `Alarm.State` is `{scheduled, countdown, paused, alerting}`.
- `AlarmPresentation.Alert.title` is a `LocalizedStringResource`, so a runtime-generated
  title needs `LocalizedStringResource(stringLiteral:)` and loses localisation.
- **There is no `com.apple.developer.alarmkit` entitlement.** The gate is
  `NSAlarmKitUsageDescription` plus `requestAuthorization()`. Most public write-ups claim
  otherwise; an Apple engineer has publicly noted that language models keep inventing it.
- `AlarmPresentationState.Mode.Countdown` carries `totalCountdownDuration`,
  `previouslyElapsedDuration`, `startDate` and `fireDate`. Prefer `totalCountdownDuration`
  over "time remaining now" for any layout decision — widget bodies render once and the
  system animates from there.
- **`preAlert` is the countdown duration itself**, not a lead-in offset. Apple's docs:
  *"this would be the duration of a timer."* Any non-nil `countdownDuration` puts the alarm
  into `.countdown` mode. Set `preAlert: nil` (not `0`) for a plain scheduled alarm.

### AlarmKit owns the Live Activity — do not create your own

**CONFIRMED.** The app supplies only the *views*, via a widget extension declaring
`ActivityConfiguration(for: AlarmAttributes<T>.self)`. You never call `Activity.request`.
`AlarmPresentationState` is documented as "the system managed content state of an alarm
Live Activity". If an app schedules an AlarmKit alarm **and** separately calls
`Activity.request` for the same countdown, it gets two. calarm calls `Activity.request`
nowhere — verified 2026-09-22.

> "AlarmKit expects a widget extension if an app supports a countdown presentation.
> Otherwise, the system may unexpectedly dismiss alarms and fail to alert."
> — [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)

### Apple's reliability promise

From the [AlarmKit FAQ](https://developer.apple.com/forums/thread/797158), **CONFIRMED**:

- *"all alarms are expected to persist regardless of app or device state changes, once they
  are successfully scheduled"* — covers reboot, force-quit, crash.
- *"AlarmKit alarms can break through all focus modes."*
- *"There is no set number as a limit… the device may impose a limit"* →
  `maximumLimitReached`.
- *"Hidden or passcode required apps do not work with AlarmKit. Currently, any scheduled
  alarms by such apps will silently fail."*

### Four open threads contradict that promise. No Apple staff reply on any.

| Bug | Evidence | Label |
|---|---|---|
| Alarms fire **at exactly 00:00** instead of the scheduled time. *Bird Rise* dev, production data: across **~13,000 firings in 30 days**, 84% of alarms are scheduled 06:00–09:59 yet **10–15% of actual rings land in 21:00–01:00**. Persists 26.1–26.4 | [thread/820388](https://developer.apple.com/forums/thread/820388) | **CONFIRMED** |
| Alarms **stopped ringing entirely** on 26.2 beta 3/RC after upgrading from 26.1. Reproducible **with Apple's own sample code**. FB21273655 | [thread/809398](https://developer.apple.com/forums/thread/809398) | CONFIRMED |
| Alarms fire **5–45 min late or not until the phone is woken**. sysdiagnose: `mobiletimerd` registers the XPC wake-up, `launchd` drops it, nothing reschedules. FB22887867 (26), FB24483266 (27.0 RC) | [thread/798619](https://developer.apple.com/forums/thread/798619) | REPORTED |
| Alarms don't fire when a foregrounded app is in **landscape**. Affected Apple's own Reminders. Workaround: 1-second `preAlert` | [thread/806681](https://developer.apple.com/forums/thread/806681) | CONFIRMED |

That 13,000-firing dataset is **the only hard reliability number in the entire research
corpus**, and it comes from a developer whose own App Store copy says *"powered by the new
AlarmKit for incredibly reliable alarms."* Marketing is not evidence of mechanism.

iOS 27.0 shipped 2026-09-14; its release notes mention alarms only for independent
Alarm/Timer volume and a China-specific Clock behaviour. **No AlarmKit delivery fix.**

The late-firing *rate* is one developer's impression. The *mechanism* — launchd dropping a
registered XPC wake-up — carries technical substance. Treat the mechanism as credible and
the rate as unmeasured.

### Known Dynamic Island / Live Activity bugs

- **Zombie empty Live Activity.** Swiping the Island away instead of using Stop leaves a
  blank activity that reappears on long-press. FB22295664.
  [thread/812006](https://developer.apple.com/forums/thread/812006)
- **Timer values update unpredictably in the Island** versus reliably in-app.
  [thread/757140](https://developer.apple.com/forums/thread/757140)
- **`Text(date, style: .timer)` over-expands** — unresolved since iOS 16. The compact region
  has no intrinsic size; the Island grows to whatever the content asks for, and timer text
  asks for room to hold every digit combination it could show.
  [thread/723316](https://developer.apple.com/forums/thread/723316)
- **Simulator is unreliable** for AlarmKit Dynamic Island and alert sounds. Test on device.
  calarm's own Settings deliberately blocks the test alarm on Simulator.

Measured glyph widths for `.system(size: 11, weight: .semibold, design: .rounded)`:
`59:59` = 33pt, `23:59:59` = 51pt. calarm reserves 38pt and 58pt respectively.

### Countdown timing and Island width (researched 2026-09-23)

- **`preAlert` with a `.fixed` schedule counts down *to* the fire date.** `Alarm.countdownDuration`
  doc: *"The UI will appear at a time equal to the next scheduled alert date minus the
  duration."* So calarm's `preAlert: fireDate.timeIntervalSinceNow` is correct per the docs.
  **CONFIRMED** (doc). No public on-device report either way — the 8-second test alarm
  (8s fire, 8s pre-alert) settles it: rings at ~8s if the docs hold, ~16s if not.
- **A snoozed alarm's Live Activity counts to press time + `postAlert`**, not to the event, and
  keeps the event title. `SnoozeAlarmIntent` also calls `AlarmManager.countdown(id:)` on top of
  the system's `.countdown` secondary behaviour. **INFERRED.**
- **The compact Island cannot shrink during an uninterrupted countdown.** Every timer text API
  (`Text(timerInterval:)`, `.timer` style, iOS 18 `SystemFormatStyle.Timer`) drops the hour field
  in its *text* but reserves maximum *width* at render, and AlarmKit re-renders only on
  countdown/paused/alert changes. Apple's WWDC26/223 sample caps width with
  `.frame(maxWidth:)` too. Best available: key width to time remaining *at render*.
  **CONFIRMED** (SDK doc comments, [723316](https://developer.apple.com/forums/thread/723316),
  [WWDC26/223](https://developer.apple.com/videos/play/wwdc2026/223/)).
- **`isDynamicIslandLimitedInWidth`** (WidgetKit, iOS 27) reports a width-limited Island
  (landscape); Apple's sample shows an icon instead of a timer then. **CONFIRMED.**
- **Widget-side `isActivityExpired` cannot work**: it reads `Date()` at render and Live
  Activities have no timeline, so it never re-evaluates. **INFERRED, high confidence.**
- New forum threads: late firing reproduced by Apple DTS with sample code, *"I do not know a
  workaround"* ([846063](https://developer.apple.com/forums/thread/846063)); zombie Live
  Activity unremovable by the app, still in 27 beta 8, FB22791285
  ([819556](https://developer.apple.com/forums/thread/819556)); lock-screen touch dismisses an
  alarm without running either intent, leaving it `.alerting` forever, FB24407814
  ([842638](https://developer.apple.com/forums/thread/842638), REPORTED); `stopIntent` skipped
  on swipe-away ([815064](https://developer.apple.com/forums/thread/815064), REPORTED).

---

## EventKit

- **Zero new API in iOS 26 or 27.** Every header in `EventKit.framework/Headers` grepped for
  `API_AVAILABLE(ios(26` and `ios(27` — no matches. Nothing has improved and nothing is
  coming. **CONFIRMED.**
- `refreshSourcesIfNecessary` is weaker than most people assume. Verbatim from
  `EKEventStore.h`: *"Cause a sync to potentially occur taking into account the necessity of
  it. […] On iOS and macOS, this sync only occurs if deemed necessary."* It is a hint the
  daemon may decline. No completion handler, no error, no force-sync.
- Realistic worst-case staleness for a Google account is **15–60 minutes**, unbounded in Low
  Power Mode. CalDAV has no push in the protocol and Google implements none, so iOS polls.
- **Local identifiers are not stable.** When a CalDAV/Google account resyncs, EventKit
  reissues local IDs for the same logical events. Keying anything durable to
  `eventIdentifier` alone will break — this is what `CalarmShared/EventOccurrenceID` exists
  to avoid, and it is the documented cause of a competitor's worst bug (see
  [Competitive landscape](#competitive-landscape)).

---

## Google Calendar API

### Sync tokens — the rule most people get backwards

From the [Events: list reference](https://developers.google.com/workspace/calendar/api/v3/reference/events/list):

- `nextSyncToken`: *"Omitted if further results are available, in which case `nextPageToken`
  is provided."* **That is the only documented omission condition.** Query parameters do not
  suppress it.
- The restriction runs the other way. Forbidden on a request that **sends** a `syncToken`:
  `iCalUID`, `orderBy`, `privateExtendedProperty`, `q`, `sharedExtendedProperty`, `timeMin`,
  `timeMax`, `updatedMin`.
- And: *"All other query parameters should be the same as for the initial synchronization to
  avoid undefined behavior."*
- `timeMin` **is** allowed on the token-minting request and does not suppress the token.
- 410 GONE means clear local state and full sync.
- Quota: 600 requests/min/user, 1,000,000/day/project. A 30-second poll is 0.33% of the
  per-user ceiling. **Quota is a non-issue.**

With `singleEvents=true` and no `timeMax`, Google expands every recurrence for all time and
one daily standup becomes thousands of rows. The token-minting call must use
`singleEvents=false`.

### Push (`events.watch`)

- Supports only `web_hook` channels to a CA-signed HTTPS URL. **A phone can never be the
  target.** **CONFIRMED.**
- **Domain verification is no longer required.** Google: *"Domain verification in the API
  Console is no longer required to make push notifications work with your domains."* A free
  `*.workers.dev` subdomain satisfies the only remaining requirement, so **the
  commonly-cited "$10/yr domain" cost for a Worker relay is wrong.** **CONFIRMED.**
- **The webhook carries no body.** Just "something changed" in headers. The relay must do an
  OAuth refresh **plus** an incremental `events.list` before it can build a push. Two Google
  round trips on the critical path — that is probably where the real latency lives, not in
  the webhook hop. **CONFIRMED.**
- **Channels expire after ~7 days (default TTL 604800) with no warning, no error, no
  callback — just silence.** Renewal is entirely yours. **CONFIRMED.**
- How practitioners handle it: Pipedream requests a **24-hour** TTL and renews at ~22.8h;
  `todoist-calendar-sync` renews every 12 hours against the 7-day TTL *and* built a liveness
  monitor. Two unrelated production systems renewing 7–14× more often than required, one
  with explicit liveness tracking, says renewal failure is common and **detection is the
  actual engineering problem**.
- **Google Workspace Events API does not support Calendar.** Chat, Drive and Meet only.
- Google's own admission: *"Notifications are not 100% reliable. Expect a small percentage
  of messages to get dropped under normal working conditions."*
- **Nobody has publicly pointed `events.watch` at a `*.workers.dev` URL.** It should work,
  but `"Unauthorized WebHook callback channel"` is a live failure mode with folklore rather
  than diagnosis around it. **INFERRED.** Ten-minute de-risk: make one call and see.
- **No public latency measurement exists.** See
  [Disproved claims](#claims-made-and-then-disproved).

---

## Google Apps Script

- `CalendarTriggerBuilder` has exactly two methods, `onEventUpdated()` and `create()`.
- **The handler receives `{authMode, calendarId, triggerUid}` and nothing else.** Google:
  *"These triggers do not tell you which event changed or how it changed."* The trigger is a
  doorbell; `syncToken` is the letter.
- **Apps Script cannot talk to APNs. Blocked twice.** `Utilities` exposes only
  `computeRsaSha1Signature`, `computeRsaSha256Signature`, `computeHmacSha256Signature`,
  `computeHmacSignature` and `computeDigest` — **no ECDSA/ES256/P-256 primitive anywhere in
  the runtime**, and APNs auth tokens require ES256. `UrlFetchApp` also has no
  protocol-version parameter, and APNs mandates HTTP/2. **CONFIRMED.**
- **FCM is the way through**, because Google service accounts sign **RS256**.
- **`doGet` cannot read request headers, ever.** Google declined the feature in 2023. A
  shared secret must travel in the query string. Avoid parameter names `c` and `sid`, which
  are reserved and return HTTP 405.
- Quotas, consumer vs Workspace: **triggers total runtime 90 min/day vs 6 hr/day**; script
  runtime 6 min/execution; UrlFetch 20,000/day vs 100,000/day; 20 triggers per user per
  script. **No documented limit on inbound requests to a published web app.**
- Apps Script on its **default** Cloud project is exempt from the 7-day refresh-token death
  that applies to OAuth clients in "Testing" status. **Attaching your own Cloud project with
  a Testing consent screen reintroduces that clock.**
- Editing an **existing** deployment keeps the URL; **"New deployment" mints a new URL** and
  your shipped app keeps calling the old one.
- **`onEventUpdated` latency is unpublished.** No SLA, no measurement, anywhere.

`apps-script/Relay.gs` implements both the FCM push path and the `doGet` read-API path.

---

## Cloudflare Worker → APNs

**It works in production, via an undocumented mechanism.** Kenton Varda, Cloudflare Workers
architect, on [workerd#4841](https://github.com/cloudflare/workerd/issues/4841):

> "workerd doesn't have HTTP/2 support, but in production it sends requests through
> Cloudflare's proxy stack which (apparently) upgrades to HTTP/2 before talking to the
> origin."

Note "(apparently)". **CONFIRMED that it works; CONFIRMED that it is undocumented.**

- **You cannot test APNs locally.** Local `workerd` has no HTTP/2, so every `wrangler dev`
  APNs call fails. Use `--remote` or deploy. Plan the dev loop around this.
- **Real corroboration:** [Codakuma](https://codakuma.com/pushy/) replaced OneSignal in a
  shipping App Store app with a ~200-line Worker doing exactly this, deleting 23,000 lines
  of SDK.
- **Sandbox vs production APNs endpoints differ.** A debug-build token sent to
  `api.push.apple.com` returns 410 and the token is deleted. This will eat your first
  afternoon if you don't know it.
- **Don't take the dependency.** `FiveSheepCo/cloudflare-apns2` is 22 stars, 0 issues, last
  pushed 2025-01-04. Zero issues at 22 stars means nobody uses it. Copy its ~150-line
  `apns.ts` as a reference implementation instead.
- JWT must be cached and regenerated ~every 55 minutes; Apple rejects tokens over an hour
  old **and** rate-limits frequent minting.
- **Cron Triggers have no automatic retries by design.** A throw or timeout is gone until the
  next tick. Combined with silent channel expiry, two consecutive cron failures = the alarm
  app stops working and nothing tells you. **A correctness problem, not an inconvenience.**

---

## What runs your code while the app is force-quit

Only three mechanisms, plus AlarmKit itself in a different category.

| Mechanism | Wakes force-quit app? | Precise timing? | Verdict |
|---|---|---|---|
| **Visible push → `UNNotificationServiceExtension`** | **YES** (the extension runs, not the app) | YES, server-timed | **The path.** Apple-endorsed |
| **Push-to-start Live Activity** | **YES** — documented to "wake up your app, and grant it background runtime" | YES, server-timed | Viable second call site; entry point is the widget extension |
| **PushKit / VoIP push** | Yes | YES | **Trap.** iOS kills a non-VoIP app that doesn't report a call, then stops launching it at all |
| AlarmKit (pre-scheduled) | Fires regardless of app state | Intended; see above | Different category — it doesn't wake you, it fires on your behalf |
| Silent push (`content-available`) | **NO** — "If something force quits or kills the app, the system discards the held notification" | No | Ruled out |
| `BGAppRefreshTask` / `BGProcessingTask` | **NO** — force-quit sets a flag preventing background launch | No | Ruled out |
| `BGContinuedProcessingTask` (26) | **NO** — "starts in the foreground" by definition | N/A | Ruled out |
| Silent audio session | **NO** — force-quit terminates it | N/A | Also an App Store rejection risk |
| Widget timeline reload | Extension only; "Widgets cannot perform tasks in the background" | No | Ruled out |
| Region / significant-location | Documentation conflicts; unreliable | **No** | Ruled out for our purpose |

**Apple DTS, verbatim**, on running code after a force-quit:

> "If you have to, you can use a Notification Service Extension… The Notification Service
> Extension will be executed for every *visible* push notification… The service extension
> will *not* be executed for push notifications that will not be presented visually."

NSE constraints, from an Apple DTS engineer: **30 seconds, 24 MB**, and *"cannot directly
communicate with the main app except via a shared container."* That makes **App Groups a
hard prerequisite**, and the entitlements file currently has only
`com.apple.developer.siri`.

**Measured rather than searched:** there is **no compile-time barrier** to calling AlarmKit
from an extension. Every `@available(... unavailable)` annotation in the AlarmKit
`.swiftinterface` is `macCatalyst`; there are **zero** `iOSApplicationExtension, unavailable`
markers. A real `AlarmManager.shared.schedule()` call typechecks clean under
`-application-extension`, with `UIApplication.shared` failing as a control. **CONFIRMED by
direct experiment.** What remains unknown is runtime XPC/sandbox policy and whether
authorization resolves for an extension caller.

---

## Competitive landscape

calendar→alarm is a **real, crowded category**. Effectively none of these existed before
iOS 26, because the mechanism did not. **CONFIRMED** via App Store metadata.

| App | minOS | First release | Notes |
|---|---|---|---|
| **Beacon: Calendar Alarms** | 26.1 | 2025-09-21 | Rules engine. Launched €35/yr, cut to $15/yr after backlash |
| **Cal Alarms** | 26.0 | 2026-02-27 | Only one documenting its sync triggers |
| **Unmissable** | 26.0 | 2025-09-15 | "No cloud sync… data stays on your device" |
| **Meeting Alarms: Calerto** | 26.0 | 2025-09-17 | Accounts + Google sync ⇒ server component |
| **Timely Alarms** | 26.0 | 2025-09-15 | iCloud restore, Live Activities, Siri |
| **KeyAlarm** | — | 2026 | Keyword triggering. $0.99 |
| **Today Planned** | 26.0 | 2023 | Pre-AlarmKit it drove **Shortcuts** to create Clock alarms |
| **Fantastical** | — | 4.1.11, 2026-03 | "Urgent Alarms" on AlarmKit. The most important datapoint here |
| **OnTimer** | 18.0 | 2025 | OAuth + server-held APNs tokens. Already shipping our architecture |
| **CalendarWake** | — | — | Asks users to add a **widget** so timeline refreshes act as a background-execution proxy (INFERRED) |

**There is already an App Store app called `Calarm`** — squishLogic LLC, id509840570,
shipping since ~2012, minOS 18.0. Pre-AlarmKit; a review states its limitation plainly:
*"alerts play for a while and then stop, whereas alarm keeps going until you stop it."* The
name is taken, by a product solving the same problem worse. **CONFIRMED.**

### Fantastical refused to build this on EventKit

Flexibits shipped "Urgent Alarms" on AlarmKit in March 2026. Their help page, **CONFIRMED**:

> "Calendar accounts must be added directly to Fantastical"
> "All day tasks and events do not support Urgent Alarms"
> "Special Google events (Out of Office, Focus Time, Events from Gmail) do not support
> Urgent Alarms"

Read the first line carefully. Urgent Alarms do **not** work off EventKit-delegated
accounts. **The best-resourced team in this category declined to build alarms on EventKit.**
Every indie competitor does. calarm has a direct Google Calendar API client — the same
choice Fantastical made, and the strongest external evidence that it is the right one.

### Beacon's changelog is the most useful artifact found anywhere

A year of releases, almost entirely one problem — **keeping already-scheduled alarms in sync
with a mutating calendar**:

- 1.2.1 — "Manual alarms are no longer lost when their event is moved to a new time"
- 1.1.8 — "Improved alarm persistence for events further than 1 month away"
- 1.0.9 — "Fixes bug with rules not respecting changes to recurring events"
- 1.0.6 — "Duplicate events and alarms in agenda"
- 1.1.2 — shipped a **"Sync Beacon" Shortcuts action** so the user can force a sync manually

That last one is an admission: **background refresh alone is not trustworthy, and the
category leader worked around it by handing the user a button.** Every one of these bugs is
a bug calarm will have.

### Two shipped-failure artifacts that map onto calarm's work

**Timely Alarms release note. CONFIRMED:**

> "Fixed alarms going silent after a calendar account resynced — an alarm could be left
> running that the app could no longer show or cancel."

**INFERRED (high confidence):** the signature of keying AlarmKit alarms to EventKit *local*
identifiers. This is exactly what `EventOccurrenceID` exists to prevent.

**Calalarm Calendar** (id1590304931) — user reviews, verbatim:

> "at 10pm I was given the alarm about a 7pm meeting"
> "Now 8 hours past a Google calendar event I am finally receiving an alarm."

**INFERRED:** the classic signature of relying on `BGAppRefreshTask`.

### The constraint nobody can engineer around

**Not one app in the category documents re-validating the calendar immediately before the
alarm fires.** AlarmKit alarms are handed to the system and fire **without your app
executing**. So a true pre-fire re-check is probably **impossible by design**. **INFERRED**,
but nothing contradicts it.

Consequence: there is no fire-time safety net. The scheduled set must be correct *in
advance* — which is why push-driven invalidation is worth infrastructure, and why
short-horizon arming bounds the damage when it fails.

### What this means

**Against:** the idea is not novel; six apps shipped it a year ago and one is a polished
paid product.

**For:** *almost none of them do push.* Every EventKit-based player hit the freshness wall
and **worked around** it — Beacon shipped a manual sync action, CalendarWake piggybacks on
widget refreshes, CalAlarms triggers on location changes. Four developers, four hacks, one
unsolved problem. The exception is **OnTimer**, which already ships this architecture. The
reconciliation problem that consumed Beacon's entire first year is **exactly what a
server-side change feed solves**. The differentiator is the backend, not the app.

---

## Target architecture

```
Google Calendar
   │  events.watch webhook  (latency UNMEASURED — see STATUS.md gate 3)
   ▼
Cloudflare Worker  ── holds the refresh token (single-tenant)
   │                 ── owns + renews the watch channel (hourly cron + liveness alert)
   │                 ── OAuth refresh + incremental events.list  ← the real latency
   │                 ── hourly poll as the dropped-notification backstop
   │
   ├── APNs direct (ES256/WebCrypto, no Firebase)
   │      └──► VISIBLE time-sensitive push, mutable-content: 1
   │             └──► NSE re-arms alarms  [GATED on STATUS.md gate 2]
   │
   └── read endpoint ◄── calarm on every foreground
```

calarm becomes a client with **no Google dependency at all** — one URL and one bearer token
in the Keychain. That deletes GoogleSignIn + AppAuth (8 SPM packages),
`GoogleService-Info.plist`, and the `REVERSED_CLIENT_ID` plist work that was never done and
is very likely why Google sign-in has never once completed end to end in this app.

Three layers of defence, because a missed meeting is this app's worst outcome: push on
change (seconds) → Worker hourly poll (catches Google's dropped notifications) → app refresh
on foreground. Plus **short-horizon arming** (24–48h) so a stale window has a bounded blast
radius.

**Why the Worker over Apps Script**, now that both latencies are known to be unmeasured:
one component instead of two (Apps Script would still need a Worker to sign APNs); no
90 min/day trigger-runtime cap; and it survives a multi-user pivot, which per-user Apps
Script deployments do not.

**Pipedream is out**: its instant trigger "does not emit cancelled events," and a deleted
meeting is precisely the event an alarm app most needs.

Cost: **$0.** The only thing that rots is the watch channel; the mitigation is hourly
renewal **plus liveness alerting** — not renewal alone, because cron has no retries.

### Options considered and their ranking

| | What | Freshness | Cost | Needs $99 Apple? |
|---|---|---|---|---|
| **A** | **Short-horizon arming.** 24–48h, re-arm on foreground, visible "synced 4 min ago" | Bounded blast radius | $0, an afternoon | No |
| **B** | Apps Script `doGet` as a read API the app polls | Poll interval + ~1s | $0 | **No** |
| **C** | B plus `onEventUpdated` pre-computing JSON into `PropertiesService` | Same as B, faster response | $0 | No |
| **D** | Pipedream instant trigger → FCM → visible push | Seconds | Free tier | Yes |
| **E** | Apps Script → FCM → visible push | Seconds | $0 infra | Yes |
| **F** | **Cloudflare Worker + `events.watch` + APNs** ← chosen | Seconds | $0 infra | Yes |
| **G** | Apps Script → APNs directly | **Impossible** | — | — |

**Option A is not optional** — it makes every other option's failure mode survivable, and
it remains the highest value-per-hour work in the project.

**Option B's real prize**, worth remembering even though it cannot meet ≤60s on its own: if
the app talks to a server instead of Google directly, it needs **no Google OAuth at all** —
no client ID, no consent screen, no verification, no 100-grant cap, no 7-day refresh-token
expiry, no `GoogleService-Info.plist`, and 8 SPM packages gone. The target architecture
keeps that property.

### Traps, each with the specific reason

- **Zapier free polls every 15 minutes; IFTTT free is hourly.** Equal to or worse than the
  EventKit staleness you are trying to escape. Make.com and n8n poll rather than watch.
- **ntfy / Pushover / Telegram deliver into *their* app.** No mechanism by which their app
  receiving a push causes calarm to execute code. Fine as a human nudge, useless as a wake.
- **Any design leaning on a silent push.** Not delivered to a force-quit app, budgeted at
  2–3/hour, dropped on undocumented heuristics. **Visible pushes are the reliable channel.**
- **Pushcut's Automation Server** works only while the Pushcut app is visible on screen.
- **Critical Alerts entitlement.** Apple has denied it to alarm apps at least twice with
  matching language — *"this API is not designed for the use you've identified"* — and DTS
  now redirects to AlarmKit. It would also buy nothing: AlarmKit already overrides silent
  mode and Focus with no entitlement. **Do not file for it.**

---

## Claims made and then disproved

Each of these was reached confidently and then found wrong. They are the traps most likely
to be re-entered.

**"The syncToken branch is dead code."** Wrong. The stated reason — that `timeMin`/`timeMax`/
`orderBy` make a response ineligible for `nextSyncToken` — is backwards. The token minted
fine and the branch ran on every sync. The real bug was the unmatchable parameter set.

**"The Google sync is properly built."** Wrong, said after reading `GoogleCalendarAPIClient`
and not its caller. The client's plumbing looks good in isolation;
`GoogleCalendarService` used it in a way that made it pointless. **Read the caller before
praising the callee.**

**"There is no calendar or alarm assistant-schema domain for Siri."** Wrong. iOS 27
**renamed** `AssistantSchemas` to `AppSchema`, leaving deprecated markers at the old name.
Both `AppSchema.CalendarIntent` and `AppSchema.ClockIntent` exist, including
`DismissAlarmIntent` and `SnoozeAlarmIntent`.

**"Use NLEmbedding plus k-NN for the behaviour learner."** Half wrong. The k-NN half stands;
`NLEmbedding` is measurably unfit — see [Apple Intelligence](#apple-intelligence).

**"The Worker relay needs a ~$10/yr domain."** Wrong. Domain verification was dropped.

**"EventKit sidesteps the Workspace OAuth block."** True in general, moot for the work
calendar — on that account the local store is **empty**.

**"Webhook latency is 3–10 seconds."** No primary source exists. Traced to content-marketing
blogs for paid sync products; no methodology, no sample size. Google's push documentation
makes **no latency claim at all**. Both the webhook and `onEventUpdated` are unmeasured.

**"calarm is unusual."** Wrong — see [Competitive landscape](#competitive-landscape).

**"None of the competitors do push."** Wrong, said twice. OnTimer does. True only of the
EventKit-based subset.

**"Cloudflare Workers need Firebase to reach APNs."** Wrong. Workers expose WebCrypto ECDSA
P-256 and their production egress negotiates HTTP/2.

**"The Apps Script read-API can meet ≤60s."** Wrong — not an Apps Script failing. iOS will
not let a rarely-opened app poll in the background at all.

### Agent claims caught, recorded so you trust the right thing

- A research agent concluded the push architecture is "quietly broken" because a push that
  wakes the app to re-read EventKit reads 15-minute-stale data. Sound reasoning, wrong
  target — it had inspected `predecessor iOS target`, not calarm. **calarm has a direct Google API
  client**, so a push leads to a fresh Google fetch.
- One agent claimed `MeetingProvider` in predecessor app "is already a protocol" (it is an enum).
- Four implementation agents once stalled for 600s and wrote zero files.

**Verify agent claims against primary sources before acting on them.**

---

## Apple Intelligence

Read from `FoundationModels.framework` in the iOS 27.0 SDK. Relevant only if the "make it
smarter" idea returns.

- Two variants, introspectable via `model.variant` in iOS 27: `core3` (3B dense) and
  `coreAdvanced3` (20B sparse). **You cannot request a variant.** `coreAdvanced3` needs
  12 GB RAM (community-reported). **Design for the 3B model.**
- Context window: the interface literally contains `return 4096` back-deployed for iOS
  26.0–26.3, deferring to a dynamic `_contextSize` on 27+. Read `contextSize`, never
  hard-code it.
- **Custom LoRA adapters are `obsoleted: 27.0`.** Fine-tuning on the user's calendar is
  permanently off the table.
- `SystemLanguageModel` has **no network-related error case at all**, while
  `PrivateCloudComputeLanguageModel.Error` has `networkFailure` and friends. An API that
  cannot report a network failure is not making network calls.
- **The number that should drive design decisions:** an independent audit measured **18.4%
  refusal on benign summarisation** (competitors 0%), 69.1% confabulation on false-premise
  questions, and confidence AUROC of **0.47** — worse than a coin flip — at a mean stated
  confidence of 98.8%. Never ask the model how sure it is; always have a silent non-LLM
  fallback.
- Rate limiting: **foreground unlimited, background budgeted**, throwing
  `rateLimited(resetDate:)`. The right place for inference is a charging `BGProcessingTask`
  or the foreground, never a widget extension.
- `SpotlightSearchTool` (iOS 27) has a purpose-built `ContentDomain.calendar` with a
  `similarityMatch` semantic-retrieval flag and `SearchReply.Content` cases `.count` and
  `.statistic`, so the *index* does arithmetic the model would get wrong.

**`NLEmbedding` is measurably unfit for this app.** Run against the live framework —
English sentence embeddings, distance 0–2, lower is more similar:

```
0.9913  "Weekly engineering standup"  <>  "Daily team sync meeting"
1.1065  "Weekly engineering standup"  <>  "Root canal at the dentist"
1.0884  "1:1 with manager"            <>  "one on one with my boss"
1.2915  "1:1 with manager"            <>  "Flight to Tokyo"
1.1483  "Focus time - do not book"    <>  "Design review w/ Priya (external)"
```

A near-paraphrase (1.0884) scores **worse** than a completely unrelated pair (1.1065). Word
embeddings are worse: a 57k GloVe-era vocabulary knows nothing about standup, retro, sprint,
1:1 or OOO. **Do not build event similarity on this.** Use structured features — recurrence
ID, attendee count, hour of day, organiser-is-me, duration, past dismiss/snooze counts. A
plain frequency table over `(recurrenceID, action)` will beat k-NN for months.

---

## Fixed and verified

Detailed evidence for the September 2026 sync fixes, kept because each write-up explains a
trap that can be re-entered. Shipped in `443feec`; see [CHANGELOG.md](CHANGELOG.md).

**Background sync was registered too late to exist.** `BGTaskScheduler` requires every
launch handler to be registered before `didFinishLaunchingWithOptions` returns.
`MorningSyncScheduler.register` was called from `ScheduleStore.bootstrap()`, which runs from
a SwiftUI `.task` — after launch returned. The 6am and hourly syncs were written correctly
and had **never been installed**. Both `submit` calls were also `try?` with no logging, so
failure was invisible too. This was the actual cause of "no live sync".

**The same meeting could produce two alarms.** The only dedup was
`isGoogleMirroredCalendar`, which lowercase-substring-matches `calendar.source.title` for
"google"/"gmail". A Google account added to iOS as a generic CalDAV entry titled "Work" does
not match. Now `ScheduleEventSourcePolicy.merge(eventKit:google:)` — a pure function. Google
wins collisions. The collision key is normalised title plus start time **truncated to the
minute**, because the two sources disagree by sub-second amounts on the same meeting.

**The incremental sync was structurally undefined.** The token was minted from a request
carrying `timeMax` and `orderBy`, both forbidden alongside a `syncToken`, and Google requires
every *other* parameter to match. The parameter set was **impossible to match**. Also
`timeMax` is an absolute date baked into the token, so deltas would never mention an event
past the window. Restructured so the incremental is a **change detector**: one cheap request
per calendar in steady state; the bounded expensive fetch runs only on a non-empty delta,
410, or error. The error path **fails open** deliberately.

**Every calendar ID was double percent-encoded.** Callers encoded with
`addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`, then `get()` assigned to
`URLComponents.path`, whose setter escapes the `%` again:

```
after addingPercentEncoding: team%20room@group.calendar.google.com
final URL:                   team%2520room@group.calendar.google.com
```

Only bites IDs with characters outside `.urlPathAllowed` — **which includes every Google
holiday calendar** (`en.usa#holiday@group.v.calendar.google.com`). Fixed by assigning to
`percentEncodedPath`.

**Focus blocks would have fired alarms.** calarm decoded no `eventType` at all. The owner
runs a separate Apps Script, "Focus Block Creator", that converts every solo event into
`eventType: 'focusTime'` — so their calendar is deliberately full of blocks whose entire
purpose is not being interrupted. Now filters `focusTime`, `outOfOffice`, `workingLocation`
and `birthday`. `fromGmail` is deliberately **left alertable**. Unknown values **fail open**.

**Concurrency annotations.** This target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
with `SWIFT_VERSION = 5.0`, so an unannotated `static func` or `struct` is MainActor-isolated
and **nobody has ever seen the diagnostic**. Pure helpers and DTOs need explicit
`nonisolated`. `IsolatedConformances` warnings went from 29 to 15.

---

## Known problems not fixed, and why

- **`ScheduleStore` is a ~600-line god object** with 14 `@Published` properties that
  instantiates its own services, so it cannot be constructed in a test without EventKit and
  AlarmKit. This is the structural obstacle to extending the app. Chip at it by extracting
  pure functions, as `ScheduleEventSourcePolicy` did. Do not attempt a big refactor.
- **`RescheduleCoordinator` has a narrowed but unclosed race.** `perform` cancels the
  previous task and immediately overwrites `inFlightTask` without awaiting cancellation, so
  two overlapping passes can interleave `AlarmManager` calls. The generation token guards
  only `lastSummary`, which is **written and never read**. Everything is `@MainActor` so
  interleaving only happens at `await` points and the reconcile converges — but the race is
  open and has zero tests.
- **`CalarmPersistence` grows without bound.** One override per *occurrence*, nothing prunes.
  `removeOverride` is called only from a test's `defer`. Fine at year one, not at year three.
- **Schema version 3 has no migration.** `currentSchemaVersion = 3`, the guard is
  `storedVersion < currentSchemaVersion`, and the body only handles `storedVersion < 2`.
  Harmless today, a landmine when you add step 4.
- **Google events can never show a calendar colour.** `ScheduleStore` hardcodes
  `calendarColorHex: nil` for Google events and `GoogleCalendarListEntry` never decodes
  `backgroundColor`/`colorId`. The calendar-colour tint feature silently does nothing for
  exactly the events the Google path exists to serve.
- **`CalendarSummary.colorHex` holds `cgColor?.components?.description`** — the Swift debug
  description of an array, e.g. `"[1.0, 0.5, 0.0, 1.0]"`. Never rendered, so harmless;
  `CalarmShared/CalendarColor.hexString` is the correct implementation.
- **Dead code**, confirmed zero call sites: `AlarmScheduler.managedAlarmIDs(for:)`,
  `hasActiveCountdown()`, `hasActiveUpcomingCountdown()`, `SchedulerLog.errorDetail`,
  `OpenAlarmApp`, `PauseAlarmIntent`, `ResumeAlarmIntent`,
  `CalarmDeepLink.occurrenceID(from:)`, `GoogleCalendarPreferences.lastSyncCheck`.
- **Tests mutate `UserDefaults.standard`** with no suite isolation, so running the suite
  changes the app's stored state on that machine.
- **`CalarmTests` compiles `CalarmShared/` directly into itself** *and* does
  `@testable import Calarm`, so every shared type exists twice in the test process.
  `CalendarColorTests` is silently testing the test target's copy.
- **All-day events are excluded by design** (`filter { !$0.isAllDay }`). Stated in the UI so
  it doesn't read as a bug.

### Worth stealing from predecessor iOS target

Not a recommendation to resurrect it — just where the useful bits are, in the predecessor app repo
under `ios/`:

- `AlarmPlan.swift` — a **pure, Foundation-only** alarm planner with 16 tests, each pinning
  a specific AlarmKit trap (same-minute grouping, truncation, the `preAlert: 1` landscape
  workaround). Compiled into the test target with no framework import.
- `docs/ios-app.md` — an eight-entry table of deliberate design-law departures. Note that
  line 77 claims EventKit freshness is "minutes", which is wrong — it is 15–60 minutes.
- The `CalendarSource` protocol seam, if calarm ever needs more than two sources.

---

## Primary sources

**Apple** — AlarmKit FAQ [797158](https://developer.apple.com/forums/thread/797158) ·
00:00 firing + 13k dataset [820388](https://developer.apple.com/forums/thread/820388) ·
26.2 regression [809398](https://developer.apple.com/forums/thread/809398) ·
late firing [798619](https://developer.apple.com/forums/thread/798619) ·
landscape + `preAlert` fix [806681](https://developer.apple.com/forums/thread/806681) ·
zombie Live Activity [812006](https://developer.apple.com/forums/thread/812006) ·
Island timer updates [757140](https://developer.apple.com/forums/thread/757140) ·
`.timer` over-expansion [723316](https://developer.apple.com/forums/thread/723316) ·
DTS on NSE after force-quit [808088](https://developer.apple.com/forums/thread/808088) ·
NSE limits [770880](https://developer.apple.com/forums/thread/770880) ·
background execution limits [685525](https://developer.apple.com/forums/thread/685525) ·
Critical Alerts denied [690030](https://developer.apple.com/forums/thread/690030) ·
DTS redirects to AlarmKit [812358](https://developer.apple.com/forums/thread/812358) ·
[WWDC25/230](https://developer.apple.com/videos/play/wwdc2025/230/) ·
[WWDC26/223 Live Activities](https://developer.apple.com/videos/play/wwdc2026/223/) ·
[scheduling-an-alarm-with-alarmkit](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit) ·
[AlarmPresentationState](https://developer.apple.com/documentation/alarmkit/alarmpresentationstate) ·
[pushing-background-updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) ·
[UNNotificationServiceExtension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension)

**Cloudflare / APNs** — [workerd#4841](https://github.com/cloudflare/workerd/issues/4841) ·
[Codakuma](https://codakuma.com/pushy/) ·
[FiveSheepCo/cloudflare-apns2](https://github.com/FiveSheepCo/cloudflare-apns2) ·
[Workers WebCrypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/) ·
[Workers limits](https://developers.cloudflare.com/workers/platform/limits/)

**Google** — [Calendar push guide](https://developers.google.com/workspace/calendar/api/guides/push) ·
[events.watch](https://developers.google.com/workspace/calendar/api/v3/reference/events/watch) ·
[events.list](https://developers.google.com/workspace/calendar/api/v3/reference/events/list) ·
[domain verification retired](https://support.google.com/googleapi/answer/7072069) ·
[Manage App Audience](https://support.google.com/cloud/answer/15549945?hl=en)

**Open source** — [RiseAndGrind](https://github.com/kevinjdolan/RiseAndGrind) (its
`AlarmEventJournal.swift` logs `systemUptime` and `processID` alongside wall clock — the
pattern calarm's alarm journal follows) ·
[dividing-by-zaro/blur](https://github.com/dividing-by-zaro/blur) (AlarmKit Live Activity
with all three modes) ·
[arsensgitacc/CalSync](https://github.com/arsensgitacc/CalSync) (Google Calendar API +
AlarmKit — calarm's exact architecture) ·
[mrblog/CalendarSiren](https://github.com/mrblog/CalendarSiren) ·
[bannzai/Alarmify](https://github.com/bannzai/Alarmify/issues/5) ·
[PuckAlarm](https://github.com/DanielBordencea/PuckAlarm)

**Market** — [Beacon](https://apps.apple.com/us/app/id6752361800) ·
[Show HN: Beacon](https://news.ycombinator.com/item?id=45409519) ·
[9to5Mac on KeyAlarm](https://9to5mac.com/2026/09/05/indie-app-spotlight-keyalarm-calendar-events-into-alarms/) ·
[MacRumors on iOS 26 alarm apps](https://www.macrumors.com/2025/06/11/ios-26-third-party-alarm-apps/)
