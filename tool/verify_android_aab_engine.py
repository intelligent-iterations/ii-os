#!/usr/bin/env python3
"""Bind an ii-os Android App Bundle to its exact attested engine AAR."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path, PurePosixPath


MAX_MEMBERS = 30_000
MAX_MEMBER_BYTES = 512 * 1024 * 1024

# Flutter 3.35+ applies these release ABI filters itself. The mobile engine AAR
# also carries legacy 32-bit x86 for non-Flutter consumers, but packaging it in
# a Flutter app would advertise an ABI for which Flutter has no AOT runtime.
# https://docs.flutter.dev/release/breaking-changes/default-abi-filters-android
FLUTTER_RELEASE_ABIS = frozenset({"armeabi-v7a", "arm64-v8a", "x86_64"})
ALLOWED_ENGINE_ONLY_ABIS = frozenset({"x86"})


def _checked_archive(path: Path) -> zipfile.ZipFile:
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"archive is missing or linked: {path}")
    archive = zipfile.ZipFile(path)
    if len(archive.infolist()) > MAX_MEMBERS:
        archive.close()
        raise RuntimeError(f"archive has too many members: {path}")
    for info in archive.infolist():
        member = PurePosixPath(info.filename)
        if (
            member.is_absolute()
            or ".." in member.parts
            or "\\" in info.filename
            or info.file_size > MAX_MEMBER_BYTES
        ):
            archive.close()
            raise RuntimeError(f"archive has an unsafe member: {info.filename}")
    return archive


def _member_sha256(archive: zipfile.ZipFile, name: str) -> str:
    info = archive.getinfo(name)
    if info.is_dir() or info.file_size > MAX_MEMBER_BYTES:
        raise RuntimeError(f"archive member is not a bounded file: {name}")
    digest = hashlib.sha256()
    read_bytes = 0
    with archive.open(info) as source:
        while chunk := source.read(1024 * 1024):
            read_bytes += len(chunk)
            if read_bytes > MAX_MEMBER_BYTES:
                raise RuntimeError(f"archive member exceeded its limit: {name}")
            digest.update(chunk)
    if read_bytes != info.file_size:
        raise RuntimeError(f"archive member changed while reading: {name}")
    return digest.hexdigest()


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify_android_aab_engine(aab_path: Path, aar_path: Path) -> dict[str, object]:
    aab = _checked_archive(aab_path)
    aar = _checked_archive(aar_path)
    try:
        sources = sorted(
            name
            for name in aar.namelist()
            if name.startswith("jni/") and name.endswith(".so")
        )
        if not sources:
            raise RuntimeError("attested Android engine contains no JNI libraries")
        source_abis = {
            PurePosixPath(source_name).parts[1]
            for source_name in sources
            if len(PurePosixPath(source_name).parts) == 3
        }
        missing_source_abis = FLUTTER_RELEASE_ABIS - source_abis
        if missing_source_abis:
            raise RuntimeError(
                "attested Android engine is missing Flutter release ABIs: "
                + ", ".join(sorted(missing_source_abis))
            )
        unexpected_source_abis = (
            source_abis - FLUTTER_RELEASE_ABIS - ALLOWED_ENGINE_ONLY_ABIS
        )
        if unexpected_source_abis:
            raise RuntimeError(
                "attested Android engine has unrecognized ABIs: "
                + ", ".join(sorted(unexpected_source_abis))
            )

        aab_members = set(aab.namelist())
        bindings: list[dict[str, str]] = []
        for source_name in sources:
            parts = PurePosixPath(source_name).parts
            if len(parts) != 3:
                raise RuntimeError(f"unexpected AAR engine member: {source_name}")
            _, abi, library = parts
            packaged_name = f"base/lib/{abi}/{library}"
            if abi in ALLOWED_ENGINE_ONLY_ABIS:
                if packaged_name in aab_members:
                    raise RuntimeError(
                        "AAB packages an ABI unsupported by Flutter release AOT: "
                        f"{packaged_name}"
                    )
                continue
            if abi not in FLUTTER_RELEASE_ABIS:
                raise RuntimeError(f"unexpected AAR engine ABI: {abi}")
            if packaged_name not in aab_members:
                raise RuntimeError(
                    "AAB is missing an attested Flutter release engine file: "
                    f"{packaged_name}"
                )
            expected = _member_sha256(aar, source_name)
            actual = _member_sha256(aab, packaged_name)
            if actual != expected:
                raise RuntimeError(
                    f"AAB engine differs from attested AAR: {packaged_name}"
                )
            bindings.append({"path": packaged_name, "sha256": actual})
        return {
            "schema": 1,
            "classification": "release-aab-package-only",
            "aab_sha256": _file_sha256(aab_path),
            "aar_sha256": _file_sha256(aar_path),
            "verified_abis": sorted(FLUTTER_RELEASE_ABIS),
            "excluded_engine_only_abis": sorted(
                source_abis & ALLOWED_ENGINE_ONLY_ABIS
            ),
            "engine_files": bindings,
        }
    finally:
        aab.close()
        aar.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--aab", type=Path, required=True)
    parser.add_argument("--aar", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise RuntimeError("binding output must be new")
    report = verify_android_aab_engine(args.aab, args.aar)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
