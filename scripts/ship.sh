#!/usr/bin/env bash
# The iOS release pipeline: one entry point, steps in scripts/lib/pipeline.sh, per-app
# settings in ios-app.config.sh, credentials in fastlane/.env.
#
#   ./scripts/ship.sh beta            Ship to TestFlight. Run on the Mac that holds the
#                                     distribution identity and API key.
#                                     SKIP_SIM_TESTS=1 skips the Simulator test run.
#   ./scripts/ship.sh finish <build>  Resume after the upload: wait for Apple, add testers,
#                                     verify, record, push. Use when `beta` failed late.
#   ./scripts/ship.sh doctor          Tools, credentials, signing, App Store Connect.
#   ./scripts/ship.sh stamp           Stamp a fresh CFBundleVersion (deploy.sh uses this).
#   ./scripts/ship.sh metadata        Upload App Store metadata and screenshots, no binary.
#   ./scripts/ship.sh screenshots     Generate App Store screenshots.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/pipeline.sh"
load_app_config

started=$(date +%s)
step() { printf '\n==> [%s +%ss] %s\n' "$(date +%H:%M:%S)" "$(( $(date +%s) - started ))" "$*"; }

start_log() {
  mkdir -p build/logs
  local log
  log="build/logs/ship-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$log") 2>&1
  echo "$1 — log: $ROOT/$log"
}

# A ship always runs the pipeline that is on main. The only uncommitted change a ship leaves
# behind is the build stamp from a failed run; anything else is someone's work, so stop.
update_checkout() {
  local other
  other="$(git status --porcelain | grep -v " $(pbxproj)\$" || true)"
  if [[ -n "$other" ]]; then
    echo "ERROR: uncommitted changes besides the build stamp. Commit or stash them first:"
    echo "$other"
    exit 1
  fi
  git checkout -q -- "$(pbxproj)"
  git pull -q --ff-only origin main
}

# codesign over SSH needs the keychain unlocked inside that SSH session, so over SSH always
# unlock. Elsewhere (at the Mac, or a herdr pane with SSH_CONNECTION cleared) only if locked.
unlock_keychain() {
  local keychain=~/Library/Keychains/login.keychain-db
  if [[ -n "${SSH_CONNECTION:-}" ]] || ! security show-keychain-info "$keychain" >/dev/null 2>&1; then
    step "Unlock the login keychain (type this Mac's login password)"
    security unlock-keychain "$keychain"
  else
    step "Login keychain already unlocked"
  fi
}

finish() {
  local build="$1"
  load_asc_env
  export ASC_TIMEOUT="${ASC_TIMEOUT:-90s}"
  step "Add build $build to Internal Testing"
  assign_testers "$build"
  step "Verify build $build in App Store Connect"
  verify_in_beta "$build"
  step "Record build $build in STATUS.md and CHANGELOG.md, push"
  record_build "$build"
  publish_build_record "$build"
  step "Done: build $build is IN_BETA_TESTING and recorded on main ($(git log -1 --format=%h))"
}

case "${1:-}" in
  beta)
    if [[ "${2:-}" != --updated ]]; then
      update_checkout
      exec "$SCRIPT_DIR/ship.sh" beta --updated
    fi
    start_log "Shipping $(git log -1 --format='%h %s')"
    unlock_keychain
    step "Doctor"
    run_doctor
    if [[ "${SKIP_SIM_TESTS:-}" == 1 ]]; then
      # The owner's call when the Mac is short on disk or RAM: a Simulator run can exhaust
      # both. The archive still compiles everything; only the test run is skipped.
      step "Unit tests SKIPPED (SKIP_SIM_TESTS=1)"
    else
      step "Unit tests"
      run_calarm_unit_tests
    fi
    step "Stamp, archive, upload"
    stamp_build_number
    archive_and_upload
    finish "$(stamped_build)"
    ;;
  finish)
    build="${2:?usage: ship.sh finish <build number>}"
    start_log "Finishing build $build"
    finish "$build"
    ;;
  doctor) run_doctor ;;
  stamp) stamp_build_number ;;
  metadata)
    asc_env_ready || { echo "Configure credentials first: ./scripts/configure-credentials.sh <ISSUER_ID>"; exit 1; }
    bundle exec fastlane ios upload_metadata screenshots:true
    ;;
  screenshots) ./scripts/generate-app-store-screenshots.sh ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
