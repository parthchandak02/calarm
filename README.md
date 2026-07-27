# Calarm

iOS 26 app for countdown alarms with **AlarmKit**, **Live Activities**, and **Dynamic Island** support. Evolved from the earlier CalendarAlarm prototype; this repo is the clean `calarm` home going forward.

## Requirements

- **Xcode 26** (full app from App Store or [Apple Developer](https://developer.apple.com/xcode/)) — Command Line Tools alone are not enough
- **iOS 26+** on simulator or physical device
- Apple Developer account for device installs (free tier works for personal device testing)
- **Developer Mode** enabled on a physical iPhone

After installing Xcode, point the active developer directory at it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

## Quick start

### Open in Xcode

```bash
open Calarm.xcodeproj
```

1. Select the **Calarm** scheme and your iPhone or an iOS 26 simulator.
2. Confirm **Signing & Capabilities** → Team is set to your Apple Developer team.
3. Press **Run** (⌘R).

### Deploy from terminal

```bash
./deploy.sh 1   # iOS 26 simulator
./deploy.sh 2   # physical device (connected + trusted)
```

## Project layout

```
calarm/
├── Calarm/                    # Main app (AlarmKit, calendar-aware alarms)
├── CalarmWidgetExtension/     # Live Activity + widget extension
├── Calarm.xcodeproj
├── deploy.sh                  # Build, install, launch
└── deploy-lib.sh
```

## Bundle IDs

| Target | Bundle ID |
|--------|-----------|
| Calarm | `com.calarmapp.calarm` |
| Widget extension | `com.calarmapp.calarm.CalarmWidgetExtension` |

## Features

- AlarmKit countdown timers with pre-alert and post-alert windows
- Live Activities in Dynamic Island
- Calendar-driven per-event alarm offsets (configurable in app)
- Pause / resume via App Intents and Live Activity controls

## Data persistence

User preferences are stored locally with **`UserDefaults.standard`** via `CalarmPersistence`:

| Data | Storage | Survives app update? |
|------|---------|----------------------|
| Per-event alarm offsets | JSON map keyed by calendar event ID | Yes |
| Default alarm offset & snooze | String / integer keys | Yes |
| Theme (appearance + accent) | String keys | Yes |

Calendar events themselves are **not** copied into app storage; Calarm reads them from EventKit each launch. Alarm preferences are keyed by EventKit `eventIdentifier`, so they reconnect after updates as long as the calendar event still exists.

`CalarmPersistence.migrateIfNeeded()` runs at launch with a schema version so older installs upgrade safely. Data is cleared only if the user deletes the app.

`PrivacyInfo.xcprivacy` declares UserDefaults access (`CA92.1` — app functionality only).

See **[SECURITY.md](SECURITY.md)** for repository security practices and what must not be committed.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `xcodebuild` requires Xcode | Install Xcode.app and run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| Signing errors | Open project → Signing & Capabilities → pick your Team |
| AlarmKit denied | Settings → Calarm → allow alarms; enable Developer Mode on device |
| No iOS 26 simulator | Xcode → Settings → Platforms → download iOS 26 |

## App Store submission

**Pipeline:** `./scripts/ship.sh doctor` → `./scripts/ship.sh beta`

| Doc | Purpose |
|-----|---------|
| [PUBLISH_PLAYBOOK.md](docs/app-store/PUBLISH_PLAYBOOK.md) | Full publish guide |
| [TERMINAL_TOOLS.md](docs/app-store/TERMINAL_TOOLS.md) | `asc`, fastlane, apple-docs |
| [pipeline/BOOTSTRAP_NEW_APP.md](pipeline/BOOTSTRAP_NEW_APP.md) | Reuse this pipeline for other Xcode apps |
| [APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md) | Checklist |

```bash
# One-time (after downloading API .p8 to ~/Keys/)
./scripts/configure-credentials.sh <ISSUER_ID>

./scripts/ship.sh doctor    # health check
./scripts/ship.sh beta      # build + TestFlight
./scripts/ship.sh metadata  # descriptions, URLs, screenshots
```

Subagents:
- `calarm-app-store-prep` — metadata, fastlane, ASC checklist
- `calarm-ship-ready` — code polish, device deploy, final QA

**Cursor skills** (`.cursor/skills/`): repo-specific playbooks for AlarmKit scheduling, device deploy verification, TestFlight, Live Activity deep links, build stamping, release pipeline, and app icon processing. See [skills README](.cursor/skills/README.md).

## Docs

- [AlarmKit](https://developer.apple.com/documentation/alarmkit)
- [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- [Live Activities](https://developer.apple.com/documentation/activitykit)
