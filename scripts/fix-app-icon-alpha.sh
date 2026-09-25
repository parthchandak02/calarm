#!/usr/bin/env bash
# Ensure App Store 1024×1024 icon has no alpha channel (ASC rejects transparent icons).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source="${1:?usage: fix-app-icon-alpha.sh <source logo image>}"
python3 "$ROOT/scripts/process-app-icon.py" --source "$source"
sips -g hasAlpha "$ROOT/Calarm/Assets.xcassets/AppIcon.appiconset/calarm.png"
