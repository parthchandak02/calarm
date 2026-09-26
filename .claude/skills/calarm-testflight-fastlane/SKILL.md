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

The fastlane `upload_beta` lane was removed — it built through gym, and gym never received
the App Store Connect API key auth, failing with *No Accounts / No signing certificate "iOS
Distribution" found*. `ship.sh beta` runs `archive_and_upload` (in `scripts/lib/pipeline.sh`)
directly, whose `ExportOptions.plist` has `destination: upload`, so xcodebuild ships straight
to App Store Connect and writes no local IPA. The fastlane lanes below are kept for metadata
and bootstrap, not for shipping a build.

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
| `build_release` | Release archive → `build/export/Calarm.ipa`. Superseded by `ship.sh beta`'s `archive_and_upload` |
| `upload_metadata` | Descriptions, keywords, screenshots |
| `bootstrap_asc` | First-time app record (Apple ID + 2FA, not API key) |

`upload_beta` was removed — see above.

## Preflight

```bash
./scripts/ship.sh doctor
```

## Common errors

| Error | Fix |
|-------|-----|
| Build number already used | Run `./scripts/ship.sh stamp`, rebuild, re-upload |
| Missing ASC_ISSUER_ID | `./scripts/configure-credentials.sh <ISSUER_ID>` |
| Invalid icon alpha | Run `scripts/process-app-icon.py` (see `calarm-app-icon-alpha` skill) |

## Bundle ID

`com.calarmapp.calarm` — must match App Store Connect record.
