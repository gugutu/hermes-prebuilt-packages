#!/usr/bin/env bash
# Copyright (c) 2026 gugutu
# SPDX-License-Identifier: MIT

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/hermes.env
source "$root/config/hermes.env"
source_dir="${HERMES_SOURCE_DIR:-$root/work/hermes-source}"

rm -rf "$source_dir"
mkdir -p "$(dirname "$source_dir")"
git init --quiet "$source_dir"
git -C "$source_dir" remote add origin "$HERMES_REPOSITORY"
git -C "$source_dir" fetch --depth=1 origin "$HERMES_REVISION"
git -C "$source_dir" checkout --quiet --detach FETCH_HEAD

for patch in "$root"/patches/*.patch; do
  [[ -e "$patch" ]] || continue
  git -C "$source_dir" apply --check "$patch"
  git -C "$source_dir" apply "$patch"
done

actual_revision="$(git -C "$source_dir" rev-parse HEAD)"
if [[ "$actual_revision" != "$HERMES_REVISION" ]]; then
  echo "Hermes source revision mismatch: $actual_revision" >&2
  exit 1
fi

bytecode_version="$(sed -n 's/.*BYTECODE_VERSION = \([0-9][0-9]*\).*/\1/p' \
  "$source_dir/include/hermes/BCGen/HBC/BytecodeVersion.h")"
if [[ "$bytecode_version" != "$HERMES_BYTECODE_VERSION" ]]; then
  echo "Hermes bytecode version mismatch: $bytecode_version" >&2
  exit 1
fi

printf 'Prepared Hermes %s (bytecode %s)\n' "$actual_revision" "$bytecode_version"
