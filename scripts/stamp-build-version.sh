#!/usr/bin/env bash
# Stamp Apple-compliant build numbers before each deploy.
#
# Apple CFBundleVersion rules (developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion):
#   - Machine-readable string of one to three period-separated non-negative integers.
#   - Must monotonically increase for each App Store upload.
#
# We use two integers: YYYYMMDD.HHmm (e.g. 20260719.2204) so each deploy is unique,
# sortable, and human-readable when formatted in Settings.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_STAMP="$(date +"%Y%m%d.%H%M")"
PBXPROJ="Calarm.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
  echo "Missing $PBXPROJ"
  exit 1
fi

if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = ${BUILD_STAMP};/g" "$PBXPROJ"
else
  sed -i "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = ${BUILD_STAMP};/g" "$PBXPROJ"
fi

DISPLAY_DATE="$(date +"%Y.%m.%d")"
DISPLAY_TIME="$(date +"%H:%M")"
echo "Stamped CURRENT_PROJECT_VERSION=${BUILD_STAMP} (${DISPLAY_DATE} · ${DISPLAY_TIME})"
