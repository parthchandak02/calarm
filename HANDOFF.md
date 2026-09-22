# Handoff: calarm, September 2026

Written at the end of a long session that audited this repo end to end, fixed five real
bugs, and researched the architecture question it had stalled on. If you are the next
agent or the next human, read sections 1 to 4 before touching anything. Section 3 exists
specifically so you do not repeat research I already did, and section 4 exists so you do
not repeat conclusions I reached and then *disproved*.

Everything in here is either verified against a primary source (SDK header, Swift
[redacted]
Where I state a fact, I read it. Where I am inferring, I say so.

---

## 1. State of play

**The verdict on this repo: extend it, do not rewrite it.** 6,590 Swift lines, 57 files,
23 commits, reached TestFlight in August 2026. The expensive, hard-won part — AlarmKit
lifecycle reconciliation — is done and done well. Around it sits a complete release
pipeline, accurate privacy manifests and a coherent design system. Rewriting means
re-earning several bug-fix cycles that are documented in the commits, the code comments
and the twelve `.cursor/skills`.

**Decision made this session: calarm is the iPhone app going forward.** A separate
`predecessor iOS target` target was built in the predecessor app repo earlier the same day (AlarmKit + Live
Activity + EventKit, 28 files) and is **retired**. The two were substantially the same
app, and calarm was far ahead. Do not resurrect `predecessor iOS target`. If you need something from
it, the useful parts are named in section 9.

**Decision made this session: calarm targets a personal Google calendar, not
[redacted]
you must read before proposing anything that reads the work calendar.

**Working tree state: everything from this session is uncommitted.** Nothing was
committed and nothing was deployed to any Google account. `git diff --stat` shows 10 files
changed, 467 insertions, 99 deletions, plus two untracked additions
(`CalarmTests/GoogleCalendarSyncParameterTests.swift` and `apps-script/`).

**Test state: 58 tests, 0 failures.** Was 36 at the start of the session.

---

## 2. What I changed, and the evidence

Run this to reproduce. There is no Xcode GUI anywhere in the loop, which is a hard
constraint from the repo owner — this Mac is RAM-constrained and the GUI is not welcome.

```bash
UDID=$(xcrun simctl create "calarm-tmp" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcodebuild test -project Calarm.xcodeproj -scheme Calarm \
  -destination "id=$UDID" -only-testing:CalarmTests CODE_SIGNING_ALLOWED=NO
xcrun simctl delete "$UDID"
```

Note the runtime: this machine has iOS 18.6, 26.4 and 26.5 simulator runtimes. **There is
no iOS 27 runtime installed**, so you cannot test iOS 27-only API on a simulator here.
The iOS 27.0 *SDK* is present and readable, which is how the SDK facts in section 3 were
verified.

### 2.1 Background sync was registered too late to exist

**The single highest-value fix in the repo, and it was one line in the wrong place.**

`BGTaskScheduler` requires every launch handler to be registered before
`didFinishLaunchingWithOptions` returns. `MorningSyncScheduler.register` was being called
from `ScheduleStore.bootstrap()`, which runs from a SwiftUI `.task` — after launch has
returned. `AppDelegate.didFinishLaunchingWithOptions` returned `true` and did nothing
else.

Consequence: the 6am morning sync and the hourly sync were **written correctly and had
never been installed**. Both `BGTaskScheduler.shared.submit` calls were also `try?` with
no logging, so submission failure was invisible too. This is the actual cause of the
owner's complaint that there was "no live sync" and "no intelligent automation" — the
automation existed and was never invoked.

Fixed in `Calarm/AppDelegate.swift` (registers) and
`Calarm/Services/MorningSyncScheduler.swift` (registration split from the reload closure,
which the store now hands over separately via `setReloadHandler`). Both submits are now
logged `do/catch`.

### 2.2 The same meeting could produce two alarms

`ScheduleStore.reload()` merged EventKit and Google events inline, and the only dedup was
`CalendarService.isGoogleMirroredCalendar`, which lowercase-substring-matches
`calendar.source.title` for "google" or "gmail". A Google account added to iOS as a
generic CalDAV entry titled "Work" does not match. The same meeting then arrives through
both paths with different identifiers, becomes two `ScheduleEvent`s with two different
`stableAlarmID`s, and rings twice with two independent bell toggles.

Extracted to a pure `ScheduleEventSourcePolicy.merge(eventKit:google:)`. Google wins
collisions because it is the fresher source when connected. The collision key is
normalised title plus start time **truncated to the minute** — the two sources disagree by
sub-second amounts on the same meeting, so exact `Date` equality lets every duplicate
through.

Seven new tests, including three negative cases so the dedup does not eat genuine
back-to-back meetings or distinct overlapping ones.

### 2.3 The incremental sync was structurally undefined

This one took two passes to diagnose and I got it wrong the first time. See section 4.1
for the wrong version so you do not repeat it.

`GoogleCalendarService.fetchUpcomingEvents` did a full window fetch **and** an incremental
fetch, per calendar, on every sync. The incremental could only ever return what the full
fetch had already returned, so it was strictly extra work. Worse, the token was minted
from a request carrying `timeMax` and `orderBy=startTime`, both of which Google forbids on
a request carrying a `syncToken` — and Google requires every *other* parameter to match
the initial sync. So the parameter set was **impossible to match**, putting every delta in
Google's documented "undefined behavior" bucket. And `timeMax` is an absolute date baked
into the token, so deltas would never have mentioned an event scheduled past the window.

Restructured:

- New `GoogleCalendarAPIClient.listFullSyncEvents` is the only token-minting call:
  `timeMin` only, no `timeMax`, no `orderBy`, `singleEvents=false`. That last one matters —
  with `singleEvents=true` and no `timeMax`, Google expands every recurrence for all time
  and one daily standup becomes thousands of rows.
- A shared `syncParameters` constant is used by both the full sync and the incremental, so
  they cannot drift apart again.
- `fetchUpcomingEvents` now uses the incremental as a **change detector**. Steady state is
  one cheap request per calendar; the expensive bounded `singleEvents=true` fetch runs only
  when a delta is non-empty, on 410, or on an error. The error path **fails open**
  deliberately: treating an unknown delta state as "nothing changed" costs a missed
  meeting, which is this app's worst outcome.
- `applyIncrementalEvents` and its `occurrenceID(for:calendar:)` helper were deleted. With
  `singleEvents=false` the deltas are recurrence parents, not mappable occurrences.

Nine new tests in `CalarmTests/GoogleCalendarSyncParameterTests.swift`, using the
injectable `URLSession` that `GoogleCalendarAPIClient` has always accepted and **nothing
had ever used**. That unused seam is exactly what would have caught this a year ago. The
sharpest test asserts the two requests agree on every parameter except `timeMin` and
`syncToken`.

### 2.4 Every calendar ID was double percent-encoded

Found by accident while writing the tests above, which is the argument for writing them.

`GoogleCalendarAPIClient` callers encode the calendar ID with
`addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`, then `get()` assigned the
result to `URLComponents.path` — whose setter escapes the `%` again. Reproduced in
isolation:

```
after addingPercentEncoding: team%20room@group.calendar.google.com
final URL:                   team%2520room@group.calendar.google.com
```

Only bites IDs containing characters outside `.urlPathAllowed` — **which includes every
Google holiday calendar**, since those are named like
`en.usa#holiday@group.v.calendar.google.com`. Subscribing to one silently requested a
calendar that does not exist. Fixed by assigning to `percentEncodedPath`, with a test
pinning the `#` case specifically and asserting the URL has no fragment.

### 2.5 Focus blocks would have fired alarms

calarm decoded no `eventType` at all. Zero matches for `eventType`, `focusTime`,
`outOfOffice`, `workingLocation` or `created` across all 57 Swift files. The predecessor app **macOS**
app has always filtered these (`predecessor app/Models/MeetingEvent.swift:146`); the Google path
here never did.

This is not theoretical for this owner. They run a separate Apps Script, "Focus Block
Creator", that converts every solo event on their calendar into `eventType: 'focusTime'`.
So their calendar is deliberately full of focus blocks, and calarm would have fired an
AlarmKit alarm — the loudest thing a third-party iOS app can do — for each block whose
entire purpose is not being interrupted.

Added `eventType` and `created` to `GoogleCalendarEvent`, plus
`GoogleCalendarEvent.isAlertableEventType` filtering `focusTime`, `outOfOffice`,
`workingLocation` and `birthday`. `fromGmail` is deliberately **left alertable** — a flight
or restaurant booking Google extracted from mail is exactly the kind of thing worth waking
for. Unknown and absent values **fail open**, because Google adds event types over time and
silently swallowing a new one means a missed meeting, which is strictly worse than one
extra alarm. Six new tests. Wired into `mapEvent` at
`Calarm/Services/GoogleCalendarService.swift:213`.

### 2.6 Concurrency annotations, which matter for the Swift 6 migration

This target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with `SWIFT_VERSION = 5.0`.
Consequence: an unannotated `static func` or `struct` is MainActor-isolated, and because
the language mode is 5.0 **nobody has ever seen the diagnostic**. Pure helpers and DTOs
need an explicit `nonisolated` or they cannot be called from a `map` closure or a
background decode.

Marked `nonisolated`: the three functions in `ScheduleEventSourcePolicy`, the six DTOs in
`GoogleCalendarModels.swift`, and `CalarmShared/EventOccurrenceID`. Each carries a comment
explaining why, because "why is this annotated" is the first question a future reader asks.

Net effect on the build: `IsolatedConformances` warnings went from **29 to 15** across the
project. Marking the DTOs `nonisolated` fixed pre-existing ones elsewhere too, since those
types are used project-wide.

---

## 3. Verified facts, with provenance

Everything here I read myself. Cite these rather than re-researching them. Where a claim
is community-sourced or inferred, it says so.

### 3.1 AlarmKit (iOS 27.0 SDK)

Read from
`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/AlarmKit.framework/Modules/AlarmKit.swiftmodule/arm64e-apple-ios.swiftinterface`.

- **There is no pre-fire hook. Nothing wakes the app when an alarm fires.** The complete
  observation surface is `alarms` (synchronous snapshot), `alarmUpdates` (an **in-process**
  `AsyncSequence`, so it needs your process already alive and iterating),
  `authorizationUpdates`, and tap-driven `stopIntent` / `secondaryIntent`.
- iOS 27 added exactly one thing: `appEntityIdentifier: AppIntents.EntityIdentifier?` on
  `AlarmConfiguration.init/timer/alarm`. That is Siri/Spotlight entity linkage, not a
  callback.
- `Alarm.State` is `{scheduled, countdown, paused, alerting}`.
- `AlarmPresentation.Alert.title` is a `LocalizedStringResource`, so a runtime-generated
  title needs `LocalizedStringResource(stringLiteral:)` and loses localisation.
- **There is no `com.apple.developer.alarmkit` entitlement.** The gate is
  `NSAlarmKitUsageDescription` plus `requestAuthorization()`. Most public write-ups claim
  otherwise; an Apple engineer has publicly noted that language models keep inventing it.

**COMMUNITY-REPORTED, single source, unverified and important:** AlarmKit alarms are
reported to fire late or not at all until the device is woken, across iOS 26.0 through the
iOS 27.0 RC. I could not corroborate this beyond one source. **If it is true on the
owner's hardware, freshness is the wrong problem** and all the architecture work below is
polishing the input to a mechanism that misfires. See section 6, experiment 3.

### 3.2 EventKit

- **Zero new API in iOS 26 or 27.** I grepped every header in `EventKit.framework/Headers`
  for `API_AVAILABLE(ios(26` and `ios(27` — no matches. Nothing has improved and nothing is
  coming.
- `refreshSourcesIfNecessary` is weaker than most people assume. Verbatim from
  `EKEventStore.h`: *"Cause a sync to potentially occur taking into account the necessity
  of it. […] On iOS and macOS, this sync only occurs if deemed necessary."* It is a hint the
  daemon may decline. No completion handler, no error, no force-sync equivalent to
  Calendar.app's pull-to-refresh.
- Realistic worst-case staleness for a Google account is **15–60 minutes**, unbounded in
  Low Power Mode. CalDAV has no push in the protocol and Google implements none, so iOS
  polls.

### 3.3 Google Calendar API sync tokens

The rule most people get backwards, from the
[Events: list reference](https://developers.google.com/workspace/calendar/api/v3/reference/events/list):

- `nextSyncToken` response field: *"Omitted if further results are available, in which case
  `nextPageToken` is provided."* **That is the only documented omission condition.** Query
  parameters do not suppress it.
- The restriction runs the other way. Forbidden on a request that **sends** a `syncToken`:
  `iCalUID`, `orderBy`, `privateExtendedProperty`, `q`, `sharedExtendedProperty`,
  `timeMin`, `timeMax`, `updatedMin`.
- And: *"All other query parameters should be the same as for the initial synchronization
  to avoid undefined behavior."* This is the clause calarm violated.
- `timeMin` **is** allowed on the token-minting request and does not suppress the token.
  Google's own sync guide sample passes it.
- 410 GONE means clear local state and full sync.
- Quota: 600 requests/min/user, 1,000,000/day/project. A 30-second incremental poll is
  0.33% of the per-user ceiling. **Quota is a non-issue**; you could poll every 5 seconds.

### 3.4 Google Calendar push, and the cost line that is wrong everywhere

- `events.watch` supports only `web_hook` channels to a CA-signed HTTPS URL. **A phone can
  never be the target.**
- **Domain verification is no longer required.** Verbatim from Google:
  *"Domain verification in the API Console is no longer required to make push notifications
  work with your domains."* The old instructions on that page are explicitly marked
  obsolete. Consequence: a free `*.workers.dev` subdomain satisfies the only remaining
  requirement, so **the commonly-cited "$10/yr domain" cost for a Worker relay is wrong**.
- Channels expire (~7 days, `params.ttl` default 604800) and there is no automatic renewal.
- **Google Workspace Events API does not support Calendar.** It covers Chat, Drive and Meet.
  Gmail has `users.watch` → Pub/Sub; Calendar has webhook only. No FCM integration, no
  streaming. Calendar API release notes through mid-2026 contain nothing about push.
- Google's own admission about this delivery machinery: *"Notifications are not 100%
  reliable. Expect a small percentage of messages to get dropped under normal working
  conditions."*

### 3.5 Google Apps Script

- `CalendarTriggerBuilder` has exactly two methods, `onEventUpdated()` and `create()`.
  `onEventUpdated()` *"Specifies a trigger that fires when a calendar entry is created,
  updated, or deleted."*
- **The handler receives `{authMode, calendarId, triggerUid}` and nothing else.** Google:
  *"These triggers do not tell you which event changed or how it changed. Instead, they
  indicate that your code needs to do an incremental sync operation to pick up recent
  changes to the calendar."* The trigger is a doorbell; `syncToken` is the letter.
- **Apps Script cannot talk to APNs. Blocked twice.** `Utilities` exposes only
  `computeRsaSha1Signature`, `computeRsaSha256Signature`, `computeHmacSha256Signature`,
  `computeHmacSignature` and `computeDigest` — **there is no ECDSA/ES256/P-256 primitive
  anywhere in the runtime**, and APNs auth tokens require ES256. `UrlFetchApp` also has no
  protocol-version or client-certificate parameter, and APNs mandates HTTP/2.
- **FCM is the way through**, because Google service accounts sign **RS256**, which
  `computeRsaSha256Signature` does. FCM owns the APNs hop.
- **`doGet` cannot read request headers, ever.** Google declined the feature in 2023 citing
  security, closing a request open since 2017. A shared secret must travel in the query
  string. Avoid the parameter names `c` and `sid`, which are reserved and return HTTP 405.
- Quotas, consumer (gmail.com) vs Workspace: **triggers total runtime 90 min/day vs 6
  hr/day**; script runtime 6 min/execution; UrlFetch 20,000/day vs 100,000/day; 20 triggers
  per user per script; 30 simultaneous executions. **There is no documented limit on inbound
  requests to a published web app.**
- Apps Script on its **default** Cloud project is exempt from the 7-day refresh-token death
  that applies to OAuth clients in "Testing" status, because Google exempts it so triggers
  can run unattended. **Attaching your own Cloud project with a Testing consent screen
  reintroduces that clock.**
- Deployment URLs: editing an **existing** deployment keeps the URL; **"New deployment"
  mints a new ID and URL** and your shipped app keeps calling the old one.
- Failure emails from a throwing trigger **cannot be switched off** without deactivating the
  trigger.
- **NOT FOUND, and it is the one load-bearing number:** nobody has published
  `onEventUpdated` latency. No SLA, no measurement, in docs or community. See section 6,
  experiment 1.

### 3.6 Apple Intelligence, for the "make it smarter" question

Read from `FoundationModels.framework`'s Swift interface in the iOS 27.0 SDK (3,647 lines).

- The framework is real and matured in one cycle. `SystemLanguageModel`,
  `LanguageModelSession`, `@Generable`/`@Guide` macros, `Tool` protocol,
  `GenerationOptions`.
- Two variants, introspectable via `model.variant` in iOS 27: `core3` (3B dense) and
  `coreAdvanced3` (20B sparse). **You cannot request a variant** — you get what the device
  has. `coreAdvanced3` needs 12 GB RAM, i.e. iPhone 17 Pro / Air only (community-reported;
  Apple publishes no device list). **Design for the 3B model.**
- Context window: the interface literally contains `return 4096` back-deployed for iOS
  26.0–26.3, deferring to a dynamic `_contextSize` on 27+. Read `contextSize`, never
  hard-code it.
- `PrivateCloudComputeLanguageModel` is public API in iOS 27, but eligibility requires the
  App Store Small Business Program and **fewer than 2 million lifetime downloads across any
  of your apps**, with no paid tier. Moot for a personal app, and not needed — nothing this
  app wants requires a 32K window.
- **Custom LoRA adapters are `obsoleted: 27.0`.** Fine-tuning Apple's model on the user's
  calendar is permanently off the table.
- Structural privacy evidence: `SystemLanguageModel` has **no network-related error case at
  all**, while `PrivateCloudComputeLanguageModel.Error` has `networkFailure`,
  `serviceUnavailable` and `quotaLimitReached`. An API that cannot report a network failure
  is not making network calls.
- **The number that should drive design decisions:** an independent audit measured **18.4%
  refusal on benign summarisation** (competitors 0%), 69.1% confabulation on false-premise
  questions, and confidence AUROC of **0.47** — worse than a coin flip — at a mean stated
  confidence of 98.8%. Never ask the model how sure it is, and always have a silent
  non-LLM fallback.
- Rate limiting: **foreground is unlimited; background is budgeted** and exceeding it throws
  `rateLimited(resetDate:)`. Community measurement: ~4 requests 30s apart hit the limit.
  Apple says rate limiting is not expected while charging. So the right place for inference
  is a charging `BGProcessingTask` or the foreground, never a widget extension.
- `SpotlightSearchTool` is new in iOS 27 and has a **purpose-built calendar domain**:
  `ContentDomain.calendar`, with `Calendar.organizer/.attendees/.location/.date`, a
  `similarityMatch` semantic-retrieval flag, and `SearchReply.Content` cases `.count` and
  `.statistic` so the *index* does arithmetic the model would get wrong.
- Siri: `AssistantSchemas` was **renamed `AppSchema`** in iOS 27, leaving deprecated marker
  protocols at the old name. Both relevant domains exist —
  `AppSchema.CalendarIntent` (CreateEvent/UpdateEvent/DeleteEvent, no *search* schema) and
  `AppSchema.ClockIntent` (CreateAlarm/UpdateAlarm/DeleteAlarm/**DismissAlarm**/**SnoozeAlarm**),
  plus `EventEntity`, `CalendarEntity`, `AttendeeEntity`, `AlarmEntity`. Reading requires
  conforming to `IndexedEntity`, since there is no calendar read schema.
- **`NLEmbedding` is measurably unfit for this app.** I ran it against the live framework.
  English sentence embeddings, distance 0–2, lower is more similar:

  ```
  0.9913  "Weekly engineering standup"  <>  "Daily team sync meeting"
  1.1065  "Weekly engineering standup"  <>  "Root canal at the dentist"
  1.0884  "1:1 with manager"            <>  "one on one with my boss"
  1.2915  "1:1 with manager"            <>  "Flight to Tokyo"
  1.1483  "Focus time - do not book"    <>  "Design review w/ Priya (external)"
  ```

  A near-paraphrase (1.0884) scores **worse** than a completely unrelated pair (1.1065),
  and the row that matters most for this app sits in the mushy middle. Word embeddings are
  worse: `contains("standup")` is `false`, so `distance(between: "meeting", and: "standup")`
  returns the 2.0 sentinel. A 57k GloVe-era vocabulary knows nothing about standup, retro,
  sprint, 1:1 or OOO. **Do not build event similarity or clustering on this.**

---

## 4. Claims I made and then disproved

Read this section. Each of these is a conclusion I reached, stated confidently, and then
found to be wrong. They are the traps most likely to be re-entered.

### 4.1 "The syncToken branch is dead code that never runs"

**Wrong.** My stated reason was that `listEvents` sends `timeMin`/`timeMax`/`orderBy`,
making the response ineligible for a `nextSyncToken`. That is backwards — see 3.3. The
token minted fine, `paginateEvents` correctly took it from the last page, and the branch
ran on every sync. The real bug was the unmatchable parameter set. The fix is a
restructure, not a deletion, which is what 2.3 did.

### 4.2 "The Google sync is properly built"

**Wrong, and I said it early after reading only `GoogleCalendarAPIClient` and not its
caller.** The client's `syncToken` plumbing and `syncTokenExpired` handling do look good in
isolation. `GoogleCalendarService` then used them in a way that made them pointless. Read
the caller before praising the callee.

### 4.3 "There is no calendar or alarm assistant-schema domain for Siri"

**Wrong.** I grepped for `AssistantSchemas` and found only deprecated markers, and
concluded the domains did not exist. iOS 27 **renamed** the namespace to `AppSchema`. Both
domains exist, including `DismissAlarmIntent` and `SnoozeAlarmIntent`, which map onto
intents calarm already has under non-schema names. See 3.6.

### 4.4 "Use NLEmbedding plus a k-NN for the behaviour learner"

**Half wrong.** The k-NN half stands. The `NLEmbedding` half is measurably unfit — see the
numbers in 3.6. Use structured features instead: recurrence ID, attendee count, hour of
day, organiser-is-me, duration, and the user's own past dismiss/snooze counts. Honestly, a
plain frequency table over `(recurrenceID, action)` will beat k-NN for months and needs no
ML at all.

### 4.5 "The Worker relay needs a ~$10/yr domain for Search Console verification"

**Wrong.** Domain verification was dropped — see 3.4. A free platform subdomain satisfies
the only remaining requirement. That path is $0 infrastructure.

### 4.6 "EventKit sidesteps the Workspace OAuth block, so it is the strong play"

**True in general, moot for the work calendar.** EventKit reads the local store populated
by Apple's own OAuth client, so there is no client ID of yours for an admin to block. But
on the work account the store is **empty**, because the account is never added to iOS
Settings > Calendar. See section 5.

### 4.7 An agent's claim I caught, recorded so you trust the right thing

A research agent concluded that the whole push architecture is "quietly broken" because a
push that wakes the app to re-read EventKit reads data that is still 15 minutes stale. The
reasoning is sound, but it had inspected `predecessor iOS target`, not calarm. **calarm has a direct
Google API client, so a push leads to a Google fetch and the data is genuinely fresh.** The
flaw does not apply here — though it is a strong retroactive argument for having picked
calarm over the EventKit-only target.

Two other agent errors from this session, for calibration: one claimed `MeetingProvider` in
predecessor app "is already a protocol" (it is an enum), and four implementation agents once stalled
for 600s and wrote zero files. **Verify agent claims against primary sources before acting
on them.**

---

[redacted]

[redacted]

[redacted]

[redacted]
> applications, in properly enrolled devices. This includes access from unmanaged or
> self-managed personal devices."

And the Apple setup guide is explicit:

> "You will need to install Gmail and Google Calendar to access email and calendar. You
> will not be able to manage it with Apple Mail/Calendar app."

Two consequences:

[redacted]
[redacted]
[redacted]
[redacted]
[redacted]
   added to iOS Settings > Calendar. The Google Calendar iOS app keeps its own private store
   and does not write to the iOS calendar database.

**Do not propose reading the work calendar from the phone without the owner clearing it
[redacted]
to target a personal Google calendar, which the policy does not govern at all.

What *is* sanctioned: the Mac. predecessor app on macOS reads the work calendar through `gws`, which
[redacted]
[redacted]
may use with no request. `gws` is a **Node.js CLI and cannot run on iOS** under any
configuration, so it is a Mac-only asset.

---

## 6. Three experiments to run before writing more code

Each is roughly 15–30 minutes on a real device, and **each can invalidate an entire branch
of the plan**. Do these first. I could not do them — they need the owner's phone and
Google account.

**1. Measure `onEventUpdated` latency.** The one load-bearing number nobody has published.
A ten-line script that appends `new Date()` to a Sheet on every fire, against a stopwatch.
If it is seconds, the trigger architecture is excellent. If it is minutes, it is no better
than polling and the whole Apps Script push path loses its reason to exist.

**2. Can a `UNNotificationServiceExtension` call `AlarmManager`?** Undocumented either way —
I looked. `AlarmManager.shared` is presented everywhere as a main-app singleton and
`NSAlarmKitUsageDescription` lives in the app's Info.plist, but an extension shares the
app's team and group while being a distinct process. If **yes**, then "visible push →
extension re-arms alarms within its ~30s window" is a complete solution that works even
when the app is force-quit. If **no**, the push still delivers a tappable "your schedule
changed" notification, which is most of the value for a fraction of the work. **This gates
the entire push architecture.**

**3. Does AlarmKit fire reliably on the owner's phone?** See the community report in 3.1.
Schedule a handful of alarms across a day and a locked/backgrounded device and check they
fire on time. If they do not, stop optimising freshness and go fix that instead.

---

## 7. Architecture options

Ranked by value per hour of work, not by cleverness. The first one is not optional — it
makes every other option's failure mode survivable.

| | What | Freshness | Cost | Needs $99 Apple? |
|---|---|---|---|---|
| **A** | **Short-horizon arming.** Schedule alarms only 24–48h out, re-arm on every foreground, show a visible "synced 4 min ago". | Bounded blast radius rather than raw freshness | $0, an afternoon | No |
| **B** | **Apps Script `doGet` as a read API the app polls.** | Poll interval + ~1s | $0 | **No** |
| **C** | B plus `onEventUpdated` pre-computing the JSON into `PropertiesService`, so `doGet` is a property read. | Same as B, faster response | $0 | No |
| **D** | **Pipedream instant trigger → FCM → visible push.** | Seconds, if trigger latency holds | Free tier | Yes |
| **E** | **My Apps Script → FCM → visible push.** | Seconds, if trigger latency holds | $0 infra | Yes |
| **F** | Cloudflare Worker + `events.watch` + APNs. | Seconds | $0 infra (see 4.5) | Yes |
| **G** | Apps Script → APNs directly. | **Impossible.** See 3.5 | — | — |

**Option B deserves its own paragraph, because it is the surprise of the research.** If the
app polls the Apps Script web app instead of Google directly, it needs **no Google OAuth at
all**: no client ID, no consent screen, no verification, no 100-grant cap, no 7-day
refresh-token expiry, no `GoogleService-Info.plist`, and no GoogleSignIn/AppAuth
dependency — that is 8 SPM packages gone. The script holds the only credential. This
deletes both of the blockers still outstanding on calarm's Google path (section 8) rather
than working around them. The `doGet` in `apps-script/Relay.gs` already implements it.

Its costs, stated honestly: the deployment URL becomes a bearer secret in a query string
(no header auth is possible — 3.5), the script becomes a dependency of the app, and
`robots.txt` on `script.google.com` returns 404 so secrecy rests entirely on never
publishing the URL. Keep it in the Keychain, not `Info.plist`.

**Why D ranks above E:** Pipedream's Google Calendar instant trigger **renews the push
channel itself** — its own schema says the renewal "runs in the background, so you should
not need to modify this schedule." That removes the two things that rot unattended, the
~7-day channel expiry and the OAuth refresh. Its documented gap is that it "does not emit
cancelled events", which is mitigated by treating any notification as "something changed,
re-read the window" — which you should do anyway. Pipedream is also explicitly permitted
for this owner.

**Traps, with the specific reason each is a trap:**

- **Zapier free polls every 15 minutes; IFTTT free is hourly.** That is equal to or worse
  than the EventKit staleness you are trying to escape, plus a cloud dependency and a second
  OAuth grant. Make.com and n8n poll Google Calendar rather than using `events.watch`.
- **ntfy / Pushover / Telegram deliver into *their* app.** There is no mechanism by which
  the ntfy app receiving a push causes calarm to execute code, so they can never touch
  `AlarmManager`. Fine as a human nudge, useless as a wake mechanism.
- **Any design leaning on a *silent* (`content-available`) push.** Not delivered to a
  force-quit app, budgeted at 2–3/hour, dropped on undocumented heuristics. For a rarely
  opened personal app that is the same near-never failure as `BGAppRefreshTask`, with $99 of
  ceremony in front of it. **Visible pushes are the reliable channel on iOS.**
- **`BGContinuedProcessingTask` (iOS 26).** Documented to require explicit user initiation,
  "never automatic". It is the most-cited new background API and cannot serve unattended
  refresh at all.
- **Pushcut's Automation Server.** Documented to work only while the Pushcut app is visible
  on screen; meant for a dedicated always-on device.

**One decision I deliberately did not make.** `Relay.gs` currently sends a **visible,
time-sensitive** push, because visible pushes survive force-quit and silent ones do not.
But a banner before an AlarmKit alarm is two interruptions for one meeting, and predecessor app's
whole thesis is that the ring is the alert and banners stay off. calarm has its own design
system so predecessor app's law does not bind it, but the tension between reliability and restraint
is real. If you send a visible push, make its text say *what changed* — information the
alarm itself cannot convey.

---

## 8. What is left, in the order I would do it

1. **Flip the OAuth consent screen to "In production"** in the Google Cloud console. In
   Testing status, refresh tokens expire after **7 days**, so the owner would re-authenticate
   weekly forever. Owner action, not an agent action. *Skip entirely if you take option B.*
2. **`REVERSED_CLIENT_ID` into `Calarm/Info.plist` `CFBundleURLTypes`.** Currently the plist
   claims only the `calarm` scheme. GoogleSignIn delivers its OAuth callback to
   `com.googleusercontent.apps.<numeric>://`, which the app does not claim, so
   `AppDelegate.swift:26` forwards to `GIDSignIn.handle(url)` and nothing ever routes there.
   `scripts/setup-google-oauth.sh:13` describes this step and it was never done. **I believe
   Google sign-in has never completed end to end in this app**, which would explain how the
   syncToken bug survived a year unnoticed. Needs the owner's actual value from the
   uncommitted plist. *Skip entirely if you take option B.*
3. **Run the three experiments in section 6.**
4. **Option A from section 7** — short-horizon arming plus a visible last-synced stamp.
   Highest value per hour, no infrastructure, nothing that rots.
5. **Swift 6 migration.** `SWIFT_VERSION` is 5.0 today. The existing warnings show exactly
   what is coming: four isolation errors in `AlarmAppIntents.swift` (`uuid(from:)` called
   from outside the actor) and four captured-`self` errors in `GoogleAuthManager.swift`.
   Section 2.6 has the pattern to follow.
6. **Add App Groups.** The entitlements file has exactly one key,
   `com.apple.developer.siri`, and the widget extension has **no entitlements file at all**.
   The Live Activity works only because everything it needs is smuggled through
   `AlarmAppMetadata`. Without an App Group the widget can never show anything not in that
   struct — and it cannot reach the app's token store, which blocks using the widget
   timeline as a background sync engine (~40–70 reloads/day, and unlike `BGAppRefreshTask`
   that budget tracks widget visibility rather than app usage).
7. **Wire the two Siri schemas.** `AppSchema.ClockIntent`'s `DismissAlarmIntent` and
   `SnoozeAlarmIntent` map onto intents calarm already has, and iOS 27's
   `appEntityIdentifier:` on `AlarmConfiguration` is the bridge. Close to free.
8. **The behaviour learner**, if still wanted: structured features plus a frequency table or
   an updatable Core ML k-NN. Not `NLEmbedding` (3.6), and not the LLM — `eventType` (2.5)
   already does most of the classification work deterministically.

---

## 9. Known problems not fixed, and why

- **`ScheduleStore` is a ~600-line god object** with 14 `@Published` properties that
  instantiates its own services, so it cannot be constructed in a test without EventKit and
  AlarmKit. Every feature you can name lands inside it. This is the structural obstacle to
  extending the app, and 2.2/2.3 chipped at it by extracting pure functions. Continue that
  pattern rather than attempting a big refactor.
- **`RescheduleCoordinator` has a narrowed but unclosed race.** `perform` cancels the
  previous task and immediately overwrites `inFlightTask` without awaiting the cancellation,
  so two overlapping reschedule passes can interleave `AlarmManager` cancel/schedule calls.
  The generation token guards only the assignment of `lastSummary` — which is **written and
  never read**, since `ScheduleStore` keeps its own copy. Everything is `@MainActor` so the
  interleaving only happens at `await` points, and the reconcile pass converges, but the race
  is not closed. Zero tests.
- **`CalarmPersistence` grows without bound.** `EventAlarmPreferences` writes one override
  per *occurrence* and nothing prunes past ones; `removeOverride` is called only from a test's
  `defer`. `alarmOffsets(for:)` JSON-decodes the whole blob and calls `allOverrides()` twice.
  Fine at 40 events and 100 overrides; not fine at year three.
- **Schema version 3 has no migration.** `CalarmPersistence.swift:14` sets
  `currentSchemaVersion = 3`; `:36` guards `storedVersion < currentSchemaVersion` and `:38`
  then only handles `storedVersion < 2`. Harmless today, a landmine when you add step 4.
- **Google events can never show a calendar colour.** `ScheduleStore.swift` hardcodes
  `calendarColorHex: nil` for Google events and `GoogleCalendarListEntry` never decodes
  Google's `backgroundColor`/`colorId`. So the "tint the Live Activity with the calendar
  colour" feature silently does nothing for exactly the events the Google path exists to
  serve.
- **`CalendarSummary.colorHex` is populated with `cgColor?.components?.description`** — the
  Swift debug description of an array, e.g. `"[1.0, 0.5, 0.0, 1.0]"`. Never rendered, so
  harmless; `CalarmShared/CalendarColor.hexString` is the correct implementation and is what
  is actually used.
- **Dead code**, confirmed zero call sites: `AlarmScheduler.managedAlarmIDs(for:)`,
  `hasActiveCountdown()`, `hasActiveUpcomingCountdown()`, `SchedulerLog.errorDetail` (byte
  identical to `error`), `OpenAlarmApp`, `PauseAlarmIntent`, `ResumeAlarmIntent`,
  `CalarmDeepLink.occurrenceID(from:)`. Also `GoogleCalendarPreferences.lastSyncCheck`:
  the accessor exists and is written at `GoogleCalendarService.swift:147`, but **no consumer
  ever reads it** and no UI shows it. (`GoogleCalendarAPIClient.listUpdatedEvents` was on
  this list too; I deleted it in 2.3, so it is gone rather than dead.)
- **Tests mutate `UserDefaults.standard`.** `EventAlarmPreferencesTests` writes real
  preferences with no suite isolation, so running the suite changes the app's stored state on
  that machine.
- **`CalarmTests` compiles `CalarmShared/` directly into itself** *and* does
  `@testable import Calarm`, so every shared type exists twice in the test process. It works
  because Swift resolves locally, but `CalendarColorTests` is silently testing the test
  target's copy.

### Worth stealing from the retired `predecessor iOS target`

Not a recommendation to resurrect it, just where the useful bits are, in the predecessor app repo
under `ios/`:

- `AlarmPlan.swift` — a **pure, Foundation-only** alarm planner with 16 tests, each pinning
  a specific AlarmKit trap (same-minute grouping, truncation, the `preAlert: 1` landscape
  workaround). Compiled into the test target with no framework import.
- `docs/ios-app.md` — an eight-entry table of deliberate design-law departures, and a
  plainly-stated list of what EventKit costs.
- The `CalendarSource` protocol seam, if calarm ever needs more than two sources.

Note that `docs/ios-app.md:77` claims EventKit freshness is "minutes", which is wrong —
it is 15–60 minutes (3.2). If anyone revives that doc, fix that line.

---

## 10. Repo-specific traps

- **No Xcode GUI.** The owner's Mac is RAM-constrained and this is a standing constraint.
  Everything goes through `xcodebuild` on the command line. Section 2 has the working
  invocation.
- **`SWIFT_VERSION = 5.0` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** The
  `@MainActor` and `Sendable` annotations across this codebase are **unenforced assertions** —
  nobody has ever seen a diagnostic. Pure helpers and DTOs need explicit `nonisolated`.
- **The project uses `PBXFileSystemSynchronizedRootGroup`** (Xcode 16+), so all four
  `Sources` build phases are literally empty and adding a Swift file requires no project
  edit. Do not hand-add file references.
- **`Calarm/GoogleService-Info.plist` is gitignored and absent**, and
  `GoogleOAuthConfig.swift:32` rejects the `REPLACE_` placeholder. Google sync is therefore
  **dark on any fresh clone**, including right now. Only `GoogleService-Info.plist.example`
  exists.
- **Never commit a credential here.** This repo has already had a git-history purge for
  personal data, and `SECURITY.md` exists. `apps-script/Relay.gs` reads every secret from
  Script Properties for exactly this reason.
- **The owner runs a separate Apps Script that mutates this calendar.** "Focus Block
  Creator" converts solo events to `eventType: 'focusTime'` via `Events.insert` then
  `Events.remove` — which **changes the event ID**. Because `EventAlarmPreferences` keys on
  `{eventIdentifier}_{startTimestamp}`, any per-event bell setting on a converted block is
  silently orphaned. Google says `eventType` "cannot be modified after the event is
  created", so insert-plus-delete is the only route and the ID churn is inherent. Keep that
  script's read-write `calendar` scope away from the relay, which needs only
  `calendar.readonly`.
- **`ScreenshotMode` is a live branch in the launch path**, checked in `CalarmApp.init` and
  short-circuiting `ScheduleStore.bootstrap()` to inject demo data. Well isolated behind a
  launch argument, but be aware it exists.

---

## 11. Files added or changed this session

New:

- `apps-script/Relay.gs` — the calendar relay. 569 lines, and the header comment is a large
  share of that because the operational traps are worth more than the code. Implements both
  the FCM push path and the `doGet` read-API path.
- `apps-script/appsscript.json` — declares the Calendar advanced service and the web-app
  deployment settings.
- `CalarmTests/GoogleCalendarSyncParameterTests.swift` — 9 tests against a stubbed
  `URLProtocol`.
- `HANDOFF.md` — this file.

Changed: `Calarm/AppDelegate.swift`, `Calarm/Services/MorningSyncScheduler.swift`,
`Calarm/Store/ScheduleStore.swift`, `Calarm/Models/ScheduleEventSourcePolicy.swift`,
`Calarm/Services/GoogleCalendarAPIClient.swift`, `Calarm/Services/GoogleCalendarService.swift`,
`Calarm/Services/GoogleCalendarModels.swift`, `CalarmShared/EventOccurrenceID.swift`,
`CalarmTests/ScheduleEventSourcePolicyTests.swift`, `CalarmTests/GoogleCalendarMappingTests.swift`.

**None of it is committed.** The owner asked to read the diff first.
