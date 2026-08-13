#!/usr/bin/env bash
# Shared helpers for iOS release pipeline scripts.
set -euo pipefail

find_repo_root() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/ios-app.config.sh" || -f "$dir/ios-app.config.sh.example" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

pipeline_root() {
  local start="${1:-$(dirname "${BASH_SOURCE[1]}")}"
  find_repo_root "$(cd "$start" && pwd)"
}

load_app_config() {
  local root
  root="${ROOT:-$(pipeline_root "$(dirname "${BASH_SOURCE[1]}")")}"
  if [[ -z "$root" || ! -f "$root/ios-app.config.sh" ]]; then
    echo "Missing ios-app.config.sh — copy from ios-app.config.sh.example in repo root"
    exit 1
  fi
  ROOT="$root"
  # shellcheck disable=SC1090
  source "$ROOT/ios-app.config.sh"
}

load_asc_env() {
  local root="${ROOT:-$(pipeline_root "$(dirname "${BASH_SOURCE[1]}")")}"
  if [[ -f "$root/fastlane/.env" ]]; then
    # shellcheck disable=SC1091
    source "$root/fastlane/.env"
  fi
}

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing command: $name"
    return 1
  fi
}

asc_env_ready() {
  load_asc_env
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" && -f "${ASC_KEY_PATH:-/dev/null}" ]]
}

asc_export_env() {
  load_asc_env
  export ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH ASC_APP_APPLE_ID FASTLANE_TEAM_ID
  export ASC_PRIVATE_KEY_PATH="${ASC_KEY_PATH:-}"
}

log_step() {
  echo ""
  echo "==> $*"
  echo "----"
}

run_calarm_unit_tests() {
  local destination="${1:-platform=iOS Simulator,name=iPhone 17}"
  if ! xcodebuild -showdestinations -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" 2>/dev/null \
    | grep -q 'name:iPhone 17[^a-zA-Z]'; then
    warn "iPhone 17 simulator not found; using generic iOS Simulator"
    destination="generic/platform=iOS Simulator"
  fi
  xcodebuild test \
    -project "$XCODE_PROJECT" \
    -scheme "$XCODE_SCHEME" \
    -destination "$destination" \
    -only-testing:CalarmTests \
    | xcbeautify 2>/dev/null || xcodebuild test \
      -project "$XCODE_PROJECT" \
      -scheme "$XCODE_SCHEME" \
      -destination "$destination" \
      -only-testing:CalarmTests
}

warn() {
  echo "!! $*"
}

ok() {
  echo "ok $*"
}

fail() {
  echo "FAIL $*"
  return 1
}

ensure_path_local_bin() {
  export PATH="$HOME/.local/bin:$PATH"
}
