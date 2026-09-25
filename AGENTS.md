# AGENTS.md

Instructions for any AI coding agent working in this repository. This is the **canonical**
instruction file — every other harness config points here. See
[Harness wiring](#harness-wiring) before adding another one.

**calarm** turns calendar events into AlarmKit alarms — the loudest thing a third-party
iOS app can do. iOS 26+, Swift, SwiftUI, a widget extension for Live Activities, and a
direct Google Calendar API client alongside EventKit.

## Read this first

| File | Holds | Read when |
|---|---|---|
| **[STATUS.md](STATUS.md)** | Where things stand, what is blocked, what is next | **Always, at session start** |
| [CHANGELOG.md](CHANGELOG.md) | What changed, when, why | Before calling something new or broken |
| [RESEARCH.md](RESEARCH.md) | Verified platform facts, disproved claims, sources | Before researching AlarmKit, EventKit, Google Calendar, push, or background execution |
| [SECURITY.md](SECURITY.md) | What must never be committed | Before touching credentials |

RESEARCH.md exists so you do not repeat finished research, and so you do not re-reach
conclusions that were already disproved — it has a whole section of confident claims that
turned out wrong. Read it before spending a research budget.

## The documentation rule

**Leave the docs true, every session, without being asked.** They are not a courtesy to
humans; they are the handoff mechanism between agents. A stale STATUS.md costs the next
agent an hour, or sends it down a path that was already closed.

Before finishing a piece of work:

- **CHANGELOG.md** — add an entry for anything a user or agent would notice. Name the
  commit. Skip typo fixes.
- **STATUS.md** — update if the state of play moved, and **always bump `Last updated`**.
- **RESEARCH.md** — add what you verified against a primary source, with URL and evidence
  label. If you disproved something there, correct it *and* record the correction.
- **This file** — update when a command, convention or trap changes.

Unsure where a fact goes? *True now and likely to change?* → STATUS. *Did it happen?* →
CHANGELOG. *True about the platform regardless of this repo?* → RESEARCH.

**Do not add a fifth top-level document.** The previous structure drifted into two
overlapping 700-line session narratives nobody could tell apart.

## Commands

Everything is command line. **No Xcode GUI** — this Mac is RAM-constrained and that is a
standing constraint, not a preference.

```bash
UDID=$(xcrun simctl create "calarm-tmp" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcodebuild test -project Calarm.xcodeproj -scheme Calarm \
  -destination "id=$UDID" -only-testing:CalarmTests
xcrun simctl delete "$UDID"
```

```bash
./scripts/ship.sh doctor    # run before anything release-shaped
./scripts/ship.sh beta      # tests + archive + TestFlight + tester group
./deploy.sh 1               # simulator      ./deploy.sh 2   # device
```

**Shipping** runs `scripts/ship-testflight.sh` on whichever Mac holds the distribution
signing identity and the App Store Connect API key (configured in its gitignored
`fastlane/.env`; see `fastlane/.env.example`). It updates itself from `main`, unlocks the
login keychain (always over SSH, where each session has its own security session; locally
only if locked), runs `ship.sh beta` (doctor, tests, archive, upload, tester group), waits
for `IN_BETA_TESTING` in ASC, runs `record-build.sh` (STATUS *Latest build*; the top
`## Unreleased` CHANGELOG heading becomes `## Build N`), commits and pushes. Timed log in
that Mac's `build/logs/`. Work happens on `main`; no side branches. Before shipping, title
pending CHANGELOG work `## Unreleased — YYYY-MM-DD` so it gets the build number.

**Release Mac vs dev Mac toolchains can differ.** An iOS 27 SDK API compiles under Xcode 27
and breaks an Xcode 26 release build. Wrap such code in `#if compiler(>=6.4)` as well as
`#available(iOS 27.0, *)`, and compile on the release Mac before shipping (see Owner's setup).

**Verify a ship against App Store Connect, not the script's output.** This pipeline has
printed success with a build that reached nobody, three times in one day. The signal is
`internalBuildState == IN_BETA_TESTING` on the build's `buildBetaDetail`; the API key's
role gets 403 on `/builds/{id}/betaGroups`.

## Owner's setup

The one place this repo names the owner's machines. Nothing here is secret: `macmini-remote`
is an SSH alias whose host and key live only in the owner's `~/.ssh/config`.

- **Release Mac:** `macmini-remote`, repo at `~/projects/calarm`, Xcode 26 (Swift 6.3).
  **Dev Mac:** Xcode 27 (Swift 6.4).
- **Ship command — hand the owner exactly this**, nothing longer, no local wrapper scripts:

  ```bash
  ssh -t macmini-remote '~/projects/calarm/scripts/ship-testflight.sh'
  ```

  The owner types the keychain password; never handle it. Afterwards `git pull` here.
- **Compile check on the release Mac** (no keychain needed):

  ```bash
  ssh macmini-remote 'cd ~/projects/calarm && git reset -q --hard HEAD && git pull -q --ff-only origin main && xcodebuild build -project Calarm.xcodeproj -scheme Calarm -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO -quiet'
  ```

## Hard constraints

- **Never commit a credential.** This repo has already had a history purge for personal
  data. See [SECURITY.md](SECURITY.md).
- **Never handle the owner's passwords.** Keychain unlocks and logins are theirs to type.
- **Do not add a work (employer) calendar as a source, and keep employer details out of
  this public repo** — names, emails, internal policy or tools. Local notes go in the
  gitignored `notes/`. See
  [RESEARCH.md § The work-calendar constraint](RESEARCH.md#the-work-calendar-constraint).
- **Do not send repo content to third-party services.** No paste sites or file hosts.
- **A missed meeting is this app's worst outcome.** When a design choice is ambiguous,
  fail *open* — show the event, ring the alarm. Every filter here that could hide an event
  defaults to showing it, deliberately.

## Code conventions

- **No comments that explain what the code does.** Comments earn their place by explaining
  *why* — a platform bug being worked around, a decision that looks wrong without context.
  Match the surrounding file's density.
- **Commit messages say what changed and why**, imperative mood. No co-author trailers; a
  git hook strips them.
- **Tests for pure logic.** The pattern that works here is extracting a pure function out
  of `ScheduleStore` and testing that, rather than constructing the store.

## Traps

- **`SWIFT_VERSION = 5.0` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** Unannotated
  statics and structs are MainActor-isolated and **nobody has ever seen the diagnostic**.
  Pure helpers and DTOs need explicit `nonisolated`.
- **`PBXFileSystemSynchronizedRootGroup`** — Sources build phases are empty and adding a
  Swift file needs **no project edit**. Do not hand-add file references.
- **`CalarmShared/` is compiled into each target, not imported as a module.** Do not mark
  its types `public`.
- **AlarmKit owns the Live Activity.** Never call `Activity.request` for an alarm, or you
  get two.
- **The Live Activity alarm is countdown-mode (`schedule: nil`), not `.fixed` + `preAlert`.**
  The latter rang late on device by exactly its pre-alert. AlarmKit keeps no fire date for a
  countdown alarm; `AlarmScheduler` stores it. See the `calarm-alarmkit-reschedule` skill.
- **The compact Island cannot shrink mid-countdown.** AlarmKit re-renders the widget only
  on state changes; width is sized from time remaining at render.
- **The Simulator cannot ring an AlarmKit alarm** and the app blocks the test alarm there.
  Anything alarm-visual must be verified on device.
- **`Calarm/GoogleService-Info.plist` and `Config/Google.local.xcconfig` are gitignored** —
  Google sign-in is off on a fresh clone until `./scripts/setup-google-oauth.sh <client
  plist>` runs. The plist is in Google Cloud console → Google Auth Platform → Clients →
  "CALarm iOS" (project `useful-field-497119-k5`, account parth.chandak02@gmail.com).
- **A separate Apps Script mutates this calendar.** "Focus Block Creator" converts solo
  events via insert-then-remove, which **changes the event ID** and orphans preferences
  keyed to it.
- **`ScreenshotMode` is a live branch in the launch path**, short-circuiting
  `ScheduleStore.bootstrap()` to inject demo data.

More, with reasoning:
[RESEARCH.md § Known problems](RESEARCH.md#known-problems-not-fixed-and-why).

## Layout

```
Calarm/                  Main app — AlarmKit, EventKit, Google client, views
CalarmWidgetExtension/   Live Activity + Dynamic Island views
CalarmShared/            Types compiled into both targets (not a module)
CalarmTests/             Unit tests      CalarmUITests/   Screenshot automation
apps-script/             Apps Script relay (alternative backend, not deployed)
scripts/                 ship.sh, ios-doctor.sh, stamping, credentials
docs/app-store/          Publishing playbooks; docs/ is also the Pages site
.claude/skills/          Task playbooks  .claude/agents/  Subagent definitions
```

## Skills and subagents

Playbooks live in `.claude/skills/<name>/SKILL.md`, subagents in
`.claude/agents/<name>.md`. See the [skills index](.claude/skills/README.md). Reach for
them when editing alarm scheduling, the release pipeline, deep links, occurrence identity,
or UI.

Adding one: create the real directory under `.claude/skills/`. Frontmatter needs `name`
(matching the folder, `a-z0-9-`) and `description` (say *what* and *when*). Keep the body
under 500 lines; push detail into `references/`.

## Harness wiring

One copy of every instruction, read by every harness. Do not add more config files.

| Path | Read natively by | Kind |
|---|---|---|
| `AGENTS.md` | Claude Code, Cursor, Codex, Copilot, Windsurf, Devin, Jules | The canonical file |
| `CLAUDE.md` | Claude Code | Two-line `@AGENTS.md` import — **keep it that way** |
| `.claude/skills/` | Claude Code, Cursor, Copilot | Real directory — author here |
| `.claude/agents/` | Claude Code, Cursor | Real directory |
| `.agents/skills` | Codex | Symlink → `.claude/skills` |
| `.gemini/settings.json` | Gemini CLI | Points `context.fileName` at AGENTS.md |
| `.aider.conf.yml` | Aider | Aider auto-loads nothing without it |

- **Never make `CLAUDE.md` a symlink or a copy.** As an import it costs nothing and never
  double-loads, and it keeps working where native AGENTS.md reading is unavailable — older
  Claude Code, Bedrock and third-party providers, telemetry off. As a symlink it breaks
  Edit/Write, and a Windows clone with `core.symlinks=false` turns it into a nine-byte file
  containing the literal string `AGENTS.md`, with a clean `git status` hiding it. Verified,
  not theoretical.
- **Never add `CLAUDE.local.md`** — it silently disables native AGENTS.md reading.
- **Author skills in `.claude/skills/`, never through `.agents/skills`.** Claude Code
  refuses to write into a symlinked directory. The symlink points this way round on
  purpose: it degrades on a Windows clone, and confining that to Codex leaves AGENTS.md
  and all twelve skills intact for everything else.

Skipped deliberately: `.github/copilot-instructions.md` (Copilot would load it *and*
AGENTS.md, duplicating context), `.cursor/rules/`, `.windsurfrules`, `GEMINI.md`.

```bash
claude plugin validate .claude/agents && claude plugin validate .claude/skills
```
