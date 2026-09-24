#!/usr/bin/env bash
# Ships a TestFlight build from macmini-remote, the only Mac with the signing identity and
# ASC key, then commits the build stamp back to main so every build number lives on one
# branch. The keychain unlock must share the build's SSH session; the owner types it.
set -euo pipefail

ssh -t macmini-remote 'set -euo pipefail
security unlock-keychain ~/Library/Keychains/login.keychain-db
cd ~/projects/calarm
git checkout -- Calarm.xcodeproj/project.pbxproj
git pull --ff-only origin main
./scripts/ship.sh beta
build=$(grep -m1 -o "CURRENT_PROJECT_VERSION = [0-9.]*" Calarm.xcodeproj/project.pbxproj | cut -d" " -f3)
git commit -qm "Stamp build $build (uploaded to TestFlight)" Calarm.xcodeproj/project.pbxproj
# The build takes minutes; if main moved meanwhile, replay the stamp on top rather than
# leave the mini diverged, which would block the next run'"'"'s fast-forward pull.
git pull -q --rebase origin main
git push -q origin main
echo "Shipped build $build and pushed its stamp to main"'

git pull -q --ff-only origin main
