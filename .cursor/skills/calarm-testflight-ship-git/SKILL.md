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

Cloud Agent branches use `cursor/<descriptive-name>-b61b`.

```bash
git checkout -b cursor/my-feature-b61b   # if needed
git status
git add <files>
git commit -m "Short imperative summary

Optional body explaining why."
git push -u origin cursor/my-feature-b61b
```

**Push blocked by `.github/workflows/`?** GitHub OAuth may lack `workflow` scope. Either push from a local machine with full credentials, or temporarily omit the workflow commit from the branch.

## Pre-ship checklist

1. On the branch that contains the changes to ship
2. Merge or rebase `origin/main` if needed; resolve conflicts
3. Run unit tests:

```bash
xcodebuild test \
  -project Calarm.xcodeproj \
  -scheme Calarm \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CalarmTests
```

4. Doctor:

```bash
./scripts/ios-doctor.sh
```

## Ship to TestFlight

### Full pipeline (recommended)

```bash
./scripts/ship.sh beta
```

Runs: doctor → unit tests → `fastlane ios upload_beta` → Internal Testing group.

### Manual (when `ship.sh beta` fails on stale build number)

`upload_beta` skips archive if `build/export/Calarm.ipa` already exists. **Always remove stale artifacts and stamp before re-upload:**

```bash
rm -rf build/export build/Calarm.xcarchive
./scripts/stamp-build-version.sh          # YYYYMMDD.HHmm → CURRENT_PROJECT_VERSION
git add Calarm.xcodeproj/project.pbxproj
git commit -m "Stamp build for TestFlight upload"
git push -u origin <branch>
bundle exec fastlane ios upload_beta
```

### Update release notes

Edit `fastlane/metadata/en-US/release_notes.txt` before upload. Fastlane sends this as the TestFlight changelog.

## Verify on App Store Connect

```bash
source fastlane/.env
asc builds list --app "$ASC_APP_APPLE_ID" --limit 3 --output table --sort -uploadedDate
```

Expect `Processing: VALID`. Internal Testing assignment runs automatically via `scripts/add-testflight-internal-group.sh` at end of `upload_beta`.

## Common errors

| Error | Fix |
|-------|-----|
| Build number already used | `stamp-build-version.sh`, delete `build/export/`, rebuild |
| Stale IPA uploaded | `rm -rf build/export` before `upload_beta` |
| Tests fail / DB locked | `pkill -9 -f xcodebuild`; retry with separate `-derivedDataPath /tmp/calarm-ci-dd` |
| Missing ASC credentials | `./scripts/configure-credentials.sh <ISSUER_ID>` |

## After ship

- Confirm testers see the new build in TestFlight (Internal group)
- Live Activity layout changes require a **fresh alarm schedule** — force-quit and reopen CALarm, or toggle an alarm, so widget extension updates

## Related skills

- `calarm-build-version-stamp` — build number format
- `calarm-testflight-fastlane` — ASC API details
- `calarm-release-pipeline` — `ship.sh` lanes overview
