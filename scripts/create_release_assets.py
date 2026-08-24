#!/usr/bin/env python3
# Copyright (c) 2026 gugutu
# SPDX-License-Identifier: MIT

from __future__ import annotations

import hashlib
import json
import sys
import tarfile
from pathlib import Path


EXPECTED_TARGETS = {
    "compiler-macos-arm64",
    "runtime-macos-arm64",
    "runtime-ios-arm64",
    "runtime-android-arm64",
}


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: create_release_assets.py <artifact-root> <asset-dir> <tag>"
        )
    artifact_root = Path(sys.argv[1])
    asset_dir = Path(sys.argv[2])
    tag = sys.argv[3]
    asset_dir.mkdir(parents=True, exist_ok=True)

    packages: list[dict[str, object]] = []
    seen: set[str] = set()
    revisions: set[str] = set()
    bytecode_versions: set[int] = set()
    for metadata_path in sorted(artifact_root.rglob("metadata.json")):
        package_dir = metadata_path.parent
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        target = str(metadata["package_target"])
        if target in seen:
            raise SystemExit(f"duplicate package target: {target}")
        seen.add(target)
        revisions.add(str(metadata["hermes_revision"]))
        bytecode_versions.add(int(metadata["bytecode_version"]))

        archive = asset_dir / f"{tag}-{target}.tar.gz"
        with tarfile.open(archive, "w:gz", compresslevel=9) as output:
            for path in sorted(package_dir.rglob("*")):
                output.add(path, path.relative_to(package_dir))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        packages.append(
            {
                "package_target": target,
                "package_kind": metadata["package_kind"],
                "rust_target": metadata["rust_target"],
                "asset": archive.name,
                "sha256": digest,
                "size": archive.stat().st_size,
                "metadata": metadata,
            }
        )

    if seen != EXPECTED_TARGETS:
        raise SystemExit(
            f"package target mismatch; missing={sorted(EXPECTED_TARGETS - seen)}, "
            f"unexpected={sorted(seen - EXPECTED_TARGETS)}"
        )
    if len(revisions) != 1 or len(bytecode_versions) != 1:
        raise SystemExit("release packages do not share one Hermes toolchain")

    manifest = {
        "schema_version": 1,
        "tag": tag,
        "hermes_revision": next(iter(revisions)),
        "bytecode_version": next(iter(bytecode_versions)),
        "packages": sorted(packages, key=lambda package: str(package["package_target"])),
    }
    manifest_path = asset_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    with (asset_dir / "checksums.txt").open("w", encoding="utf-8") as output:
        for package in manifest["packages"]:
            output.write(f"{package['sha256']}  {package['asset']}\n")
        output.write(
            f"{hashlib.sha256(manifest_path.read_bytes()).hexdigest()}  manifest.json\n"
        )

    (asset_dir / "release-notes.md").write_text(
        f"Hermes prebuilt toolchain `{tag}`.\n\n"
        f"Hermes revision: `{manifest['hermes_revision']}`  \n"
        f"Bytecode version: `{manifest['bytecode_version']}`\n\n"
        "The macOS arm64 compiler and all target runtimes are built from the "
        "same source revision. Archives contain immutable manifests, build "
        "metadata, checksums, and redistributed license files.\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

