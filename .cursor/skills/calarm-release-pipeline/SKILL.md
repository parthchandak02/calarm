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
| `./deploy.sh 1` | Simulator debug build |
| `./deploy.sh 2` | Physical device (stamp + install + verify) |
| `./release.sh` | Release archive + App Store IPA |
| `./scripts/ship.sh doctor` | Toolchain + signing health check |
| `./scripts/ship.sh beta` | Doctor + TestFlight upload |
| `./scripts/ship.sh all` | Full pipeline when credentials ready |

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
