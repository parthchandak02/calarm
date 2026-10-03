# What only you can do (App Store release)

**Status (2026-10-03):** Repo is prepped for 1.0: iPhone only, no data collected, metadata and
review notes in `fastlane/metadata/`. Google data access is verified. Submission waits on
Gate 1 and the device checks in [STATUS.md](../../STATUS.md).

## In order

1. **Sign the expired Apple agreement**: App Store Connect → Business (or
   developer.apple.com → Account). Then check the API works:
   `ssh macmini-remote 'export PATH=/opt/homebrew/bin:$PATH; asc versions list --app 6787163619 --output table'`
2. **Ship a build with these changes**: `ssh -t macmini-remote '~/projects/calarm/scripts/ship.sh beta'`
3. **Finish the device checks** in STATUS *Waiting on the owner*, including Google sign-in
   with the verified client, and settle Gate 1.
4. **App Store Connect, CALarm → App Information and the 1.0 version page:**
   - App Privacy: **Data Not Collected**. Tracking: No.
   - Age rating questionnaire: no mature content.
   - Pricing: Free. Availability: your choice of countries.
   - Review contact: name, email and phone (phone in App Store Connect only, never in this repo).
5. **Screenshots**: `./scripts/generate-app-store-screenshots.sh` on a Mac with Simulator.app
   (6.9" iPhone, 1320x2868), then upload metadata:
   `bundle exec fastlane ios precheck_metadata` and
   `bundle exec fastlane ios upload_metadata screenshots:true`
6. **Attach the build** to version 1.0, confirm export compliance (pre-answered: no
   non-exempt encryption), and **Submit for Review**.

## Optional

- Delete the old "CALarm iOS" OAuth client in Google Cloud project `useful-field-497119-k5`.
