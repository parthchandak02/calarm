# App Store screenshot automation

CALarm uses **fictional demo calendar data** in the simulator — never your real events.

## Quick start

```bash
./scripts/generate-app-store-screenshots.sh
```

Produces four PNGs at **1320×2868** (iPhone 17 Pro Max / 6.9") in `fastlane/screenshots/en-US/`.

## How it works

| Layer | What |
|-------|------|
| `SCREENSHOT_MODE` launch arg | Skips calendar permission; loads `ScreenshotDemoData` |
| `SCREENSHOT_SCENE=*` | Opens schedule, event detail, settings, or add-alarm picker |
| `scripts/capture-screenshots-simctl.sh` | Build → install → launch scenes → `simctl io screenshot` |
| `fastlane/Snapfile` + `CalarmUITests` | Optional UI-test path via `fastlane snapshot` |

## Commands

| Command | Purpose |
|---------|---------|
| `./scripts/generate-app-store-screenshots.sh` | Default simctl pipeline (recommended) |
| `./scripts/generate-app-store-screenshots.sh --ui-tests` | fastlane snapshot (UI tests; can be flaky) |
| `./scripts/generate-app-store-screenshots.sh --frame` | Add device frames via frameit (needs ImageMagick) |
| `bundle exec fastlane ios screenshots` | fastlane lane wrapper |

## Upload to App Store Connect

```bash
bundle exec fastlane ios upload_metadata screenshots:true
```

## Tools reference (industry standard)

| Tool | Role | Docs |
|------|------|------|
| **fastlane snapshot** | UI-test-driven capture across devices/locales | [fastlane docs](https://docs.fastlane.tools/actions/snapshot/) |
| **fastlane frameit** | Device bezels + caption overlays | [frameit](https://docs.fastlane.tools/actions/frameit/) |
| **fastlane deliver** | Upload screenshots + metadata to ASC | [deliver](https://docs.fastlane.tools/actions/deliver/) |
| **appshots** (CLI) | Frame/caption/validate without UI tests | [github.com/albertnahas/appshots](https://github.com/albertnahas/appshots) |
| **EasyFrameCommand** | SwiftUI-framed screenshots (fork-friendly) | [github.com/alschmut/EasyFrameCommand](https://github.com/alschmut/EasyFrameCommand) |

Raw App Store screenshots (no marketing frames) are acceptable; framed + captioned versions convert better. This repo ships **raw UI captures** by default; use `--frame` when you want marketing polish.

## Demo data scenes

1. **01_Schedule** — week view with fictional work events
2. **02_Event_Alarms** — design review with multiple alarms
3. **03_Settings** — default alarm, snooze, appearance, accent
4. **04_Add_Alarm** — alarm offset picker sheet

## Regenerating after UI changes

Re-run `./scripts/generate-app-store-screenshots.sh` before each App Store submission. No phone photos or personal calendar data required.
