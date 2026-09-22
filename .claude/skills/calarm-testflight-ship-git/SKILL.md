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

1. On the branch that contains the changes to ship
2. Merge or rebase `origin/main` if needed; resolve conflicts
3. Compile check (no Simulator.app, no booted sim unless the user explicitly asks):

```bash
xcodebuild -project Calarm.xcodeproj -scheme Calarm \
  -configuration Release -destination 'generic/platform=iOS' \
  -quiet build
```

Do **not** run `xcodebuild test` or boot simulators on this Mac unless the user says to. Tests eat RAM. Prefer a prior TEST SUCCEEDED run, or skip tests and archive.

4. Doctor:

```bash
./scripts/ios-doctor.sh
```

## Ship to TestFlight

Shipping happens on **`macmini-remote`**, which holds the signing identity and the App
Store Connect key. The keychain must be unlocked **in the same SSH session as the build** —
each `ssh` gets its own security session, so unlocking in a separate invocation does
nothing. The owner types the password; do not handle it.

```bash
ssh -t macmini-remote 'security unlock-keychain ~/Library/Keychains/login.keychain-db && cd ~/projects/calarm && git pull --ff-only origin main && ./scripts/ship.sh beta'
```

Runs: doctor → unit tests → `./release.sh` → Internal Testing group.

**Not `fastlane ios upload_beta`.** That lane builds through gym, which never received the
ASC API key auth `release.sh` passes to xcodebuild, and fails with *No Accounts / No signing
certificate "iOS Distribution" found*. See the `calarm-testflight-fastlane` skill.

After a successful ship, commit the stamp the script wrote:

```bash
ssh macmini-remote 'cd ~/projects/calarm && git add -A && git commit -m "Stamp build YYYYMMDD.HHmm (uploaded to TestFlight)" && git push origin main'
git pull --ff-only origin main
```

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

Group assignment runs automatically at the end of `ship.sh beta` via
`scripts/add-testflight-internal-group.sh`, which waits for the stamped
`CURRENT_PROJECT_VERSION` to finish processing before assigning it. It used to pass
`--latest`, which resolves to the newest *processed* build — right after an upload that is
the previous one, so it re-assigned an old build and stranded the new one.

## Common errors

| Error | Fix |
|-------|-----|
| Build number already used | `stamp-build-version.sh`, delete `build/export/`, rebuild |
| `No Accounts / No signing certificate "iOS Distribution"` | You are on the fastlane/gym path. Use `./scripts/ship.sh beta` |
| `CodeSign errSecInternalComponent` over SSH | The login keychain is locked. Unlock it **in the same** `ssh -t` session as the build |
| Upload succeeded, build never appears for testers | Group assignment raced processing, or was skipped. Run `./scripts/add-testflight-internal-group.sh` |
| Tests fail / DB locked | `pkill -9 -f xcodebuild`; retry with separate `-derivedDataPath /tmp/calarm-ci-dd` |
| Missing ASC credentials | `./scripts/configure-credentials.sh <ISSUER_ID>` |

## After ship

- Confirm testers see the new build in TestFlight (Internal group)
- Live Activity layout changes require a **fresh alarm schedule** — force-quit and reopen CALarm, or toggle an alarm, so widget extension updates

## Related skills

- `calarm-build-version-stamp` — build number format
- `calarm-testflight-fastlane` — ASC API details
- `calarm-release-pipeline` — `ship.sh` lanes overview
