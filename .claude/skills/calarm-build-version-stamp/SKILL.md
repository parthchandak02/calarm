---
name: calarm-build-version-stamp
description: >-
  CALarm date-based CFBundleVersion stamping (YYYYMMDD.HHmm) and Settings display.
  Use before deploy, TestFlight upload, or when user asks about build numbers.
---

# CALarm Build Version Stamp

## Apple standard

| Field | Xcode | Purpose |
|-------|-------|---------|
| Version | `MARKETING_VERSION` → `CFBundleShortVersionString` | User-facing, e.g. `1.0` |
| Build | `CURRENT_PROJECT_VERSION` → `CFBundleVersion` | Unique per upload; must increase |

Per [Apple CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion): period-separated integers only.

## CALarm format

**`YYYYMMDD.HHmm`** — e.g. `20260726.1057`

- Two integers (Apple-compliant)
- Monotonically increasing per deploy
- Displayed in Settings as `2026.07.26 · 10:57` via `AppBuildInfo.formatBuildNumber`

## Stamp before build

```bash
./scripts/stamp-build-version.sh
```

Updates all `CURRENT_PROJECT_VERSION = ...` in `Calarm.xcodeproj/project.pbxproj`.

Called automatically by `deploy.sh` and `release.sh`.

## Info.plist wiring

```xml
<key>CFBundleShortVersionString</key>
<string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>
<string>$(CURRENT_PROJECT_VERSION)</string>
```

## Verify built app

```bash
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" path/to/Calarm.app/Info.plist
```

## Settings UI

- `Calarm/Utilities/AppBuildInfo.swift` reads bundle metadata
- `SettingsSheet` shows build under title + pinned footer (`settings.developerInfo`)

## TestFlight note

ASC rejects duplicate build numbers. Always stamp before a new upload.
