#!/usr/bin/env bash
# Master iOS ship pipeline — doctor → build → TestFlight → optional metadata.
#
# Usage:
#   ./scripts/ship.sh doctor
#   ./scripts/ship.sh build
#   ./scripts/ship.sh beta          # TestFlight upload
#   ./scripts/ship.sh metadata        # ASC metadata only
#   ./scripts/ship.sh screenshots
#   ./scripts/ship.sh all             # doctor + beta + metadata
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/pipeline.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
load_app_config

CMD="${1:-doctor}"

case "$CMD" in
  doctor)
    "$SCRIPT_DIR/ios-doctor.sh"
    ;;
  build)
    log_step "Release archive + IPA"
    ./release.sh
    ;;
  beta)
    "$SCRIPT_DIR/ios-doctor.sh"
    log_step "Unit tests"
    run_calarm_unit_tests
    log_step "TestFlight upload (fastlane)"
    bundle exec fastlane ios upload_beta
    ;;
  metadata)
    asc_env_ready || { echo "Configure credentials first: ./scripts/configure-credentials.sh <ISSUER_ID>"; exit 1; }
    log_step "Upload metadata"
    bundle exec fastlane ios upload_metadata screenshots:true
    ;;
  screenshots)
  log_step "Generate App Store screenshots"
    ./scripts/generate-app-store-screenshots.sh
    ;;
  all)
    "$SCRIPT_DIR/ios-doctor.sh"
    log_step "Unit tests"
    run_calarm_unit_tests
    bundle exec fastlane ios upload_beta
    bundle exec fastlane ios upload_metadata screenshots:true
    ;;
  *)
    echo "Usage: $0 {doctor|build|beta|metadata|screenshots|all}"
    exit 1
    ;;
esac
