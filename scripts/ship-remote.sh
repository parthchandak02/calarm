#!/usr/bin/env bash
# Ship CALarm to TestFlight in one command, from this Mac:
#
#   ./scripts/ship-remote.sh
#
# Builds on macmini-remote, the only Mac with the signing identity and ASC key. The one
# manual step is the mini's login keychain password: the unlock must happen in the same SSH
# session as the build, and the owner types it. Everything else — pull, tests, archive,
# upload, tester group, ASC verification, recording the build in the docs, committing and
# pushing the stamp, pulling it back here — is done by scripts/ship-on-mini.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n==> [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

step "Preflight on this Mac"
branch="$(git branch --show-current)"
[[ "$branch" == main ]] || { echo "ERROR: on '$branch'. Ship from main."; exit 1; }
git fetch -q origin main
unpushed="$(git rev-list --count origin/main..HEAD)"
[[ "$unpushed" == 0 ]] || { echo "ERROR: $unpushed commit(s) not pushed. The mini ships origin/main — run: git push origin main"; exit 1; }
git diff --quiet HEAD || echo "WARNING: uncommitted changes here will not ship."
echo "Shipping origin/main at $(git log -1 --format='%h %s' origin/main)"

mkdir -p build/logs
log="build/logs/ship-$(date +%Y%m%d-%H%M%S).log"
echo "Full log: $log"

step "Ship on macmini-remote — type the Mac mini's keychain password when asked"
ssh -t macmini-remote 'set -e
security unlock-keychain ~/Library/Keychains/login.keychain-db
cd ~/projects/calarm
git reset -q --hard HEAD
git pull -q --ff-only origin main
./scripts/ship-on-mini.sh' 2>&1 | tee "$log"

step "Pull the stamp commit back to this Mac"
git pull -q --ff-only origin main
git log -1 --format='%h %s'
