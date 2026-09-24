#!/usr/bin/env bash
# Records a shipped build in the docs: STATUS.md "Latest build" and "Last updated", and the
# CHANGELOG's topmost "## Unreleased" heading becomes "## Build <n>".
#
#   ./scripts/record-build.sh 20260924.1447
set -euo pipefail
cd "$(dirname "$0")/.."
build="${1:?usage: record-build.sh <build number>}"

python3 - "$build" <<'PY'
import re, sys, datetime
build = sys.argv[1]
today = datetime.date.today().isoformat()

status = open("STATUS.md").read()
status = re.sub(r"\*\*Last updated: [0-9-]+\*\*", f"**Last updated: {today}**", status, count=1)
status = re.sub(r"^\| \*\*Latest build\*\* \|.*$",
                f"| **Latest build** | `{build}` — `VALID`, `IN_BETA_TESTING` (verified by `ship-on-mini.sh`) |",
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
