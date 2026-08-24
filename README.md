# Hermes Prebuilt Packages

Builds immutable Hermes toolchain packages. A release keeps the host bytecode
compiler and every target runtime on exactly one Hermes source revision and
bytecode version.

The release contract deliberately separates two lifetimes:

- `compiler-macos-arm64`, `compiler-linux-x64`, `compiler-windows-x64`, and
  `compiler-windows-arm64` contain the host `hermesc` used during local and CI
  application builds;
- runtime packages cover macOS arm64, iOS device arm64, Android arm64, Linux
  x64, and Windows x64/arm64, and contain target headers, static libraries,
  platform support, metadata, and licenses.

The Android runtime is a pure native arm64 package. It uses Hermes' lightweight
Unicode backend and does not require Java classes, fbjni, or an Android AAR.
ECMA-402 `Intl` is intentionally outside this toolchain contract.

Every GitHub release contains per-package `.tar.gz` archives, `manifest.json`,
and `checksums.txt`. Tags and release assets are immutable. These narrowly
scoped packages are intended for applications embedding Hermes; this is not a
general-purpose Hermes SDK.

## Release

Run **Release Hermes packages** from `main` with a tag matching
`hermes-static-h-b99-rN`, for example `hermes-static-h-b99-r0`.
