#!/usr/bin/env bash
# Install iOS release pipeline scripts into another Xcode repo.
#
# Usage: ./pipeline/install-into-repo.sh /path/to/OtherApp
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/target-repo"
  exit 1
fi

TARGET="$(cd "$1" && pwd)"
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$TARGET/scripts/lib"

FILES=(
  ios-app.config.sh.example
  release.sh
  ExportOptions.plist.example
  scripts/lib/pipeline.sh
  scripts/ios-doctor.sh
  scripts/configure-credentials.sh
  scripts/bootstrap-portal.sh
  scripts/setup-asc-cli.sh
  scripts/verify-asc-api.sh
  scripts/ship.sh
  scripts/preflight-release.sh
  pipeline/BOOTSTRAP_NEW_APP.md
)

for f in "${FILES[@]}"; do
  dest="$TARGET/$(basename "$f")"
  case "$f" in
    scripts/*) dest="$TARGET/$f" ;;
    pipeline/*) mkdir -p "$TARGET/pipeline"; dest="$TARGET/$f" ;;
    ios-app.config.sh.example) dest="$TARGET/ios-app.config.sh.example" ;;
    *) dest="$TARGET/$(basename "$f")" ;;
  esac
  mkdir -p "$(dirname "$dest")"
  cp "$SOURCE/$f" "$dest"
  echo "copied → $dest"
done

chmod +x "$TARGET/scripts/"*.sh 2>/dev/null || true

if [[ ! -f "$TARGET/ios-app.config.sh" ]]; then
  cp "$TARGET/ios-app.config.sh.example" "$TARGET/ios-app.config.sh"
  echo "created ios-app.config.sh — edit before shipping"
fi

if [[ ! -f "$TARGET/ExportOptions.plist" && -f "$TARGET/ExportOptions.plist.example" ]]; then
  cp "$TARGET/ExportOptions.plist.example" "$TARGET/ExportOptions.plist"
fi

echo ""
echo "Done. Next in $TARGET:"
echo "  1. Edit ios-app.config.sh"
echo "  2. Add fastlane/ (copy from CALarm or run fastlane init)"
echo "  3. ./scripts/configure-credentials.sh <ISSUER_ID>"
