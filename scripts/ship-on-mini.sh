#!/usr/bin/env bash
# Runs on macmini-remote with the keychain already unlocked; started by ship-remote.sh.
# Ships, verifies the build actually reached testers, records it in the docs, and pushes.
set -euo pipefail
cd "$(dirname "$0")/.."

started=$(date +%s)
step() { printf '\n==> [%s +%ss] %s\n' "$(date +%H:%M:%S)" "$(( $(date +%s) - started ))" "$*"; }

step "1/4 Ship: doctor, unit tests, archive, upload, Internal Testing group"
./scripts/ship.sh beta
build="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' Calarm.xcodeproj/project.pbxproj | head -n1)"

# The pipeline has printed success for a build that reached nobody, so the ship is not done
# until App Store Connect says the build is in beta testing.
step "2/4 Verify build $build in App Store Connect"
# shellcheck disable=SC1091
source fastlane/.env
state=""
for _ in $(seq 1 40); do
  id="$(asc builds list --app "$ASC_APP_APPLE_ID" --limit 5 --output json \
    | jq -r --arg v "$build" '.data[] | select(.attributes.version == $v) | .id' | head -n1)"
  if [[ -n "$id" ]]; then
    state="$(asc builds build-beta-detail view --build-id "$id" --output json \
      | jq -r '.. | .internalBuildState? // empty' | head -n1)"
    echo "    build $build ($id): ${state:-unknown}"
    [[ "$state" == IN_BETA_TESTING ]] && break
  else
    echo "    build $build not listed yet"
  fi
  sleep 15
done
[[ "$state" == IN_BETA_TESTING ]] || { echo "ERROR: build $build is '${state:-missing}', not IN_BETA_TESTING. Not recording it."; exit 1; }

step "3/4 Record build $build in STATUS.md and CHANGELOG.md"
./scripts/record-build.sh "$build"

step "4/4 Commit and push to main"
git commit -qm "Ship build $build to TestFlight" Calarm.xcodeproj/project.pbxproj STATUS.md CHANGELOG.md
# The build takes minutes; if main moved meanwhile, replay the commit on top rather than
# leave the mini diverged, which would block the next run's fast-forward pull.
git pull -q --rebase origin main
git push -q origin main

step "Done: build $build is IN_BETA_TESTING and recorded on main ($(git log -1 --format=%h))"
