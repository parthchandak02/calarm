#!/usr/bin/env bash
# Ensure App Store 1024×1024 icon has no alpha channel (ASC rejects transparent icons).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/scripts/process-app-icon.py" --source "${1:-/Users/parthchandak/Downloads/calarm-final.jpeg}"
sips -g hasAlpha "$ROOT/Calarm/Assets.xcassets/AppIcon.appiconset/calarm.png"
