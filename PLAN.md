# Plan: getting calarm to reliable, ≤60-second calendar alarms

Written 2026-09-19, superseding the first draft of the same date. Built on the September
2026 audit in [HANDOFF.md](HANDOFF.md) plus four parallel research passes (shipping-app
market survey, open-source/GitHub survey, Cloudflare→APNs stack verification, iOS
background-execution research).

**Read section 1 first.** It corrects three conclusions in HANDOFF.md and four claims made
earlier in this session, including one of my own that was load-bearing for the
architecture recommendation.

Scope locked with the owner: **just me for now** (friends deferred), **paid Apple Developer
Program**, **≤60s freshness**, **phone available for testing**, **owner is on iOS 27.0**.

Evidence labels used throughout: **CONFIRMED** (primary source read directly), **REPORTED**
(secondhand), **INFERRED** (reasoning, flagged as such).

**Provenance caveat.** Some vendor pages were fetched through a summarizing layer, so a few
quoted strings are near-verbatim rather than guaranteed character-exact. Apple documentation,
Apple Developer Forums, GitHub source and the `itunes.apple.com/lookup` API were read
directly. Before citing any quote here externally, re-read its source URL. Also note that the
most consistently reliable evidence in the whole survey was `minimumOsVersion` from Apple's
lookup API — a floor of 26.0 is a hard tell for AlarmKit, anything lower disproves
AlarmKit-only — because vendor marketing contradicted verifiable mechanism in at least three
cases (Wake Up Broo, Bird Rise, and OnTimer's FAQ versus its own privacy policy).

---

## 1. Corrections

### 1.1 To HANDOFF.md

**Cloudflare Workers can reach APNs directly. Firebase is not needed.** The handoff
correctly established that Apps Script has no ES256 primitive, then carried that constraint
into option F without rechecking. Workers expose WebCrypto (ECDSA P-256) and their
production egress negotiates HTTP/2. Firebase, the service account, the FCM SDK and
`GoogleService-Info.plist` all leave the design. **CONFIRMED** — see 3.2.

**The Apps Script read-API (option B) cannot meet ≤60s.** Not an Apps Script failing: option
B is "the app polls the script," and iOS will not let a rarely-opened app poll in the
background. `BGAppRefreshTask` is ruled out by Apple's own documentation (see the table in
3.4). Anything under 60s with the app closed requires a push. What survives from option B is
its real prize — a single-user server can hold the Google credential, so the app needs no
Google OAuth at all. The design below keeps that and adds push.

**The visible-vs-silent push question the handoff left open is settled by the platform.** A
`UNNotificationServiceExtension` runs **only** for visible alert pushes carrying
`mutable-content: 1`; Apple's docs state "You can't modify silent notifications." If you
want code to run while calarm is dead, the push must be visible. Not a design preference.
**CONFIRMED.**

### 1.2 To claims I made earlier in this session

**"Webhook latency is 3–10 seconds" — no primary source exists.** I traced the figure to
content-marketing blogs for paid calendar-sync products. No methodology, no sample size.
Google's push documentation makes **no latency claim at all**. This matters because it was
my stated reason for ranking the Worker above Apps Script ("3–10s known vs. `onEventUpdated`
unmeasured"). **Both are unmeasured.** The ranking still holds, but on different grounds —
see 4.1.

**"AlarmKit drops 1 in 3–5 alarms overnight" — I over-corrected, twice.** First I stated it
as fact; then I called it uncorroborated. The accurate position: the *rate* is one
developer's impression and no public dataset confirms it, but the report carries technical
substance — a sysdiagnose showing `mobiletimerd` registering the XPC wake-up and `launchd`
then dropping it with nothing rescheduling (FB22887867). Treat the mechanism as credible and
the rate as unmeasured. **REPORTED.**

**"File the Critical Alerts entitlement request" — retracted.** Apple has explicitly denied
this entitlement to alarm apps, at least twice, with matching language: *"this API is not
designed for the use you've identified."* Apple DTS now redirects alarm developers to
AlarmKit instead. Zero alarm-clock apps have a public grant; every confirmed grantee is
clinical or incident-response (Dexcom, Sugarmate, PagerDuty, Opsgenie). It would also buy
nothing — AlarmKit already overrides silent mode and Focus with no entitlement.
**CONFIRMED.**

**"calarm is unusual" — wrong. There is a crowded competitive field.** See section 2. This
is the finding with the largest strategic consequence and I had no idea it existed.

**"None of the competitors do push" — wrong, one does.** I said this twice. **OnTimer**
(id6755317601) runs OAuth against Google and Outlook, holds APNs device tokens server-side,
and uses "Apple Push Notifications (to trigger background syncs)" — the architecture in
section 4, already shipping. See 2.4. The claim holds for every *EventKit-based* competitor,
which was the set I had looked at; it does not hold for the category. **CONFIRMED** from
OnTimer's privacy policy.

---

## 2. The competitive landscape — calendar→alarm is a real, crowded category

Effectively none of these existed before iOS 26, because the mechanism did not exist. All
are AlarmKit-era. **CONFIRMED** via App Store metadata and developer statements.

| App | minOS | First release | Notes |
|---|---|---|---|
| **Beacon: Calendar Alarms** | 26.1 | 2025-09-21 | Rules engine ("events with 'Interview' in the title", "meetings with 3+ attendees"). Launched €35/yr, cut to $15/yr after backlash |
| **Cal Alarms** | 26.0 | 2026-02-27 | Only one documenting its sync triggers |
| **Unmissable: Calendar Alarm** | 26.0 | 2025-09-15 | "No cloud sync… data stays on your device" |
| **Meeting Alarms: Calerto** | 26.0 | 2025-09-17 | Has accounts + Google Calendar sync ⇒ server component |
| **Timely Alarms** | 26.0 | 2025-09-15 | iCloud restore, Live Activities, Siri |
| **KeyAlarm** | — | 2026 | Keyword triggering, per-calendar. $0.99. Covered by 9to5Mac |
| **Today Planned** | 26.0 | 2023 | Pre-AlarmKit it drove **Shortcuts** to create real Clock alarms; has since raised its floor to 26.0. Whether it now uses AlarmKit is **unresolved** |
| **Fantastical** | — | 4.1.11, 2026-03 | "Urgent Alarms" on AlarmKit. See 2.2 — the most important datapoint in this section |
| **CalendarWake** | — | — | Asks users to add a **widget** so "iOS refreshes widgets periodically, which gives CalendarWake an opportunity to check for calendar changes" (INFERRED: widget timeline as a background-execution proxy) |

### 2.0 A name collision you should know about

**There is already an App Store app called `Calarm`** — squishLogic LLC, id509840570, $1.99, shipping since roughly 2012, minOS 18.0. It is pre-AlarmKit and a review states its limitation plainly: *"alerts play for a while and then stop, whereas alarm keeps going until you stop it. This app offers alerts, not alarms."* So the name is taken, by a product solving the same problem worse. **CONFIRMED.**

### 2.1 The most useful artifact found anywhere: Beacon's changelog

A year of releases, and it is almost entirely one problem — **keeping already-scheduled
alarms in sync with a mutating calendar**:

- 1.2.1 — "Manual alarms are no longer lost when their event is moved to a new time"
- 1.1.8 — "Improved alarm persistence for events further than 1 month away"
- 1.0.9 — "Fixes bug with rules not respecting changes to recurring events"
- 1.0.6 — "Duplicate events and alarms in agenda"
- 1.1.2 — shipped a **"Sync Beacon" Shortcuts action** so the user can force a sync manually

That last one is an admission: **background refresh alone is not trustworthy, and the
shipping leader in this category worked around it by handing the user a manual button.**
CalAlarms goes further and lists *"when you move between locations"* among its sync triggers
— almost certainly significant-location-change abused as a background wake (**INFERRED**).

**Every one of these bugs is a bug calarm will have.** The handoff's known-problems list
already contains the same shapes (orphaned overrides on event-ID churn, unbounded
persistence growth, the `RescheduleCoordinator` race).

### 2.2 Fantastical refused to build this on EventKit — and that validates calarm's architecture

Flexibits shipped "Urgent Alarms" on AlarmKit in Fantastical 4.1.11 (March 2026). Their own
help page states the constraints, **CONFIRMED**:

> "Calendar accounts must be added directly to Fantastical"
> "All day tasks and events do not support Urgent Alarms"
> "Special Google events (Out of Office, Focus Time, Events from Gmail) do not support
> Urgent Alarms"

Read the first line carefully. Urgent Alarms do **not** work off EventKit-delegated accounts;
they require Flexibits' own direct sync stack. **The best-resourced team in this category
declined to build alarms on EventKit.** Every indie competitor in section 2 uses EventKit.

calarm has a direct Google Calendar API client. That is the same architectural choice
Fantastical made, and it is the strongest external evidence available that it is the right
one. It also retroactively justifies the handoff's decision to keep calarm over the
EventKit-only `predecessor iOS target`.

Second line worth noting: Fantastical excludes Out of Office, Focus Time and Gmail-derived
events. calarm's §2.5 `eventType` filtering lands in the same place — except calarm
deliberately leaves `fromGmail` alertable, which on this evidence is a defensible divergence
rather than an oversight.

### 2.3 Prior art to read before writing code

[arsensgitacc/CalSync](https://github.com/arsensgitacc/CalSync) is the only open-source
artifact found that pairs the **Google Calendar API** with AlarmKit rather than EventKit —
i.e. calarm's exact architecture. Not on the App Store; source readable. Worth an hour.
[mrblog/CalendarSiren](https://github.com/mrblog/CalendarSiren) is a second open-source
reference in the same space.

### 2.4 OnTimer is already shipping the architecture in section 4

**OnTimer — Never be late** (Ethan Garr), id6755317601, **iOS 18.0+**, free + $7.99/mo. The
only app found doing real **OAuth against calendar providers instead of EventKit**, with
**server-driven push** for freshness.

From its privacy policy, **CONFIRMED** (primary source):

- OAuth 2.0 against Google Calendar and Microsoft Outlook, scopes `calendar.readonly` and
  `Calendars.Read`.
- *"We do NOT store your calendar events or personal calendar data on our servers."*
- Freshness mechanism: *"Periodically refresh your event list to ensure accuracy"* using
  **"Apple Push Notifications (to trigger background syncs)"**, with device tokens held
  server-side for that purpose.
- FAQ: *"When a meeting is rescheduled, your alarm moves too — with no action from you."*

**INFERRED:** a server watching Google's push channels, waking the app via APNs to
re-materialize alarms. That is the design in section 4, already in the App Store.

Two caveats. Its iOS 18.0 floor means it cannot be AlarmKit-only, so something else delivers
the ring below iOS 26. And **its marketing contradicts its own privacy policy** — the FAQ
claims *"OnTimer reads your calendar locally and never sends your data to any server"* and
*"completely on-device,"* which is irreconcilable with server-mediated OAuth and server-held
APNs tokens. The privacy policy is the accurate document.

**What this changes:** calarm's architecture is no longer unclaimed. It is validated by
existing in the market, and the differentiator has to be execution and the rules engine
rather than the mechanism.

### 2.5 Two shipped-failure artifacts that map onto calarm's existing work

**Timely Alarms release note — the most instructive single line found. CONFIRMED:**

> "Fixed alarms going silent after a calendar account resynced — an alarm could be left
> running that the app could no longer show or cancel."

**INFERRED (high confidence):** the signature of keying AlarmKit alarms to EventKit *local*
identifiers. When a CalDAV/Google account resyncs, EventKit reissues local IDs for the same
logical events, the alarm↔event mapping breaks, and orphaned AlarmKit alarms remain that the
app can no longer address. Unrecoverable for the user.

**Calalarm Calendar** (Devart B.V., id1590304931) — user reviews, verbatim:

> "at 10pm I was given the alarm about a 7pm meeting"
> "Now 8 hours past a Google calendar event I am finally receiving an alarm."
> "I depend on Google calendar, so maybe that is what this app is having difficulty with"

**INFERRED:** multi-hour delays correlating with Google Calendar is the classic signature of
relying on `BGAppRefreshTask`, which iOS schedules opportunistically and may defer
indefinitely. Compare handoff §2.1 — calarm's background sync was registered too late to
exist at all, which is the same failure with a different cause.

**The relevant observation:** calarm's in-flight work — `GoogleCalendarAPIClient` (provider
API instead of EventKit), `EventOccurrenceID` (stable occurrence identity instead of
reissued local IDs), `MorningSyncScheduler` and the commit *"Fix stale AlarmKit alarms firing
hours after events"* — maps onto exactly these three documented competitor failures. That is
a reason to finish it, not restart it.

### 2.6 The constraint nobody can engineer around

**Not one app in the category documents re-validating the calendar immediately before the
alarm fires.** The likely reason: AlarmKit alarms are handed to the system and fire
**without your app executing** — Troughton-Smith's CONFIRMED observation that the API
*"doesn't wake up your app."* So a true pre-fire re-check is probably **impossible by
design**. **INFERRED**, but nothing contradicts it.

Consequence for calarm: there is no fire-time safety net. The scheduled set must be correct
*in advance*, which is precisely why push-driven invalidation (section 4) is worth the
infrastructure and why short-horizon arming bounds the damage when it fails.

### 2.7 What this means

Two things, pulling in opposite directions.

**Against:** the idea is not novel, six apps shipped it a year ago, and one is a polished
paid product. If the goal were a business, that is a crowded room.

**For, with one important exception:** *almost none of them do push.* Every EventKit-based
player hit the freshness wall and **worked around** it rather than solving it — Beacon
shipped a manual Shortcuts sync action, CalendarWake piggybacks on widget timeline
refreshes, CalAlarms triggers on location changes, Today Planned leans on Shortcuts
automations. Four independent developers, four different hacks, same unsolved problem.

The exception is **OnTimer**, and it matters — see 2.4. It is already shipping calarm's
proposed architecture. Every one relies on
background refresh, manual sync buttons, or location tricks. The reconciliation problem that
consumed Beacon's entire first year is **exactly what a server-side change feed solves**. A
Worker that learns about the change in seconds and pushes does not need to guess when to
poll. **calarm's proposed architecture would be better than every shipping competitor at the
one thing the category is bad at.** That is a defensible reason to keep building, and it is
worth knowing that the differentiator is the backend, not the app.

---

## 3. What is actually verified

### 3.1 AlarmKit — Apple's promise, and the contradicting evidence

**Apple's own AlarmKit FAQ** (Developer Forums thread 797158), verbatim, **CONFIRMED**:

- Persistence: *"all alarms are expected to persist regardless of app or device state
  changes, once they are successfully scheduled"* — covers reboot, force-quit, crash.
- Focus: *"AlarmKit alarms can break through all focus modes."*
- Limits: *"There is no set number as a limit… the device may impose a limit"* →
  `maximumLimitReached`.
- A silent failure mode worth knowing: *"Hidden or passcode required apps do not work with
  AlarmKit. Currently, any scheduled alarms by such apps will silently fail."*
- No entitlement. `NSAlarmKitUsageDescription` + a user prompt is the whole gate.

**Four open forum threads contradict the persistence promise. No Apple staff reply on any.**

| Bug | Evidence | Label |
|---|---|---|
| Alarms fire **at exactly 00:00** instead of the scheduled time. *Bird Rise* dev, production data: across **~13,000 firings in 30 days**, 84% of alarms are scheduled 06:00–09:59 yet **10–15% of actual rings land in 21:00–01:00**. Persists 26.1–26.4 | thread/820388 | **CONFIRMED** |
| Alarms **stopped ringing entirely** on 26.2 beta 3/RC after upgrading from 26.1. Reproducible **with Apple's own sample code**. FB21273655 | thread/809398 | CONFIRMED |
| Alarms fire **5–45 min late or not until the phone is woken**. sysdiagnose: `mobiletimerd` registers the XPC wake-up, `launchd` drops it, nothing reschedules. FB22887867 (26), FB24483266 (27.0 RC) | thread/798619 | REPORTED |
| Alarms don't fire when a foregrounded app is in **landscape**. Affected Apple's own Reminders. **Workaround: 1-second `preAlert`** | thread/806681 | CONFIRMED |

That 13,000-firing dataset is **the only hard reliability number in the entire research
corpus**, and it comes from a developer whose own App Store copy says *"powered by the new
AlarmKit for incredibly reliable alarms."* Marketing is not evidence of mechanism, and not
evidence of reliability.

iOS 27.0 shipped 2026-09-14; its release notes mention alarms only for independent
Alarm/Timer volume and a China-specific Clock behaviour. **No AlarmKit delivery fix.** The
late-firing report explicitly covers "iOS 26.0 up through the iOS 27.0 RC."

**Two actionable consequences, both cheap:**

1. **Set `preAlert: 1` where calarm currently sets `nil`.** `AlarmScheduler.swift:521` passes
   `preAlert: nil` for every alarm without a Live Activity; `:516` passes the full
   `secondsUntilAlarm` when there is one. The retired predecessor iOS target hardcoded `preAlert: 1` and
   the handoff records it as a pinned test case — so the mitigation exists in the *retired*
   repo and is absent from the live one. Circumstantial support: Apple's Reminders app
   appears to have added a preAlert in 26.2.
2. **Verify the widget extension is properly wired.** Apple: *"AlarmKit expects a widget
   extension if an app supports a countdown presentation. Otherwise, the system may
   unexpectedly dismiss alarms and fail to alert."* calarm sets `countdownDuration` on every
   alarm and does have `CalarmWidgetExtension` — but the handoff records that the widget
   extension has **no entitlements file at all**. This is a plausible alternative
   explanation for the exact symptom gate 1 will measure.

### 3.2 Cloudflare Worker → APNs

**It works in production, via an undocumented mechanism.** Kenton Varda, Cloudflare's
Workers architect, on [workerd#4841](https://github.com/cloudflare/workerd/issues/4841):

> "workerd doesn't have HTTP/2 support, but in production it sends requests through
> Cloudflare's proxy stack which (apparently) upgrades to HTTP/2 before talking to the
> origin."

Note "(apparently)". **CONFIRMED that it works; CONFIRMED that it is undocumented.**

- **You cannot test APNs locally.** Local `workerd` has no HTTP/2, so every `wrangler dev`
  APNs call fails. Use `--remote` or deploy. Plan the dev loop around this.
- **Real corroboration:** [Codakuma](https://codakuma.com/pushy/) replaced OneSignal in a
  shipping App Store app with a ~200-line Worker doing exactly this, deleting 23,000 lines
  of SDK. Handles APNs 410 token invalidation, i.e. genuinely in production.
- **Sandbox vs production APNs endpoints differ.** A debug-build token sent to
  `api.push.apple.com` returns 410 and the token is deleted. This will eat your first
  afternoon if you don't know it.
- **Don't take the dependency.** `FiveSheepCo/cloudflare-apns2` is 22 stars, 0 issues, last
  pushed 2025-01-04. Zero issues at 22 stars means nobody uses it, not that it is solid.
  Copy its ~150-line `apns.ts` as a reference implementation.
- JWT must be cached and regenerated ~every 55 minutes; Apple rejects tokens over an hour
  old **and** rate-limits frequent minting.

### 3.3 Google Calendar `events.watch`

- **Domain verification is genuinely gone.** Google: *"Domain verification in the API Console
  is no longer required."* The only stated requirement on the receiving URL is a valid
  publicly-trusted TLS certificate. **CONFIRMED.**
- **Nobody has publicly pointed `events.watch` at a `*.workers.dev` URL.** It should work —
  no mechanism remains by which Google would reject it — but `"Unauthorized WebHook callback
  channel"` is still a live failure mode with folklore rather than diagnosis around it.
  **INFERRED.** Ten-minute de-risk: make one `events.watch` call and see. A custom domain on
  the Worker removes the question entirely and costs nothing.
- **The webhook carries no body.** Just "something changed" in headers. The Worker must do an
  OAuth refresh **plus** an incremental `events.list` before it can build a push. Two Google
  round trips on the critical path — that is probably where the real latency lives, not in
  the webhook hop. **CONFIRMED.** This changes the latency budget.
- **Channels expire after 7 days (default TTL 604800) with no warning, no error, no
  callback — just silence.** Renewal is entirely yours. **CONFIRMED.**
- **How practitioners actually handle it:** Pipedream requests a **24-hour** TTL and renews at
  95% of it (~22.8h). `todoist-calendar-sync` renews every 12 hours against the 7-day TTL
  *and* built a liveness monitor. Two unrelated production systems both renewing 7–14× more
  often than required, one with explicit liveness tracking, tells you renewal failure is
  common and **detection is the actual engineering problem**.
- **Cloudflare Cron Triggers have no automatic retries by design.** A throw or timeout is
  gone until the next tick. Combined with silent channel expiry, two consecutive cron
  failures = the alarm app stops working and nothing tells you. **This is a correctness
  problem, not an inconvenience.**
- **Nobody has published a real latency measurement.** See 1.2.

### 3.4 What actually runs your code while the app is force-quit

Only three mechanisms, plus AlarmKit itself in a different category.

| Mechanism | Wakes force-quit app? | Precise timing? | Verdict |
|---|---|---|---|
| **Visible push → `UNNotificationServiceExtension`** | **YES** (the extension runs, not the app) | YES, server-timed | **The path.** Apple-endorsed |
| **Push-to-start Live Activity** | **YES** — documented to "wake up your app, and grant it background runtime" | YES, server-timed | Viable second call site; entry point is the widget extension, not the app delegate |
| **PushKit / VoIP push** | Yes | YES | **Trap.** iOS kills a non-VoIP app that doesn't report a call, then stops launching it at all |
| AlarmKit (pre-scheduled) | Fires regardless of app state | Intended; see 3.1 | Different category — it doesn't wake you, it fires on your behalf |
| Silent push (`content-available`) | **NO** — "If something force quits or kills the app, the system discards the held notification" | No | Ruled out |
| `BGAppRefreshTask` / `BGProcessingTask` | **NO** — force-quit sets a flag preventing background launch | No | Ruled out |
| `BGContinuedProcessingTask` (26) | **NO** — "starts in the foreground" by definition | N/A | Ruled out |
| Silent audio session | **NO** — force-quit terminates it | N/A | Also an App Store rejection risk (3.5) |
| Widget timeline reload | Extension only; "Widgets cannot perform tasks in the background" | No | Ruled out |
| Region / significant-location | Documentation conflicts; unreliable | **No** — not time-triggered | Ruled out for our purpose |

**Apple DTS, verbatim, on running code after a force-quit:**

> "If you have to, you can use a Notification Service Extension… The Notification Service
> Extension will be executed for every *visible* push notification… The service extension
> will *not* be executed for push notifications that will not be presented visually."

NSE constraints, from an Apple DTS engineer: **30 seconds, 24 MB**, and *"cannot directly
communicate with the main app except via a shared container."* That makes **App Groups a
hard prerequisite** — currently handoff to-do item 6, and the entitlements file has only
`com.apple.developer.siri`.

**The big result, measured rather than searched:** there is **no compile-time barrier** to
calling AlarmKit from an extension. Every `@available(... unavailable)` annotation in the
entire AlarmKit `.swiftinterface` is `macCatalyst`; there are **zero**
`iOSApplicationExtension, unavailable` markers. A real `AlarmManager.shared.schedule()` call
typechecks clean under `-application-extension`, with `UIApplication.shared` failing as a
control. **CONFIRMED by direct experiment on this machine.** What remains unknown is runtime
XPC/sandbox policy and whether authorization resolves for an extension caller — both cheap
to test.

Prior art: [bannzai/Alarmify](https://github.com/bannzai/Alarmify/issues/5) states its
delivery route as "Notification Service Extension / background push / ActivityKit" to
"reflect alarm requests arrived via push into AlarmKit." No verdict recorded; read the code.

### 3.5 How the competition actually wakes people (and why it doesn't apply to us)

- **Alarmy** uses AlarmKit only as a *degraded fallback*: app alive ⇒ your chosen sound via
  its own `AVAudioSession`; app killed ⇒ generic system tone. Its support docs, updated
  2026-09-19, still say *"Do not force close Alarmy app."*
- **Sleep Cycle** is pre-AlarmKit and structurally cannot adopt it — *"you will still have to
  unlock the device to turn off the alarm."* It holds an all-night mic session for sleep
  tracking and gets alarm delivery free. It ships a "Battery alarm" as a safety net, which is
  an admission the mechanism dies with the process.
- **The silent-audio-loop technique is still being rejected by App Review in 2025.**
  Guideline 2.5.4; the boilerplate reads *"did not include features that require persistent
  audio."* Approvals exist but are reviewer-dependent appeals, not policy. **INFERRED:** the
  winning appeal argument was always "local notifications can't bypass silent/DND" — AlarmKit
  removes that argument on iOS 26+.

**Conclusion: AlarmKit is the only sanctioned path, and calarm is already on it.** The
alternatives are worse, not better.

---

## 4. Target architecture

Unchanged in shape from the first draft; the research tightened the details and killed the
alternatives.

```
Google Calendar
   │  events.watch webhook  (latency UNMEASURED — see gate 3)
   ▼
Cloudflare Worker  ── holds the refresh token (single-tenant)
   │                 ── owns + renews the watch channel (hourly cron + liveness alert)
   │                 ── OAuth refresh + incremental events.list  ← the real latency
   │                 ── hourly poll as the dropped-notification backstop
   │
   ├── APNs direct (ES256/WebCrypto, no Firebase)
   │      └──► VISIBLE time-sensitive push, mutable-content: 1
   │             └──► NSE re-arms alarms  [GATED on experiment 2]
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
radius. That last item is handoff option A and remains the highest value-per-hour work in
the project.

### 4.1 Why the Worker over Apps Script, now that the latency argument is void

Both latencies are unmeasured, so the original reason is gone. What remains:

- **One component instead of two.** Apps Script would still need a Worker to sign APNs.
- **Apps Script's `onEventUpdated` gives you a doorbell with no letter** — same as the
  webhook — but adds a 90 min/day trigger-runtime cap on a consumer account.
- **It survives the friends pivot.** The Worker scales to multi-tenant; per-user Apps Script
  deployments do not.

`apps-script/Relay.gs` already exists and implements both paths, so the alternative keeps a
head start if Cloudflare turns out to be unwelcome. **Pipedream is out**: its instant trigger
"does not emit cancelled events," and a deleted meeting is precisely the event an alarm app
most needs.

### 4.2 Cost and what rots

$0. Cloudflare free tier is not stressed; Google's quota is 600 req/min/user and this uses a
rounding error of it. The only thing that rots is the watch channel, and the mitigation is
hourly renewal **plus liveness alerting** — not renewal alone, because cron has no retries.

---

## 5. The plan

### Gate 1 — Does AlarmKit fire reliably on this phone? (BLOCKING, ~1 day elapsed)

The dominant risk, and now better motivated: a production dataset of ~13,000 firings shows
10–15% landing in the wrong window, and the late-firing report covers iOS 27.0 RC.

Harness: arm ~10 alarms across a day and **overnight on a locked, uncharged phone** — the
condition every report points at. Record intended vs. actual.

**Design constraints discovered in research, all of which the harness must respect:**

- `alarmUpdates` is **in-process**. It cannot observe a fire on a phone where calarm has been
  killed since midnight. Reconcile **on next launch**, not live. (Independently confirmed
  against calarm's own `AlarmUpdatesObserver`.)
- `try? AlarmManager.shared.alarms` **cannot distinguish "framework broken" from "nothing
  scheduled."** The harness needs its own durable intent ledger.
- AlarmKit **silently deletes spent one-shot alarms**. Disappearance is normal, not a miss.
- AlarmKit **rejects `schedule` for a UUID it already holds** — cancel before re-scheduling.
- **Cancelling a ringing alarm silently ends the wake-up** — a naive "reconcile everything on
  launch" pass is dangerous, since launch-during-ringing is a likely state.
- `maximumLimitReached` is real. Budget alarm slots; any redundancy strategy has a ceiling.

Prior art to copy: [RiseAndGrind](https://github.com/kevinjdolan/RiseAndGrind)'s
`AlarmEventJournal.swift`, which logs `systemUptime` and `processID` alongside wall-clock
time — that is how you detect a killed-and-relaunched process or a clock change. **No
open-source project computes `actualFireDate − intendedFireDate`.** Gate 1 is original work.

Also check here, in the same run, two cheap unknowns:

- **Whether any alarm armed *before* the iOS 27 upgrade is silently dead** (FB21273655).
- **AlarmKit's practical scheduling horizon and concurrent-alarm ceiling.** Apple says only
  that there is no fixed number but the device may impose one, surfacing
  `maximumLimitReached`. Beacon shipped *"improved alarm persistence for events further than
  1 month away"*, which implies a real horizon problem exists. For an app that pre-arms many
  calendar events this is load-bearing, and it is faster to measure than to research.

- **Fires reliably** → proceed. Freshness is the real problem and the plan holds.
- **Reproduces** → stop and fix the alert layer first: `preAlert: 1`, verify the widget
  extension, then consider a redundant pre-alarm notification. Sync moves to the back.

### Gate 2 — Can the NSE arm an alarm while the app is dead? (~1 afternoon)

Compile-time is proven clear (3.4). Three runtime questions:

1. Does `AlarmManager.shared.schedule()` succeed inside an NSE? Distinguish **throws**,
   **silently no-ops**, and **works** — watch Console for `alarmd`, `apsd`, and the extension
   process.
2. Does `authorizationState` resolve for an extension caller? `NSAlarmKitUsageDescription`
   lives in the *app's* Info.plist. If the NSE reports `.notDetermined` while the app reports
   `.authorized`, the path is dead.
3. Same two questions for the **widget extension**, which given AlarmKit's structural
   coupling to a widget may be the intended call site.

Prerequisite: **App Groups**, since a shared container is the only sanctioned NSE↔app IPC.
Also set file protection to `.completeUntilFirstUserAuthentication` or container writes fail
on a cold-booted locked phone.

- **Yes** → complete solution; a calendar change re-arms alarms with the app never opened.
- **No** → the visible push still delivers a tappable "your schedule changed" banner, and the
  app re-arms on tap. Most of the value, a fraction of the work.

### Gate 3 — Stand up the Worker and measure edit-to-buzz (~2 hrs)

Single-tenant Worker, personal Google account. First action, before any code: one
`events.watch` call against a `*.workers.dev` URL to settle 3.3.

Then measure the full chain — calendar mutation → webhook → OAuth refresh → `events.list` →
JWT sign → APNs → device — and confirm <60s. **Log each hop separately**, since the two
Google round trips are the suspect, not the webhook. Run it ~100 times across a day.

**Nobody has published this number. It would be the first public data.**

### Then, the app work

1. Short-horizon arming (24–48h) + visible "synced N min ago". No gate depends on it.
2. Rip out GoogleSignIn/AppAuth; point at the Worker read endpoint.
3. Push handler + APNs device-token registration.
4. Whatever gate 1 forces on the alert layer.

### Independent of all gates, do now

- **`preAlert: 1` where it is currently `nil`** (3.1). One line, cheapest available
  mitigation.
- **Verify the widget extension is wired** (3.1). Possible silent alarm-dismissal cause.
- **Review and commit the uncommitted September work.** 10 files, 467 insertions, 58 tests
  passing, 5 real bugs fixed including the background-sync registration bug. It is sitting
  untracked; the owner's read of the diff is the only thing blocking it.
- ~~File the Critical Alerts entitlement request~~ — **retracted, see 1.2.**

---

## 6. Open questions

1. **Cloudflare account** — existing or new signup? Free tier suffices.
2. **Does the friends pivot come back?** The Worker survives it; the Apps Script alternative
   does not. Cheaper to know before the Worker is written.
3. **Given the competitive field (section 2), is the goal still to build this?** Note also
   that the name `Calarm` is already taken on the App Store (2.0), which matters only if
   this ever ships publicly. The
   honest case for yes: none of them do push, the reconciliation problem that consumed
   Beacon's entire first year is exactly what a server-side change feed solves, and
   Fantastical's refusal to build on EventKit (2.2) says calarm's direct-API architecture is
   the right one. The honest case for no: KeyAlarm is $0.99.
4. **The visible push text.** Now that a visible push is mandatory (1.1), its content is the
   only lever left. It should say *what changed* — information the alarm itself cannot carry.

---

## 7. Primary sources

**Apple** — AlarmKit FAQ [forums/797158](https://developer.apple.com/forums/thread/797158) ·
00:00 firing + 13k dataset [820388](https://developer.apple.com/forums/thread/820388) ·
26.2 regression [809398](https://developer.apple.com/forums/thread/809398) ·
late firing [798619](https://developer.apple.com/forums/thread/798619) ·
landscape + `preAlert` fix [806681](https://developer.apple.com/forums/thread/806681) ·
DTS on NSE after force-quit [808088](https://developer.apple.com/forums/thread/808088) ·
NSE limits [770880](https://developer.apple.com/forums/thread/770880) ·
background execution limits [685525](https://developer.apple.com/forums/thread/685525) ·
Critical Alerts denied to alarm apps [690030](https://developer.apple.com/forums/thread/690030) ·
DTS redirects to AlarmKit [812358](https://developer.apple.com/forums/thread/812358) ·
[WWDC25/230](https://developer.apple.com/videos/play/wwdc2025/230/) ·
[scheduling-an-alarm-with-alarmkit](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit) ·
[pushing-background-updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) ·
[UNNotificationServiceExtension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension)

**Cloudflare / APNs** — [workerd#4841](https://github.com/cloudflare/workerd/issues/4841) ·
[Codakuma](https://codakuma.com/pushy/) ·
[FiveSheepCo/cloudflare-apns2](https://github.com/FiveSheepCo/cloudflare-apns2) ·
[Workers WebCrypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/) ·
[Workers limits](https://developers.cloudflare.com/workers/platform/limits/)

**Google** — [Calendar push guide](https://developers.google.com/workspace/calendar/api/guides/push) ·
[events.watch](https://developers.google.com/workspace/calendar/api/v3/reference/events/watch) ·
[domain verification retired](https://support.google.com/googleapi/answer/7072069) ·
[Manage App Audience](https://support.google.com/cloud/answer/15549945?hl=en)

**Open source** — [RiseAndGrind](https://github.com/kevinjdolan/RiseAndGrind) ·
[PuckAlarm](https://github.com/DanielBordencea/PuckAlarm) ·
[bannzai/Alarmify](https://github.com/bannzai/Alarmify/issues/5) ·
[gdelataillade/alarm#87](https://github.com/gdelataillade/alarm/discussions/87) (App Review experiences)

**Market** — [Beacon](https://apps.apple.com/us/app/id6752361800) ·
[Show HN: Beacon](https://news.ycombinator.com/item?id=45409519) ·
[9to5Mac on KeyAlarm](https://9to5mac.com/2026/09/05/indie-app-spotlight-keyalarm-calendar-events-into-alarms/) ·
[MacRumors on iOS 26 alarm apps](https://www.macrumors.com/2025/06/11/ios-26-third-party-alarm-apps/)
