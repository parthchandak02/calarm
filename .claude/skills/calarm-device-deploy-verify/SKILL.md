---
name: calarm-device-deploy-verify
description: >-
  Deploy CALarm to a physical iPhone via deploy.sh with post-install build verification.
  Use for USB/Wi-Fi device installs, stale-build recovery, and launch debugging.
---

# CALarm Device Deploy & Verify

## Quick deploy

```bash
cd "$(git rev-parse --show-toplevel)"
./deploy.sh 2
```

- Stamps build via `scripts/stamp-build-version.sh`
- Uses `xcodebuild install` (not devicectl-only) for physical devices
- Verifies on-device `CFBundleVersion` via `verify_device_install` in `deploy-lib.sh`

## Manual USB path (when deploy.sh fails)

```bash
./scripts/stamp-build-version.sh
xcodebuild -project Calarm.xcodeproj -scheme Calarm -sdk iphoneos \
  -configuration Debug -destination 'platform=iOS,id=DEVICE_UDID' \
  -derivedDataPath ./build -allowProvisioningUpdates install

APP=$(find build -path '*InstallationBuildProductsLocation*' -name Calarm.app -type d | head -1)
xcrun devicectl device install app --device DEVICE_UDID "$APP"
xcrun devicectl device process launch --device DEVICE_UDID com.calarmapp.calarm
```

## List devices

```bash
xcrun devicectl list devices
xcrun xctrace list devices | grep -v Simulator
```

Use **USB UDID** from xctrace for `xcodebuild -destination`. Keep phone **unlocked** during install.

## Stale build recovery

If device shows old `CFBundleVersion` after "INSTALL SUCCEEDED":

1. `xcrun devicectl device uninstall app --device UDID com.calarmapp.calarm`
2. Re-run `./deploy.sh 2`
3. Confirm: `xcrun devicectl device info apps --device UDID | grep -i calarm`

## Debug helpers

```bash
./deploy.sh monitor    # Live Activity logs
./deploy.sh lifecycle  # AlarmKit state
./deploy.sh auth       # AlarmKit authorization
```

## Common failures

| Error | Fix |
|-------|-----|
| `device is locked` | Unlock iPhone, keep screen on |
| `developer disk image` | USB cable, trust Mac, Developer Mode on |
| Build on device ≠ built .app | Force devicectl reinstall (deploy.sh does this) |
