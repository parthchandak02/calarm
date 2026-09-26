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
  # Decide on the formatter up front. The old `| xcbeautify || xcodebuild test` fallback
  # re-ran the whole suite whenever xcbeautify was missing -- or whenever a test failed.
  local cmd=(xcodebuild test -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" \
    -destination "$destination" -only-testing:CalarmTests)
  if command -v xcbeautify >/dev/null 2>&1; then
    "${cmd[@]}" | xcbeautify
  else
    "${cmd[@]}"
  fi
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

# ---------------------------------------------------------------------------------------
# Release steps. `scripts/ship.sh` is the only caller; each step is one function so a ship
# that fails late can resume from that step (`ship.sh finish <build>`).
# ---------------------------------------------------------------------------------------

pbxproj() { echo "$XCODE_PROJECT/project.pbxproj"; }

stamped_build() {
  sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' "$(pbxproj)" | head -n1
}

# CFBundleVersion must be one to three dot-separated integers, increasing for every upload.
# YYYYMMDD.HHmm is unique per minute, sorts, and reads as a date in Settings.
stamp_build_number() {
  local stamp
  stamp="$(date +%Y%m%d.%H%M)"
  sed -i.bak "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = ${stamp};/g" "$(pbxproj)"
  rm -f "$(pbxproj).bak"
  echo "Stamped CURRENT_PROJECT_VERSION=${stamp}"
}

# Archives Release and exports with ExportOptions.plist, whose destination=upload sends the
# build straight to App Store Connect and writes no IPA. The API key is passed to xcodebuild
# so signing works headless; fastlane's gym never had it, which is why its lane was removed.
archive_and_upload() {
  load_asc_env
  local auth=()
  if [[ -n "${ASC_KEY_PATH:-}" && -f "${ASC_KEY_PATH}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  fi
  local archive="build/$ARCHIVE_NAME"
  rm -rf "$archive" build/export
  xcodebuild -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates \
    ${auth[@]+"${auth[@]}"} archive
  xcodebuild -exportArchive -archivePath "$archive" -exportPath build/export \
    -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
}

# App Store Connect ID of a build Apple has finished processing (VALID); empty if not yet.
# ASC strips leading zeros per dotted part (20260926.0204 is listed as 20260926.204), so the
# parts are compared as numbers: a string match never finds a build stamped before 10:00.
asc_build_id() {
  asc builds list --app "$ASC_APP_APPLE_ID" --processing-state VALID --sort -uploadedDate \
    --limit 20 --output json 2>/dev/null \
    | jq -r --arg v "$1" '
        ($v | split(".") | map(tonumber)) as $want
        | [.data[] | select((.attributes.version | split(".") | map(tonumber)) == $want)][0].id
        // empty' 2>/dev/null || true
}

# Waits for Apple to process <build>, then adds exactly that build to the Internal Testing
# group. Never `--latest`: until processing ends, "latest" is the previous build. Processing
# has taken hours, so give up after 30 minutes and say how to resume.
assign_testers() {
  local build="$1" id=""
  echo "    waiting for Apple to process $build (up to 30 min)"
  for _ in $(seq 1 120); do
    id="$(asc_build_id "$build")"
    [[ -n "$id" ]] && break
    sleep 15
  done
  if [[ -z "$id" ]]; then
    echo "ERROR: build $build is not processed yet. Nothing was assigned."
    echo "       Check: asc builds uploads list --app $ASC_APP_APPLE_ID"
    echo "       Resume when it is: ./scripts/ship.sh finish $build"
    return 1
  fi
  echo "    $build is $id; adding it to the Internal Testing group"
  asc builds add-groups --build-id "$id" --group "$ASC_INTERNAL_TESTING_GROUP_ID" --output table
}

# The pipeline has printed success for a build that reached nobody, so a ship is not done
# until App Store Connect reports this exact build as IN_BETA_TESTING.
verify_in_beta() {
  local build="$1" id state=""
  for _ in $(seq 1 20); do
    id="$(asc_build_id "$build")"
    if [[ -n "$id" ]]; then
      state="$(asc builds build-beta-detail view --build-id "$id" --output json 2>/dev/null \
        | jq -r '.. | .internalBuildState? // empty' | head -n1)"
      echo "    build $build ($id): ${state:-unknown}"
      [[ "$state" == IN_BETA_TESTING ]] && return 0
    fi
    sleep 15
  done
  echo "ERROR: build $build is '${state:-missing}', not IN_BETA_TESTING. Not recording it."
  return 1
}

# STATUS.md "Latest build" and "Last updated"; the top "## Unreleased" CHANGELOG heading
# becomes "## Build <n>" (or an empty entry is added if nothing was pending).
record_build() {
  python3 - "$1" <<'PY'
import re, sys, datetime
build = sys.argv[1]
today = datetime.date.today().isoformat()

status = open("STATUS.md").read()
status = re.sub(r"\*\*Last updated: [0-9-]+\*\*", f"**Last updated: {today}**", status, count=1)
status = re.sub(r"^\| \*\*Latest build\*\* \|.*$",
                f"| **Latest build** | `{build}` — `VALID`, `IN_BETA_TESTING` (verified by `ship.sh`) |",
                status, count=1, flags=re.M)
open("STATUS.md", "w").write(status)

changelog = open("CHANGELOG.md").read()
changelog, n = re.subn(r"^## Unreleased — ([0-9-]+)[^\n]*$", f"## Build {build} — \\1",
                       changelog, count=1, flags=re.M)
if n == 0:
    changelog = changelog.replace("\n---\n", f"\n---\n\n## Build {build} — {today}\n\nNo user-facing changes recorded.\n", 1)
open("CHANGELOG.md", "w").write(changelog)
print(f"    STATUS.md and CHANGELOG.md now name build {build}")
PY
}

# Commits the stamp and the build record. The build takes minutes; if main moved meanwhile,
# replay the commit on top rather than leave this checkout diverged.
publish_build_record() {
  git commit -qm "Ship build $1 to TestFlight" "$(pbxproj)" STATUS.md CHANGELOG.md
  git pull -q --rebase origin main
  git push -q origin main
}

# Tools, credentials, signing and App Store Connect access. Exits non-zero on a blocker.
run_doctor() {
  load_asc_env
  ensure_path_local_bin
  local red='\033[0;31m' green='\033[0;32m' yellow='\033[1;33m' nc='\033[0m'
  local fails=0 warns=0
  check() {
    if eval "$2" >/dev/null 2>&1; then echo -e "${green}✓${nc} $1"
    else echo -e "${red}✗${nc} $1"; fails=$((fails + 1)); fi
  }
  note() { echo -e "${yellow}!${nc} $1"; warns=$((warns + 1)); }

  echo "iOS release pipeline — doctor"
  echo "App: ${APP_DISPLAY_NAME} (${BUNDLE_ID})"
  echo "=============================="
  check "ios-app.config.sh" "test -f ios-app.config.sh"
  check "Xcode" "xcodebuild -version"
  check "Bundler" "bundle --version"
  check "fastlane (bundle)" "bundle exec fastlane --version"
  check "asc CLI" "command -v asc"
  check "jq" "command -v jq"
  check "ExportOptions.plist" "test -f ExportOptions.plist"
  check "Privacy manifest" "test -f Calarm/PrivacyInfo.xcprivacy"
  check "ITSAppUsesNonExemptEncryption in Info.plist" "grep -q ITSAppUsesNonExemptEncryption Calarm/Info.plist"
  check "fastlane/.env exists" "test -f fastlane/.env"
  if [[ -f Calarm/GoogleService-Info.plist && -f Config/Google.local.xcconfig ]]; then
    echo -e "${green}✓${nc} Google sign-in configured"
  else
    note "Google sign-in not configured — this build ships with it off. Run ./scripts/setup-google-oauth.sh <client plist>"
  fi

  if [[ -f fastlane/.env ]]; then
    check "ASC_KEY_ID" "test -n \"${ASC_KEY_ID:-}\""
    check "ASC_ISSUER_ID" "test -n \"${ASC_ISSUER_ID:-}\""
    check "ASC_KEY_PATH file" "test -f \"${ASC_KEY_PATH:-/missing}\""
    check "ASC_APP_APPLE_ID" "test -n \"${ASC_APP_APPLE_ID:-}\""
    check "ASC_INTERNAL_TESTING_GROUP_ID" "test -n \"${ASC_INTERNAL_TESTING_GROUP_ID:-}\""
  else
    note "Copy fastlane/.env.example → fastlane/.env"
  fi

  if asc_env_ready && command -v asc >/dev/null; then
    asc_export_env
    if asc auth doctor >/dev/null 2>&1 || asc apps list --limit 1 >/dev/null 2>&1; then
      echo -e "${green}✓${nc} asc API authentication"
    else
      note "asc not authenticated — run ./scripts/setup-asc-cli.sh"
    fi
  fi

  local url
  for url in privacy_url support_url; do
    if grep -q example.com "fastlane/metadata/en-US/$url.txt" 2>/dev/null; then
      note "$url.txt still uses example.com"
    fi
  done

  echo ""
  echo "Signing / build probe (Release)..."
  if xcodebuild -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" -configuration Release \
    -destination 'generic/platform=iOS' -allowProvisioningUpdates build 2>&1 \
    | tee /tmp/ios-doctor-build.log | tail -3 | grep -q "BUILD SUCCEEDED"; then
    echo -e "${green}✓${nc} Release build succeeds"
  elif grep -q "Siri capability" /tmp/ios-doctor-build.log 2>/dev/null; then
    echo -e "${red}✗${nc} Release build — Siri capability missing on App ID. Fix: ./scripts/bootstrap-portal.sh"
    fails=$((fails + 1))
  else
    echo -e "${red}✗${nc} Release build failed — see /tmp/ios-doctor-build.log"
    fails=$((fails + 1))
  fi

  local shots
  shots=$(find fastlane/screenshots/en-US -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$shots" -ge 1 ]]; then
    echo -e "${green}✓${nc} $shots screenshot(s) in fastlane/screenshots/en-US/"
  else
    note "No screenshots — ./scripts/ship.sh screenshots (needed for App Store, not TestFlight)"
  fi

  echo ""
  if [[ $fails -eq 0 ]]; then
    echo -e "${green}Doctor: ready to ship${nc} (warnings: $warns)"
  else
    echo -e "${red}Doctor: $fails blocker(s), $warns warning(s)${nc}"
    return 1
  fi
}
