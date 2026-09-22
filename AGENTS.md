# AGENTS.md

Instructions for any AI coding agent working in this repository. This is the **canonical
and only** instruction file — see [Harness wiring](#harness-wiring) if you are wondering
where `CLAUDE.md` went.

**calarm** is an iOS 26+ app that turns calendar events into AlarmKit alarms — the loudest
thing a third-party iOS app can do. Swift, SwiftUI, a widget extension for Live Activities,
and a direct Google Calendar API client alongside EventKit.

---

## Read this first

| File | What it holds | Read when |
|---|---|---|
| **[STATUS.md](STATUS.md)** | Where the project stands, what is blocked, what comes next | **Always, at session start** |
| [CHANGELOG.md](CHANGELOG.md) | What changed, when, and why | Before claiming something is new or broken |
| [RESEARCH.md](RESEARCH.md) | Verified platform facts, disproved claims, architecture reasoning, sources | Before researching AlarmKit, EventKit, Google Calendar, push, or background execution |
| [README.md](README.md) | Human-facing setup and project layout | Setting up a machine |
| [SECURITY.md](SECURITY.md) | What must never be committed | Before touching credentials or config |

**RESEARCH.md exists so you do not repeat research that is already done, and so you do not
re-reach conclusions that were already disproved.** It has a section of confidently-stated
claims that turned out to be wrong. Read it before spending a research budget.

---

## The documentation rule

**Leave the docs true. Every session, without being asked.**

Documentation here is not a courtesy to humans — it is the handoff mechanism between
agents. A stale `STATUS.md` costs the next agent an hour of rediscovery, or worse, sends it
down a path that was already closed.

Before you finish a piece of work:

1. **`CHANGELOG.md`** — add an entry for anything a user or another agent would notice.
   Behaviour changes, bug fixes, new files, pipeline changes. Not typo fixes. Name the
   commit hash.
2. **`STATUS.md`** — update it if the state of play moved: something shipped, a gate
   resolved, a blocker appeared or cleared, the next step changed. **Always update the
   `Last updated` date when you touch it.**
3. **`RESEARCH.md`** — add anything you verified against a primary source, with its URL and
   an evidence label. If you disproved something in there, correct it in place *and* record
   the correction — the wrong version is useful to the next agent.
4. **This file** — update it when a command, convention or trap changes.

If you are unsure which file a fact belongs in: *is it true right now and likely to change?*
→ STATUS. *Did it happen?* → CHANGELOG. *Is it true about the platform regardless of this
repo?* → RESEARCH.

Do not create new top-level documents. Four is the budget; the previous structure drifted
into two overlapping 700-line session narratives that nobody could tell apart.

---

## Commands

Everything is command line. **There is no Xcode GUI in this loop** — the owner's Mac is
RAM-constrained and this is a standing constraint, not a preference.

```bash
# Tests. Needs a simulator; create one if none exists.
UDID=$(xcrun simctl create "calarm-tmp" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcodebuild test -project Calarm.xcodeproj -scheme Calarm \
  -destination "id=$UDID" -only-testing:CalarmTests
xcrun simctl delete "$UDID"
```

```bash
./scripts/ship.sh doctor    # health check — run before anything release-shaped
./scripts/ship.sh beta      # tests + archive + TestFlight + tester group
./scripts/ship.sh metadata  # App Store descriptions, URLs, screenshots
```

```bash
./deploy.sh 1   # build + install + launch on simulator
./deploy.sh 2   # same, physical device
```

### Shipping happens on the Mac mini, not the laptop

The App Store Connect key and signing identity live on `macmini-remote`. The keychain must
be unlocked **in the same SSH session** as the build — each `ssh` gets its own security
session, so a separate unlock call does nothing. The owner types the password; an agent
must not handle it.

```bash
ssh -t macmini-remote 'security unlock-keychain ~/Library/Keychains/login.keychain-db && cd ~/projects/calarm && git pull --ff-only origin main && ./scripts/ship.sh beta'
```

**Verify a ship against App Store Connect, not against the script's output.** This pipeline
has produced a green success message with a build that reached nobody three separate times.
The signal that matters is `internalBuildState == IN_BETA_TESTING`. Note that the API key's
role gets 403 on `/builds/{id}/betaGroups`, so check the build beta detail instead.

---

## Hard constraints

- **Never commit a credential.** This repo has already had a git-history purge for personal
  data. `apps-script/Relay.gs` reads every secret from Script Properties for this reason.
  See [SECURITY.md](SECURITY.md).
- **Never handle the owner's passwords.** Keychain unlocks and console logins are theirs to
  type.
[redacted]
[redacted]
[redacted]
- **Do not send repo content to third-party services.** No paste sites, file hosts, or
  upload endpoints.
- **A missed meeting is this app's worst outcome.** When a design choice is ambiguous, fail
  *open* — show the event, ring the alarm. Every filter in this codebase that could hide an
  event defaults to showing it, deliberately.

---

## Code conventions

- **Do not write comments that explain what the code does.** Code should be
  self-explanatory. Comments here earn their place by explaining *why* — a non-obvious
  constraint, a platform bug being worked around, a decision that looks wrong without
  context. Match the density of the surrounding file.
- **Commit messages say what changed and why**, in the imperative. No co-author trailers —
  a git hook strips them.
- **Tests are expected** for pure logic. The pattern that works here is extracting a pure
  function out of `ScheduleStore` and testing that, rather than trying to construct the
  store.

---

## Traps specific to this repo

- **`SWIFT_VERSION = 5.0` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** Every
  unannotated `static func` or `struct` is MainActor-isolated, and because the language mode
  is 5.0 **nobody has ever seen the diagnostic**. Pure helpers and DTOs need an explicit
  `nonisolated` or they cannot be called from a `map` closure or a background decode.
- **The project uses `PBXFileSystemSynchronizedRootGroup`.** All four Sources build phases
  are literally empty and adding a Swift file requires **no project edit**. Do not hand-add
  file references.
- **`CalarmShared/` is compiled directly into each target, not imported as a module.** Do
  not mark its types `public`. `CalarmTests` compiles it *and* does
  `@testable import Calarm`, so shared types exist twice in the test process.
- **`Calarm/GoogleService-Info.plist` is gitignored and absent.** Google sync is dark on
  any fresh clone. Only the `.example` exists.
- **AlarmKit owns the Live Activity.** Never call `Activity.request` for an alarm — the
  widget extension supplies views for an activity AlarmKit creates. Calling it yourself
  produces two.
- **The Simulator cannot ring an AlarmKit alarm**, and the app blocks the test alarm there
  on purpose. Anything alarm-visual must be verified on the device.
- **The owner runs a separate Apps Script that mutates this calendar.** "Focus Block
  Creator" converts solo events to `eventType: 'focusTime'` via insert-then-remove, which
  **changes the event ID** and silently orphans any per-event preference keyed to it.
- **`ScreenshotMode` is a live branch in the launch path**, checked in `CalarmApp.init`,
  short-circuiting `ScheduleStore.bootstrap()` to inject demo data.

More, with the reasoning behind each:
[RESEARCH.md § Known problems](RESEARCH.md#known-problems-not-fixed-and-why).

---

## Layout

```
Calarm/                     Main app — AlarmKit, EventKit, Google client, SwiftUI views
CalarmWidgetExtension/      Live Activity + Dynamic Island views
CalarmShared/               Types compiled into both targets (not a module)
CalarmTests/                Unit tests
CalarmUITests/              Screenshot automation
apps-script/                Google Apps Script relay (alternative backend, not deployed)
scripts/                    ship.sh, ios-doctor.sh, build stamping, credentials
docs/app-store/             Publishing playbooks
docs/                       Also the GitHub Pages site (index/privacy/support .html)
.claude/skills/             Task-scoped playbooks — see below
.claude/agents/             Subagent definitions — see below
```

## Skills and subagents

Task-scoped playbooks live in `.claude/skills/<name>/SKILL.md`, subagent definitions in
`.claude/agents/<name>.md`. See the [skills index](.claude/skills/README.md).

Reach for them when editing alarm scheduling, the release pipeline, deep links, occurrence
identity, or UI.

**Adding one:** create the real directory under `.claude/skills/`, never through a symlink
— Claude Code refuses to write into symlinked directories. Frontmatter needs `name` (must
match the folder name, `a-z0-9-`) and `description` (say *what* and *when*). Keep the body
under 500 lines and push detail into a `references/` subdirectory.

## Harness wiring

One copy of everything, read by every agent harness. The layout is deliberate:

| Path | Read natively by | Notes |
|---|---|---|
| `AGENTS.md` | Claude Code, Cursor, Codex, Copilot, Windsurf, Devin, Jules | The canonical file |
| `.claude/skills/` | Claude Code, Cursor, Copilot | Real directory — author here |
| `.claude/agents/` | Claude Code, Cursor | Real directory |
| `.agents/skills` | Codex | Symlink → `.claude/skills` |
| `.gemini/settings.json` | Gemini CLI | Points `context.fileName` at AGENTS.md |
| `.aider.conf.yml` | Aider | Aider auto-loads nothing; this adds AGENTS.md |

**Do not add a `CLAUDE.md`.** Claude Code reads `AGENTS.md` natively, but *only when no
`CLAUDE.md` exists* — creating one, even as a symlink, silently disables this file. Same
for a personal `CLAUDE.local.md`. If you genuinely need Claude-specific instructions, make
`CLAUDE.md` contain the single line `@AGENTS.md` followed by your additions; the import
never causes double-loading.

Symlinking `CLAUDE.md → AGENTS.md` looks tempting and is a trap: it breaks Edit/Write, and
on a Windows clone with `core.symlinks=false` it silently becomes a 9-byte text file
containing the literal string `AGENTS.md`, with a clean `git status`.
