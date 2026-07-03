# Security & privacy (repository)

Last audited: 2026-06-30 (post–history purge; App Store prep pass)

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

- Bundle IDs: `com.calarmapp.calarm`, `com.calarmapp.calarm.CalarmWidgetExtension`
- Apple Developer Team ID in `Calarm.xcodeproj` and `fastlane/Appfile` (required for local signing)

## App Store publishing

- API keys and `.p8` files stay in `fastlane/.env` (gitignored) and outside the repo.
- `ExportOptions.plist` is local-only; use `ExportOptions.plist.example` as a template.
- Privacy/support pages in `docs/` are public by design once GitHub Pages is enabled.
- Contact email on support/privacy pages is intentional for App Store Connect URL validation.

## Git history purge (2026-06-30)

The following were removed from **all commits** via `git filter-repo` and force-pushed to `origin/main`:

- Physical device UDID (`00008150-…`) from agent docs
- Personal machine paths (`/Users/parthchandak/…`)
- Xcode “Created by …” file headers in widget sources

**If you cloned before this purge:** delete your local clone and re-clone, or run `git fetch origin && git reset --hard origin/main`. Old commit SHAs (`bb30337`, `719d2b6`, etc.) are invalid on the remote.

Forks and local copies made before the force-push may still contain the old history until their owners rebase or delete the fork.

## Reporting

If you find credentials or personal device data in the repository, rotate affected Apple API keys and open an issue. Do not commit device UDIDs or local machine paths in docs or scripts.
