#!/usr/bin/env bash
# Capture App Store screenshots from the booted iOS simulator.
# Usage: ./scripts/capture-screenshots.sh [label]
# Example: open app to schedule view, then: ./scripts/capture-screenshots.sh 01_schedule

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/fastlane/screenshots/en-US"
LABEL="${1:-screenshot}"

mkdir -p "$OUT"
DEST="$OUT/${LABEL}.png"

if ! xcrun simctl list devices booted | grep -q Booted; then
  echo "No booted simulator. Boot one first, e.g.:"
  echo "  xcrun simctl boot 'iPhone 17 Pro Max'"
  echo "  open -a Simulator"
  exit 1
fi

xcrun simctl io booted screenshot "$DEST"
echo "Saved: $DEST"
echo "Required size for App Store (6.9\"): 1320×2868 — verify in Preview."
