#!/usr/bin/env bash
# Copyright (c) 2026 gugutu
# SPDX-License-Identifier: MIT

set -euo pipefail

target="${1:-}"
if [[ -z "$target" ]]; then
  echo "usage: $0 <compiler-macos-arm64|compiler-linux-x64|runtime-macos-arm64|runtime-ios-arm64|runtime-android-arm64>" >&2
  exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/hermes.env
source "$root/config/hermes.env"
source_dir="${HERMES_SOURCE_DIR:-$root/work/hermes-source}"
build_root="$root/work/build/$target"
package_dir="$root/work/package/$target"
package_tag="${HERMES_PACKAGE_TAG:-local}"

if [[ ! -f "$source_dir/CMakeLists.txt" ]]; then
  echo "Hermes source is missing; run scripts/prepare_source.sh first" >&2
  exit 1
fi

rm -rf "$package_dir"
mkdir -p "$package_dir/LICENSES"

common_cmake=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=MinSizeRel
  -DHERMES_ENABLE_NAPI=OFF
  -DHERMES_ENABLE_INTL=ON
  -DHERMES_ENABLE_CORE_EXTENSIONS=ON
  -DHERMES_ENABLE_CONTRIB_EXTENSIONS=ON
  -DHERMES_ENABLE_DEBUGGER=OFF
  -DHERMES_BUILD_SHARED_JSI=OFF
)

copy_licenses() {
  cp "$source_dir/LICENSE" "$package_dir/LICENSES/Hermes-LICENSE"
  cp "$source_dir/external/boost/boost_1_86_0/LICENSE_1_0.txt" \
    "$package_dir/LICENSES/Boost-LICENSE_1_0.txt"
}

copy_runtime_sdk() {
  local output_dir=$1
  mkdir -p "$package_dir/include/hermes" "$package_dir/include/jsi" "$package_dir/lib"
  cp "$source_dir/API/hermes/hermes.h" "$package_dir/include/hermes/hermes.h"
  cp -R "$source_dir/public/hermes/Public" "$package_dir/include/hermes/Public"
  cp -R "$source_dir/API/jsi/jsi/." "$package_dir/include/jsi"
  cp "$output_dir/lib/libhermesvm_a.a" "$package_dir/lib/libhermesvm.a"
  cp "$output_dir/jsi/libjsi.a" "$package_dir/lib/libjsi.a"
  cp "$output_dir/external/boost/boost_1_86_0/libs/context/libboost_context.a" \
    "$package_dir/lib/libboost_context.a"
}

package_kind=runtime
rust_target=
platform_support=
fbjni_version=

case "$target" in
  compiler-macos-arm64)
    package_kind=compiler
    rust_target=aarch64-apple-darwin
    platform_support=host-macos
    cmake -S "$source_dir" -B "$build_root" "${common_cmake[@]}" \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
    cmake --build "$build_root" --target hermesc
    mkdir -p "$package_dir/bin"
    cp "$build_root/bin/hermesc" "$package_dir/bin/hermesc"
    ;;
  compiler-linux-x64)
    package_kind=compiler
    rust_target=x86_64-unknown-linux-gnu
    platform_support=host-linux
    cmake -S "$source_dir" -B "$build_root" "${common_cmake[@]}"
    cmake --build "$build_root" --target hermesc
    mkdir -p "$package_dir/bin"
    cp "$build_root/bin/hermesc" "$package_dir/bin/hermesc"
    ;;
  runtime-macos-arm64)
    rust_target=aarch64-apple-darwin
    platform_support=apple
    cmake -S "$source_dir" -B "$build_root" "${common_cmake[@]}" \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
    cmake --build "$build_root" --target hermesvm_a jsi
    copy_runtime_sdk "$build_root"
    ;;
  runtime-ios-arm64)
    rust_target=aarch64-apple-ios
    platform_support=apple
    host_build="$build_root/host"
    target_build="$build_root/target"
    cmake -S "$source_dir" -B "$host_build" "${common_cmake[@]}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
    cmake --build "$host_build" --target hermesc
    cmake -S "$source_dir" -B "$target_build" "${common_cmake[@]}" \
      -DCMAKE_OSX_SYSROOT=iphoneos \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
      -DIMPORT_HOST_COMPILERS="$host_build/ImportHostCompilers.cmake"
    cmake --build "$target_build" --target hermesvm_a jsi
    copy_runtime_sdk "$target_build"
    ;;
  runtime-android-arm64)
    rust_target=aarch64-linux-android
    platform_support=android-fbjni
    fbjni_version="$FBJNI_VERSION"
    android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
    android_ndk="${ANDROID_NDK:-$android_sdk/ndk/$ANDROID_NDK_VERSION}"
    if [[ ! -f "$android_ndk/build/cmake/android.toolchain.cmake" ]]; then
      echo "Android NDK is missing: $android_ndk" >&2
      exit 1
    fi

    ANDROID_SDK_ROOT="$android_sdk" HERMES_WS_DIR="$source_dir" \
      "$source_dir/android/gradlew" -p "$source_dir/android" \
      -PndkPath="$android_ndk" \
      'configureCMakeRelease[arm64-v8a]' \
      compileReleaseJavaWithJavac \
      --quiet

    host_compilers="$source_dir/build/ImportHostCompilers.cmake"
    fbjni_config="$(find "$source_dir/build" "$source_dir/android/.cxx" \
      -path '*/arm64-v8a/*/fbjniConfig.cmake' -print 2>/dev/null | head -1)"
    if [[ ! -f "$host_compilers" || -z "$fbjni_config" ]]; then
      echo "Official Hermes Android bootstrap did not produce host compilers or fbjni Prefab" >&2
      exit 1
    fi

    target_build="$build_root/target"
    cmake -S "$source_dir" -B "$target_build" "${common_cmake[@]}" \
      -DCMAKE_TOOLCHAIN_FILE="$android_ndk/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
      -DANDROID_STL=c++_shared \
      -DHERMES_IS_ANDROID=ON \
      -DIMPORT_HOST_COMPILERS="$host_compilers" \
      -DJSI_DIR="$source_dir/API/jsi" \
      -Dfbjni_DIR="$(dirname "$fbjni_config")" \
      -DHERMES_RELEASE_VERSION=1.0.0 \
      -DHERMESVM_HEAP_HV_MODE=HEAP_HV_PREFER32
    cmake --build "$target_build" --target hermesvm_a jsi
    copy_runtime_sdk "$target_build"

    gradle_home="${GRADLE_USER_HOME:-$HOME/.gradle}"
    fbjni_aar="$(find "$gradle_home/caches/modules-2/files-2.1/com.facebook.fbjni/fbjni/$FBJNI_VERSION" \
      -name "fbjni-$FBJNI_VERSION.aar" -type f -print | head -1)"
    java_classes="$(find "$source_dir/build/intermediates/javac/release" \
      -type d -name classes -print | head -1)"
    if [[ -z "$fbjni_aar" || -z "$java_classes" ]]; then
      echo "Hermes Android platform payload is incomplete" >&2
      exit 1
    fi
    mkdir -p "$package_dir/android"
    unzip -p "$fbjni_aar" jni/arm64-v8a/libfbjni.so > "$package_dir/lib/libfbjni.so"
    (cd "$java_classes" && jar --create --file "$package_dir/android/hermes-platform.jar" .)
    ;;
  *)
    echo "unsupported package target: $target" >&2
    exit 2
    ;;
esac

copy_licenses

cat > "$package_dir/manifest.toml" <<EOF
format_version = 2
package_kind = "$package_kind"
package_tag = "$package_tag"
source_revision = "$HERMES_REVISION"
source_branch = "$HERMES_BRANCH"
bytecode_version = $HERMES_BYTECODE_VERSION
target = "$rust_target"
intl = true
core_extensions = true
contrib_extensions = true
napi = false
platform_support = "$platform_support"
fbjni_version = "$fbjni_version"
EOF

python3 - "$package_dir/metadata.json" "$target" "$package_kind" "$rust_target" \
  "$platform_support" "$package_tag" "$HERMES_REVISION" "$HERMES_BRANCH" \
  "$HERMES_BYTECODE_VERSION" "$fbjni_version" <<'PY'
import json
import sys
from pathlib import Path

(
    output,
    target,
    kind,
    rust_target,
    platform_support,
    tag,
    revision,
    branch,
    bytecode_version,
    fbjni_version,
) = sys.argv[1:]
metadata = {
    "schema_version": 1,
    "package_target": target,
    "package_kind": kind,
    "rust_target": rust_target,
    "platform_support": platform_support,
    "package_tag": tag,
    "hermes_revision": revision,
    "hermes_branch": branch,
    "bytecode_version": int(bytecode_version),
    "features": {
        "intl": True,
        "core_extensions": True,
        "contrib_extensions": True,
        "napi": False,
    },
}
if fbjni_version:
    metadata["fbjni_version"] = fbjni_version
Path(output).write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
PY

printf 'Packaged %s at %s\n' "$target" "$package_dir"
