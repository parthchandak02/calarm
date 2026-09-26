---
name: calarm-release-pipeline
description: >-
  CALarm iOS release pipeline: the single ship.sh entry point, its step library
  (scripts/lib/pipeline.sh), ios-app.config and credential setup. Use when changing the
  release pipeline, bootstrapping releases, or porting it to another app.
---

# CALarm Release Pipeline

## Entry points

**One script ships: `scripts/ship.sh`.** Its steps are functions in `scripts/lib/pipeline.sh`
(`run_doctor`, `stamp_build_number`, `archive_and_upload`, `asc_build_id`, `assign_testers`,
`verify_in_beta`, `record_build`, `publish_build_record`). To change the pipeline, change a
function or add one and call it from `ship.sh`. **Do not add another ship script**: the
previous seven-script chain let the upload, tester assignment and verification disagree
about which build they meant.

| Command | Purpose |
|---------|---------|
| `./scripts/ship.sh beta` | **The ship.** On the signing Mac: fast-forward to `main`, keychain, doctor, tests, stamp, archive + upload, then `finish` |
| `./scripts/ship.sh finish <build>` | Resume after the upload: wait for Apple (≤30 min), add that build to Internal Testing by ID, verify `IN_BETA_TESTING`, record, push |
| `./scripts/ship.sh doctor` | Toolchain, credentials, signing probe, ASC auth |
| `./scripts/ship.sh stamp` | Fresh `YYYYMMDD.HHmm` CFBundleVersion (`deploy.sh` calls it) |
| `./scripts/ship.sh metadata` / `screenshots` | App Store metadata upload / screenshot generation |
| `./deploy.sh 1` / `./deploy.sh 2` | Simulator / physical device debug install |

## Config

- `ios-app.config.sh` — per-app constants (bundle ID, scheme, ASC SKU, capabilities)
- Copy from `ios-app.config.sh.example` for new apps
- `scripts/lib/pipeline.sh` — config loading plus every release step

## Credential setup (one-time)

```bash
./scripts/configure-credentials.sh <ASC_ISSUER_ID> [ASC_APP_APPLE_ID]
./scripts/setup-asc-cli.sh
./scripts/bootstrap-portal.sh   # Siri / bundle IDs via asc
```

## Doctor

```bash
./scripts/ship.sh doctor
```

Checks: Xcode, bundler, fastlane, asc, jq, ExportOptions, privacy manifest, export-encryption
key, `fastlane/.env` values (incl. the tester group ID), ASC auth, placeholder URLs, a Release
signing build, screenshots.

## Port to another iOS app

1. Copy `ios-app.config.sh.example` → `ios-app.config.sh`
2. `./pipeline/install-into-repo.sh <other-repo>` copies `ship.sh`, the library and setup tools
3. Replace CALarm-specific checks in `run_doctor` (privacy manifest path, Info.plist path) and the test scheme in `run_calarm_unit_tests`
4. Set `REQUIRED_CAPABILITIES` for portal bootstrap

## Docs

- `docs/app-store/PUBLISH_PLAYBOOK.md`
- `docs/app-store/TERMINAL_TOOLS.md`
- `docs/app-store/IDENTIFIER_CLEANUP.md`

## Agent pairing

- `calarm-ship-ready` agent — code audit + device deploy
- `calarm-app-store-prep` agent — metadata + ASC checklist
