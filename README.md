# Hermes Prebuilt Packages

Builds immutable Hermes toolchain packages for Orch UI. A release keeps the
host bytecode compiler and every target runtime on exactly one Hermes source
revision and bytecode version.

The release contract deliberately separates two lifetimes:

- `compiler-macos-arm64` contains the host `hermesc` used during application
  builds;
- `runtime-macos-arm64`, `runtime-ios-arm64`, and
  `runtime-android-arm64` contain target headers, static libraries, platform
  support, metadata, and licenses.

Android packages contain only the arm64 fbjni linker library and Hermes Intl
classes. Applications obtain the matching fbjni runtime through its Maven
dependency and choose their final ABI set with Gradle `abiFilters`.

Every GitHub release contains per-package `.tar.gz` archives, `manifest.json`,
and `checksums.txt`. Tags and release assets are immutable. This repository is
the binary toolchain source for Orch UI, not a general-purpose Hermes SDK.

## Release

Run **Release Hermes packages** from `main` with a tag matching
`hermes-static-h-b99-rN`, for example `hermes-static-h-b99-r0`.

