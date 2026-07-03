#!/usr/bin/env bash
# Generate App Store screenshots (simulator + SCREENSHOT_MODE demo data).
#
# Usage:
#   ./scripts/generate-app-store-screenshots.sh           # default: simctl (reliable)
#   ./scripts/generate-app-store-screenshots.sh --ui-tests  # fastlane snapshot (UI tests)
#   ./scripts/generate-app-store-screenshots.sh --frame     # add frameit after capture
#
# Output: fastlane/screenshots/en-US/ at 1320×2868 (iPhone 17 Pro Max)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="simctl"
FRAME=false

for arg in "$@"; do
  case "$arg" in
    --ui-tests) MODE="snapshot" ;;
    --frame) FRAME=true ;;
    -h|--help)
      echo "Usage: $0 [--ui-tests] [--frame]"
      exit 0
      ;;
  esac
done

echo "==> CALarm screenshot pipeline (mode: $MODE)"

bundle check >/dev/null 2>&1 || bundle install

if [[ "$MODE" == "snapshot" ]]; then
  echo "==> fastlane snapshot (UI tests)"
  bundle exec fastlane snapshot || {
    echo "WARN: snapshot failed — falling back to simctl capture"
    "$ROOT/scripts/capture-screenshots-simctl.sh"
  }
else
  "$ROOT/scripts/capture-screenshots-simctl.sh"
fi

if [[ "$FRAME" == "true" ]]; then
  if command -v convert >/dev/null 2>&1; then
    echo "==> frameit (optional marketing frames)"
    bundle exec fastlane frameit silver || echo "WARN: frameit skipped"
  else
    echo "WARN: ImageMagick not installed (brew install imagemagick) — skipping frameit"
  fi
fi

RAW_COUNT=$(find fastlane/screenshots/en-US -maxdepth 1 -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
echo "==> $RAW_COUNT screenshot(s) ready in fastlane/screenshots/en-US/"
