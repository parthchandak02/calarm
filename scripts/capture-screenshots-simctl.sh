#!/usr/bin/env bash
# Reliable App Store screenshots via simulator + SCREENSHOT_MODE demo data.
# No UI test runner required — avoids AX/flaky XCTest issues on CI.
#
# Usage: ./scripts/capture-screenshots-simctl.sh
# Output: fastlane/screenshots/en-US/*.png (1320×2868 on iPhone 17 Pro Max)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEVICE="${SCREENSHOT_DEVICE:-iPhone 17 Pro Max}"
BUNDLE_ID="com.calarmapp.calarm"
OUT_DIR="fastlane/screenshots/en-US"
BUILD_PATH="build/screenshot-sim"
DERIVED="$BUILD_PATH/DerivedData"

mkdir -p "$OUT_DIR"

echo "==> Boot simulator: $DEVICE"
xcrun simctl shutdown all 2>/dev/null || true
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator >/dev/null 2>&1 || true
sleep 5

echo "==> Build Debug for simulator"
xcodebuild \
  -project Calarm.xcodeproj \
  -scheme Calarm \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  build >/dev/null

APP=$(find "$DERIVED" -name Calarm.app -path '*iphonesimulator*' -type d | head -1)
if [[ -z "${APP:-}" ]]; then
  echo "ERROR: Calarm.app not found after build"
  exit 1
fi

echo "==> Install $APP"
xcrun simctl install booted "$APP"

echo "==> Status bar (9:41, full battery) for App Store polish"
UDID=$(xcrun simctl list devices booted -j | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(iter(d.get('devices',{}).values()))[0]['udid'])" 2>/dev/null || xcrun simctl list devices | awk -F'[()]' '/Booted/{print $2; exit}')
if [[ -n "${UDID:-}" ]]; then
  xcrun simctl status_bar "$UDID" override \
    --time "2007-01-09T09:41:00-08:00" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 2>/dev/null || true
fi

capture() {
  local scene="$1"
  local filename="$2"
  local dest="$OUT_DIR/$filename"
  local tmp
  tmp="$(mktemp /tmp/calarm-shot.XXXXXX).png"

  xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.5
  xcrun simctl launch booted "$BUNDLE_ID" SCREENSHOT_MODE "SCREENSHOT_SCENE=$scene" >/dev/null
  sleep 2.5
  xcrun simctl io booted screenshot "$tmp"
  cp -f "$tmp" "$dest"
  rm -f "$tmp"
  echo "  ✓ $dest ($(file -b "$dest" | cut -d, -f1-2))"
}

echo "==> Capture scenes (demo calendar data)"
capture "schedule" "iPhone 17 Pro Max-01_Schedule.png"
capture "event_detail" "iPhone 17 Pro Max-02_Event_Alarms.png"
capture "settings" "iPhone 17 Pro Max-03_Settings.png"
capture "add_alarm" "iPhone 17 Pro Max-04_Add_Alarm.png"

echo ""
echo "Done — $(find "$OUT_DIR" -name '*.png' | wc -l | tr -d ' ') screenshots in $OUT_DIR"
echo "Upload: bundle exec fastlane ios upload_metadata screenshots:true"
