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
./scripts/ship.sh beta
```

**Do not reach for `bundle exec fastlane ios upload_beta`.** That lane builds through gym,
and gym never received the App Store Connect API key auth that `release.sh` passes to
xcodebuild — it fails with *No Accounts / No signing certificate "iOS Distribution" found*.
`ship.sh beta` calls `./release.sh`, whose `ExportOptions.plist` has
`destination: upload`, so xcodebuild ships straight to App Store Connect and writes no
local IPA. The fastlane lanes below are kept for metadata and bootstrap, not for shipping
a build.

## Verify on ASC

```bash
source fastlane/.env
asc builds list --app "$ASC_APP_APPLE_ID" --limit 5 --output table --sort -uploadedDate
```

`Processing: VALID` only means Apple accepted the binary. **It does not mean any tester can
install it.** The state that gates TestFlight is `internalBuildState`, which must read
`IN_BETA_TESTING` rather than `READY_FOR_BETA_TESTING`. Query `buildBetaDetail` for it — the
API key's role returns 403 on `/builds/{id}/betaGroups`, so group membership cannot be read
directly.

Verify against App Store Connect rather than the ship script's own output. This pipeline has
printed a successful upload while the build reached nobody.

## Lanes (Fastfile)

| Lane | Purpose |
|------|---------|
| `build_release` | Release archive → `build/export/Calarm.ipa`. Superseded by `./release.sh` |
| `upload_beta` | **Broken — see above.** Lacks ASC API key auth |
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
