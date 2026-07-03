# Security & privacy (repository)

Last audited: 2026-07-03

## What this app stores on device

| Data | Location | Leaves device? |
|------|----------|----------------|
| Alarm preferences per calendar event | `UserDefaults` (via `CalarmPersistence`) | No |
| Default alarm offset & snooze | `UserDefaults` | No |
| Theme (appearance + accent) | `UserDefaults` | No |
| Calendar events | EventKit (system); read-only at runtime | No app upload |

No accounts, analytics SDKs, or network calls for user data.

## What must never be committed

- `fastlane/.env` (App Store Connect API keys)
- `*.p8` / `AuthKey_*.p8`
- `ExportOptions.plist` (signing export; local)
- `build/`, `build-device/`, `build-sim/`, `DerivedData/`
- Device UDIDs or named device identifiers in docs/scripts
- Personal machine paths (`/Users/...`) in shared docs

All of the above are covered by `.gitignore` or project conventions.

## Intentionally public in this repo

These identify the app / Apple Developer account but are **not secrets** (they also appear in signed IPAs):

- Bundle IDs: `pchandak.calarm`, `pchandak.calarm.CalarmWidgetExtension`
- Apple Developer Team ID in `Calarm.xcodeproj` and `fastlane/Appfile` (required for local signing)

## Reporting

If you find credentials or personal device data in the git history, open an issue or rotate the affected Apple API key / treat the UDID as non-secret but remove from future commits.
