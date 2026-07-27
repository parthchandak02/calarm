fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios bootstrap_asc

```sh
[bundle exec] fastlane ios bootstrap_asc
```

Create App Store Connect app + register bundle IDs (Apple ID + 2FA; does not use API key)

### ios build_release

```sh
[bundle exec] fastlane ios build_release
```

Archive Release build and export App Store IPA

### ios upload_beta

```sh
[bundle exec] fastlane ios upload_beta
```

Upload IPA to TestFlight (no review submission)

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload metadata only (no binary) — descriptions, keywords, URLs

### ios release

```sh
[bundle exec] fastlane ios release
```

Upload IPA + metadata and optionally submit for review

### ios precheck_metadata

```sh
[bundle exec] fastlane ios precheck_metadata
```

Run fastlane precheck against metadata

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Generate App Store screenshots via fastlane snapshot (simulator + demo data)

### ios bump_build

```sh
[bundle exec] fastlane ios bump_build
```

Bump build number to App Store Connect latest + 1

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
