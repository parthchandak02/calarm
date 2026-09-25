---
name: calarm-release-pipeline
description: >-
  CALarm iOS release pipeline: ship.sh, ios-doctor, configure-credentials, ios-app.config,
  and reusable scripts for multi-app deployment. Use when bootstrapping releases or CI.
---

# CALarm Release Pipeline

## Entry points

| Command | Purpose |
|---------|---------|
| `./scripts/ship-testflight.sh` | **The one ship command**, run on the signing Mac (or over `ssh -t`). Updates itself from `main`, prompts for the keychain, ships, verifies `IN_BETA_TESTING`, records the build (`record-build.sh`), pushes |
| `./deploy.sh 1` | Simulator debug build |
| `./deploy.sh 2` | Physical device (stamp + install + verify) |
| `./release.sh` | Release archive + upload straight to App Store Connect (`ExportOptions` sets `destination: upload`, so no local IPA is written) |
| `./scripts/ship.sh doctor` | Toolchain + signing health check |
| `./scripts/ship.sh beta` | Doctor → tests → `./release.sh` → Internal Testing group. **The ship path** |
| `./scripts/ship.sh all` | Still routes through the fastlane `upload_beta` lane, which is broken — see `calarm-testflight-fastlane` |

## Config

- `ios-app.config.sh` — per-app constants (bundle ID, scheme, ASC SKU, capabilities)
- Copy from `ios-app.config.sh.example` for new apps
- `scripts/lib/pipeline.sh` — shared `load_app_config`, `asc_env_ready`, logging

## Credential setup (one-time)

```bash
./scripts/configure-credentials.sh <ASC_ISSUER_ID> [ASC_APP_APPLE_ID]
./scripts/setup-asc-cli.sh
./scripts/bootstrap-portal.sh   # Siri / bundle IDs via asc
```

## Doctor

```bash
./scripts/ios-doctor.sh
```

Checks: Xcode, bundle, fastlane, ASC auth, signing probe, screenshots.

## Port to another iOS app

1. Copy `ios-app.config.sh.example` → `ios-app.config.sh`
2. Copy `scripts/` pipeline scripts
3. Wire `fastlane/Fastfile` lanes
4. Set `REQUIRED_CAPABILITIES` for portal bootstrap

## Docs

- `docs/app-store/PUBLISH_PLAYBOOK.md`
- `docs/app-store/TERMINAL_TOOLS.md`
- `docs/app-store/IDENTIFIER_CLEANUP.md`

## Agent pairing

- `calarm-ship-ready` agent — code audit + device deploy
- `calarm-app-store-prep` agent — metadata + ASC checklist
