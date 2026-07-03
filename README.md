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
2. Confirm **Signing & Capabilities** → Team is set (project uses `M49XY93NTP`).
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
| Calarm | `pchandak.calarm` |
| Widget extension | `pchandak.calarm.CalarmWidgetExtension` |

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

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `xcodebuild` requires Xcode | Install Xcode.app and run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| Signing errors | Open project → Signing & Capabilities → pick your Team |
| AlarmKit denied | Settings → Calarm → allow alarms; enable Developer Mode on device |
| No iOS 26 simulator | Xcode → Settings → Platforms → download iOS 26 |

## App Store submission

See **[APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md)** for the full pre-publish checklist.

```bash
./release.sh                              # Archive + export IPA
cp fastlane/.env.example fastlane/.env    # add ASC API key
bundle install && bundle exec fastlane ios upload_beta
```

Subagents:
- `calarm-app-store-prep` — metadata, fastlane, ASC checklist
- `calarm-ship-ready` — code polish, device deploy, final QA

## Docs

- [AlarmKit](https://developer.apple.com/documentation/alarmkit)
- [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- [Live Activities](https://developer.apple.com/documentation/activitykit)
