---
name: calarm-testflight-fastlane
description: >-
  Upload CALarm to TestFlight via fastlane and verify builds with asc CLI.
  Use for beta releases, ASC API keys, IPA export, and build processing checks.
---

# CALarm TestFlight & Fastlane

## Prerequisites

Copy and fill credentials (never commit):

```bash
cp fastlane/.env.example fastlane/.env
# ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, ASC_APP_APPLE_ID
```

Store `.p8` outside repo (e.g. `~/Keys/AuthKey_XXXXX.p8`).

## Upload beta

```bash
./scripts/stamp-build-version.sh
bundle exec fastlane ios build_release   # archive + export IPA
bundle exec fastlane ios upload_beta     # upload to TestFlight
```

Or: `./scripts/ship.sh beta`

## Verify on ASC

```bash
source fastlane/.env
asc builds list --app "$ASC_APP_APPLE_ID" --limit 5 --output table --sort -uploadedDate
```

Look for `Processing: VALID` and expected `Build` column (`YYYYMMDD.HHmm`).

## Lanes (Fastfile)

| Lane | Purpose |
|------|---------|
| `build_release` | Release archive → `build/export/Calarm.ipa` |
| `upload_beta` | Upload IPA + release notes from `fastlane/metadata/en-US/release_notes.txt` |
| `upload_metadata` | Descriptions, keywords, screenshots |
| `bootstrap_asc` | First-time app record (Apple ID + 2FA, not API key) |

## Preflight

```bash
./scripts/verify-asc-api.sh
./scripts/preflight-release.sh
./scripts/ios-doctor.sh
```

## Common errors

| Error | Fix |
|-------|-----|
| Build number already used | Run `stamp-build-version.sh`, rebuild, re-upload |
| Missing ASC_ISSUER_ID | `./scripts/configure-credentials.sh <ISSUER_ID>` |
| Invalid icon alpha | Run `scripts/process-app-icon.py` (see `calarm-app-icon-alpha` skill) |

## Bundle ID

`com.calarmapp.calarm` — must match App Store Connect record.
