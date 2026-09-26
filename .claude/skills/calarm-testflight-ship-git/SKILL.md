---
name: calarm-testflight-ship-git
description: >-
  Commit, push, and ship CALarm to TestFlight. Covers branch workflow, build
  stamping, stale IPA cleanup, fastlane upload, and Internal Testing group assignment.
  Use when the user asks to deploy to TestFlight, push changes, ship a beta build,
  or commit and push for release.
---

# CALarm TestFlight Ship & Git Push

## Prerequisites

```bash
cp fastlane/.env.example fastlane/.env   # once — ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, ASC_APP_APPLE_ID
cp ios-app.config.sh.example ios-app.config.sh   # once
```

Store `.p8` outside the repo (e.g. `~/Keys/AuthKey_XXXXX.p8`).

## Git: commit and push

Work goes straight to `main` unless the owner asks otherwise.

```bash
git status
git add <files>
git commit -m "Short imperative summary

Optional body explaining why."
git push origin main
```

**Push blocked by `.github/workflows/`?** GitHub OAuth may lack `workflow` scope. Either push from a local machine with full credentials, or temporarily omit the workflow commit from the branch.

## Pre-ship checklist

1. On `main`, committed and pushed — the mini ships whatever `origin/main` holds. No side
   branches for ship work.
2. Compile check (no Simulator.app, no booted sim unless the user explicitly asks):

```bash
xcodebuild -project Calarm.xcodeproj -scheme Calarm \
  -configuration Release -destination 'generic/platform=iOS' \
  -quiet build
```

Do **not** run `xcodebuild test` or boot simulators on this Mac unless the user says to. Tests eat RAM. Prefer a prior TEST SUCCEEDED run, or skip tests and archive.

3. Doctor:

```bash
./scripts/ship.sh doctor
```

## Ship to TestFlight

Shipping happens on the Mac that holds the distribution signing identity and the App
Store Connect key (the owner's is in AGENTS.md § Owner's setup). The keychain must be unlocked **in the same SSH session as the build** —
each `ssh` gets its own security session, so unlocking in a separate invocation does
nothing. The owner types the password; do not handle it.

```bash
./scripts/ship.sh beta        # at the signing Mac
ssh -t <signing-mac> '<repo>/scripts/ship.sh beta'   # over SSH; owner's exact command is in AGENTS.md § Owner's setup
```

One command; the owner types only the keychain password (or nothing, through the herdr pane in
AGENTS.md § Owner's setup). `ship.sh beta` refuses if anything but the build stamp is
uncommitted → `git pull --ff-only` → re-runs its updated self → keychain → doctor → tests →
stamp → archive + upload → `finish`: wait for Apple to process that exact build → add it to
Internal Testing **by build ID** → verify `IN_BETA_TESTING` → record (STATUS *Latest build*, top
`## Unreleased` CHANGELOG heading → `## Build N`) → commit `Ship build N to TestFlight` →
rebase → push. Then `git pull` here. Timed log in the signing Mac's `build/logs/ship-*.log`.

**If it fails after the upload** (Apple slow, an API timeout), nothing is lost: run
`./scripts/ship.sh finish <build>` on the signing Mac once Apple has processed the build. Do
not finish by hand.

**Not fastlane for binaries.** Its gym path never had the ASC API key auth that
`archive_and_upload` passes to xcodebuild, and fails with *No Accounts / No signing
certificate "iOS Distribution" found*. The `upload_beta` lane has been removed.

### Update release notes

Edit `fastlane/metadata/en-US/release_notes.txt` before upload. Fastlane sends this as the TestFlight changelog.

## Verify on App Store Connect — always

**A green ship log does not mean the build reached anyone.** This pipeline has produced a
successful upload with a build no tester could install, three separate times in one day.

```bash
source fastlane/.env
asc builds list --app "$ASC_APP_APPLE_ID" --limit 3 --output table --sort -uploadedDate
```

`Processing: VALID` only says Apple accepted the binary. The state that gates TestFlight is
`internalBuildState` on the build's `buildBetaDetail`, and it must read **`IN_BETA_TESTING`**,
not `READY_FOR_BETA_TESTING`. The API key's role returns 403 on `/builds/{id}/betaGroups`, so
read the beta detail rather than group membership.

Tester assignment (`assign_testers` in `scripts/lib/pipeline.sh`) looks up the stamped
`CURRENT_PROJECT_VERSION` with `asc_build_id` (numeric match: App Store Connect lists `.0204`
as `.204`), waits up to 30 min for it to be `VALID`, and assigns **that build ID**. Never use
`--latest`: right after an upload it is the previous build.

## Common errors

| Error | Fix |
|-------|-----|
| Build number already used | Re-run `./scripts/ship.sh beta`; it stamps a new number each run |
| `No Accounts / No signing certificate "iOS Distribution"` | You are on the fastlane/gym path. Use `./scripts/ship.sh beta` |
| `CodeSign errSecInternalComponent` over SSH | The login keychain is locked. Unlock it **in the same** `ssh -t` session as the build |
| Upload succeeded, build never appears for testers | Apple still processing (check `asc builds uploads list`), or a late step failed. `./scripts/ship.sh finish <build>` |
| Tests fail / DB locked | `pkill -9 -f xcodebuild`; retry with separate `-derivedDataPath /tmp/calarm-ci-dd` |
| Missing ASC credentials | `./scripts/configure-credentials.sh <ISSUER_ID>` |

## After ship

- Confirm testers see the new build in TestFlight (Internal group)
- Live Activity layout changes require a **fresh alarm schedule** — force-quit and reopen CALarm, or toggle an alarm, so widget extension updates

## Related skills

- `calarm-build-version-stamp` — build number format
- `calarm-testflight-fastlane` — ASC API details
- `calarm-release-pipeline` — `ship.sh` lanes overview
