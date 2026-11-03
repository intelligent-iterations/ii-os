#!/usr/bin/env python3
"""Fail-closed inspection for Android/iOS FFmpeg engine archives."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import shlex
import stat
import struct
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath
from typing import Any

from mobile_binary_closure import (
    BinaryClosureError,
    elf_dynamic_closure,
    macho_dynamic_closure,
)

MAX_ENTRIES = 20_000
MAX_MEMBER_BYTES = 512 * 1024 * 1024
CONFIG_RE = re.compile(rb"--cross-prefix=[^\x00\r\n]{20,20000}")
VERSION_RE = re.compile(rb"\bn[0-9]+\.[0-9]+(?:\.[0-9]+)?\x00")
ANDROID_ELF = {
    "arm64-v8a": (2, 183),
    "armeabi-v7a": (1, 40),
    "x86": (1, 3),
    "x86_64": (2, 62),
}
MACHO_ARCH = {
    (0x0100000C, 0): "arm64",
    (0x0100000C, 2): "arm64e",
    (0x01000007, 3): "x86_64",
}


class VerificationError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _checked_zip(path: Path) -> zipfile.ZipFile:
    try:
        archive = zipfile.ZipFile(path)
    except (OSError, zipfile.BadZipFile) as error:
        raise VerificationError(f"invalid zip archive {path}: {error}") from error
    infos = archive.infolist()
    if not infos or len(infos) > MAX_ENTRIES:
        archive.close()
        raise VerificationError(f"unsafe entry count in {path}: {len(infos)}")
    seen: set[str] = set()
    for info in infos:
        name = info.filename
        pure = PurePosixPath(name)
        normalized = str(pure)
        mode = info.external_attr >> 16
        unsafe = (
            not name
            or "\\" in name
            or pure.is_absolute()
            or ".." in pure.parts
            or normalized in seen
            or info.file_size > MAX_MEMBER_BYTES
            or stat.S_ISLNK(mode)
        )
        if unsafe:
            archive.close()
            raise VerificationError(f"unsafe zip member in {path}: {name!r}")
        seen.add(normalized)
    return archive


def _member_bytes(archive: zipfile.ZipFile, name: str) -> bytes:
    info = archive.getinfo(name)
    if info.file_size > MAX_MEMBER_BYTES:
        raise VerificationError(f"archive member exceeds limit: {name}")
    with archive.open(info) as source:
        data = source.read(MAX_MEMBER_BYTES + 1)
    if len(data) != info.file_size:
        raise VerificationError(f"incomplete or oversized archive member: {name}")
    return data


def _configs(data: bytes, member: str) -> list[list[str]]:
    matches = CONFIG_RE.findall(data)
    if not matches:
        raise VerificationError(f"no embedded FFmpeg configure line in {member}")
    parsed = []
    for raw in matches:
        try:
            parsed.append(shlex.split(raw.decode("utf-8")))
        except (UnicodeDecodeError, ValueError) as error:
            raise VerificationError(f"malformed configure line in {member}") from error
    return parsed


def _flag_present(tokens: list[str], flag: str) -> bool:
    return any(token == flag or token.startswith(f"{flag}=") for token in tokens)


def _check_config(
    tokens: list[str], lock: dict[str, Any], platform: str, release: bool
) -> None:
    target = "--target-os=android" if platform == "android" else "--target-os=darwin"
    if target not in tokens:
        raise VerificationError(f"missing target flag: {target}")
    for flag in lock["release_profile"]["forbidden_flags"]:
        if _flag_present(tokens, flag):
            raise VerificationError(f"forbidden engine flag present: {flag}")
    if release:
        for flag in lock["release_profile"]["required_flags"]:
            if not _flag_present(tokens, flag):
                raise VerificationError(f"release engine flag missing: {flag}")


def _versions(data: bytes) -> set[str]:
    return {
        raw[:-1].decode("ascii")
        for raw in VERSION_RE.findall(data)
        if raw.startswith(b"n")
    }


def _check_elf(data: bytes, member: str, abi: str) -> None:
    if len(data) < 20 or data[:4] != b"\x7fELF" or data[5] != 1:
        raise VerificationError(f"invalid little-endian ELF identity: {member}")
    expected_class, expected_machine = ANDROID_ELF[abi]
    elf_class = data[4]
    elf_type, machine = struct.unpack_from("<HH", data, 16)
    if (
        elf_class != expected_class
        or elf_type != 3
        or machine != expected_machine
    ):
        raise VerificationError(
            f"Android ELF target mismatch for {member}: "
            f"class={elf_class}, type={elf_type}, machine={machine}"
        )


def _macho_architectures(data: bytes, member: str) -> set[str]:
    identities: list[tuple[int, int]] = []
    if len(data) >= 12 and data[:4] == b"\xcf\xfa\xed\xfe":
        cpu_type, cpu_subtype = struct.unpack_from("<II", data, 4)
        identities.append((cpu_type, cpu_subtype & 0x00FFFFFF))
    elif len(data) >= 8 and data[:4] in {b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}:
        count = struct.unpack_from(">I", data, 4)[0]
        entry_size = 20 if data[:4] == b"\xca\xfe\xba\xbe" else 32
        if count == 0 or count > 8 or len(data) < 8 + count * entry_size:
            raise VerificationError(f"invalid Mach-O slice table: {member}")
        for index in range(count):
            offset = 8 + index * entry_size
            cpu_type, cpu_subtype = struct.unpack_from(">II", data, offset)
            if entry_size == 20:
                slice_offset, size = struct.unpack_from(">II", data, offset + 8)
            else:
                slice_offset, size = struct.unpack_from(">QQ", data, offset + 8)
            if size == 0 or slice_offset + size > len(data):
                raise VerificationError(f"out-of-bounds Mach-O slice: {member}")
            identities.append((cpu_type, cpu_subtype & 0x00FFFFFF))
    else:
        raise VerificationError(f"invalid 64-bit Mach-O identity: {member}")
    try:
        architectures = {MACHO_ARCH[value] for value in identities}
    except KeyError as error:
        raise VerificationError(
            f"unsupported Mach-O architecture in {member}: {error.args[0]}"
        ) from error
    if len(architectures) != len(identities):
        raise VerificationError(f"duplicate Mach-O architecture in {member}")
    return architectures


def _ios_metadata(
    archive: zipfile.ZipFile, library: str, lock: dict[str, Any]
) -> dict[str, set[str]]:
    root = f"{library}.xcframework"
    info_name = f"{root}/Info.plist"
    if info_name not in archive.namelist():
        raise VerificationError(f"iOS archive is missing {info_name}")
    try:
        info = plistlib.loads(_member_bytes(archive, info_name))
    except (plistlib.InvalidFileException, ValueError) as error:
        raise VerificationError(f"malformed XCFramework metadata: {library}") from error
    values = info.get("AvailableLibraries") if isinstance(info, dict) else None
    if not isinstance(values, list):
        raise VerificationError(f"XCFramework has no AvailableLibraries: {library}")
    actual: dict[str, set[str]] = {}
    expected = {
        value["identifier"]: value
        for value in lock["release_profile"]["ios_slices"]
    }
    for value in values:
        if not isinstance(value, dict):
            raise VerificationError(f"invalid XCFramework slice record: {library}")
        identifier = value.get("LibraryIdentifier")
        if not isinstance(identifier, str) or identifier in actual:
            raise VerificationError(f"duplicate XCFramework slice: {library}")
        specification = expected.get(identifier)
        architectures = value.get("SupportedArchitectures")
        variant = value.get("SupportedPlatformVariant")
        if (
            specification is None
            or value.get("LibraryPath") != f"{library}.framework"
            or value.get("SupportedPlatform") != specification["platform"]
            or variant != specification.get("variant")
            or not isinstance(architectures, list)
            or set(architectures) != set(specification["architectures"])
            or len(architectures) != len(set(architectures))
        ):
            raise VerificationError(
                f"XCFramework slice metadata mismatch: {library}/{identifier}"
            )
        actual[identifier] = set(architectures)
    if set(actual) != set(expected):
        raise VerificationError(f"XCFramework slice set mismatch: {library}")
    return actual


def verify_android(
    path: Path, lock: dict[str, Any], release: bool, expected_sha: str | None
) -> dict[str, Any]:
    actual_sha = _sha256(path)
    if expected_sha and actual_sha != expected_sha:
        raise VerificationError(f"Android AAR checksum mismatch: {actual_sha}")
    archive = _checked_zip(path)
    try:
        names = set(archive.namelist())
        manifest_name = "AndroidManifest.xml"
        if manifest_name not in names:
            raise VerificationError("Android AAR contains no manifest")
        try:
            manifest = ET.fromstring(_member_bytes(archive, manifest_name))
        except ET.ParseError as error:
            raise VerificationError("Android AAR manifest is malformed") from error
        android_package = lock["release_profile"]["android_package"]
        if (
            manifest.tag != "manifest"
            or manifest.attrib.get("package") != android_package
        ):
            raise VerificationError(
                "Android AAR manifest package mismatch: "
                f"{manifest.attrib.get('package')!r}"
            )
        expected_abis = lock["release_profile"]["android_abis"]
        config_report: dict[str, list[list[str]]] = {}
        closure_report: dict[str, dict[str, Any]] = {}
        versions: set[str] = set()
        for abi in expected_abis:
            expected_libraries = set(
                lock["release_profile"]["android_libraries"][abi]
            )
            prefix = f"jni/{abi}/"
            members = {
                name
                for name in names
                if name.startswith(prefix) and not name.endswith("/")
            }
            expected_members = {f"{prefix}{name}" for name in expected_libraries}
            if members != expected_members:
                raise VerificationError(
                    f"Android JNI library set mismatch for {abi}: "
                    f"{sorted(PurePosixPath(value).name for value in members)}"
                )
            abi_configs: list[list[str]] = []
            abi_closure: dict[str, Any] = {}
            allowed_dependencies = expected_libraries | set(
                lock["release_profile"]["android_system_libraries"]
            )
            for member in sorted(members):
                data = _member_bytes(archive, member)
                _check_elf(data, member, abi)
                closure = elf_dynamic_closure(data, member)
                library_name = PurePosixPath(member).name
                loader_dependencies = set(closure["needed"]) | set(
                    closure["filters"]
                ) | set(closure["auxiliary"])
                if closure["soname"] != library_name or not loader_dependencies.issubset(
                    allowed_dependencies
                ):
                    raise VerificationError(
                        f"Android dynamic closure mismatch in {member}: {closure}"
                    )
                abi_closure[library_name] = closure
                if PurePosixPath(member).name.startswith("libavutil"):
                    member_versions = _versions(data)
                    if lock["engine_version"] not in member_versions:
                        raise VerificationError(
                            f"Android engine version missing in {member}"
                        )
                    versions.update(member_versions)
                    parsed = _configs(data, member)
                    for tokens in parsed:
                        _check_config(tokens, lock, "android", release)
                        if "--enable-jni" not in tokens:
                            raise VerificationError(
                                f"Android JNI flag missing in {member}"
                            )
                    abi_configs.extend(parsed)
            config_report[abi] = abi_configs
            closure_report[abi] = abi_closure
        present_abis = {
            PurePosixPath(name).parts[1]
            for name in names
            if name.startswith("jni/") and len(PurePosixPath(name).parts) > 2
        }
        if present_abis != set(expected_abis):
            raise VerificationError(f"unexpected Android ABI set: {sorted(present_abis)}")
        expected_version = lock["engine_version"]
        if expected_version not in versions:
            raise VerificationError(
                f"Android engine version {expected_version} not embedded: {sorted(versions)}"
            )
        licenses = sorted(
            name
            for name in names
            if PurePosixPath(name).name.lower().startswith(("license", "copying", "notice"))
        )
        if release and not licenses:
            raise VerificationError("release Android AAR contains no license payload")
        embedded_ledger = "res/raw/ii_ffmpeg_source_ledger.json"
        if embedded_ledger not in names:
            raise VerificationError("release Android AAR contains no source ledger")
        return {
            "platform": "android",
            "archive_sha256": actual_sha,
            "engine_version": expected_version,
            "android_package": android_package,
            "abis": expected_abis,
            "configure": config_report,
            "dynamic_closure": closure_report,
            "license_members": licenses,
            "embedded_source_ledger_sha256": hashlib.sha256(
                _member_bytes(archive, embedded_ledger)
            ).hexdigest(),
            "release_profile": release,
        }
    finally:
        archive.close()


def verify_ios(
    paths: dict[str, Path], lock: dict[str, Any], release: bool
) -> dict[str, Any]:
    expected_names = set(lock["release_profile"]["ios_libraries"])
    if set(paths) != expected_names:
        raise VerificationError(f"iOS archive set mismatch: {sorted(paths)}")
    locked = lock["consumed_artifacts"]["ios_full_8_1_2"]
    report: dict[str, Any] = {}
    configs: dict[str, list[list[str]]] = {}
    versions: set[str] = set()
    license_count = 0
    internal_dependencies = {
        f"@rpath/{name}.framework/{name}" for name in expected_names
    }
    allowed_dependencies = internal_dependencies | set(
        lock["release_profile"]["ios_system_libraries"]
    )
    minimum_version = _version_tuple(lock["toolchains"]["ios_minimum_version"])
    for library in sorted(paths):
        path = paths[library]
        actual_sha = _sha256(path)
        if not release and actual_sha != locked[library]:
            raise VerificationError(f"iOS {library} checksum mismatch: {actual_sha}")
        archive = _checked_zip(path)
        try:
            names = archive.namelist()
            slices = _ios_metadata(archive, library, lock)
            licenses = [
                name
                for name in names
                if PurePosixPath(name).name.lower().startswith(
                    ("license", "copying", "notice")
                )
            ]
            license_count += len(licenses)
            binary_members = {
                f"{library}.xcframework/{identifier}/"
                f"{library}.framework/{library}"
                for identifier in slices
            }
            if not binary_members.issubset(names):
                raise VerificationError(
                    f"iOS archive binary set is incomplete for {library}"
                )
            for member in sorted(binary_members):
                data = _member_bytes(archive, member)
                identifier = PurePosixPath(member).parts[1]
                actual_architectures = _macho_architectures(data, member)
                if actual_architectures != slices[identifier]:
                    raise VerificationError(
                        f"Mach-O slice mismatch in {member}: "
                        f"{sorted(actual_architectures)}"
                    )
                closure = macho_dynamic_closure(data, member)
                if set(closure) != actual_architectures:
                    raise VerificationError(
                        f"Mach-O dynamic architecture mismatch in {member}"
                    )
                specification = next(
                    value
                    for value in lock["release_profile"]["ios_slices"]
                    if value["identifier"] == identifier
                )
                expected_platform = (
                    "ios-simulator" if specification.get("variant") else "ios"
                )
                for architecture, value in closure.items():
                    if (
                        value["platform"] != expected_platform
                        or not set(value["dependencies"]).issubset(
                            allowed_dependencies
                        )
                        or (
                            release
                            and _version_tuple(value["minimum_version"])
                            != minimum_version
                        )
                    ):
                        raise VerificationError(
                            f"iOS dynamic closure mismatch in {member}/"
                            f"{architecture}: {value}"
                        )
                if library in {"libavutil", "ffmpegkit"}:
                    member_versions = _versions(data)
                    versions.update(member_versions)
                    if library == "libavutil":
                        if lock["engine_version"] not in member_versions:
                            raise VerificationError(
                                f"iOS engine version missing in {member}"
                            )
                        parsed = _configs(data, member)
                        for tokens in parsed:
                            _check_config(tokens, lock, "ios", release)
                        configs[member] = parsed
            report[library] = {
                "sha256": actual_sha,
                "binary_members": sorted(binary_members),
                "slices": {
                    key: sorted(value) for key, value in sorted(slices.items())
                },
                "license_members": sorted(licenses),
                "dynamic_closure": {
                    member: macho_dynamic_closure(
                        _member_bytes(archive, member), member
                    )
                    for member in sorted(binary_members)
                },
            }
        finally:
            archive.close()
    expected_version = lock["engine_version"]
    if expected_version not in versions:
        raise VerificationError(
            f"iOS engine version {expected_version} not embedded: {sorted(versions)}"
        )
    if release and license_count == 0:
        raise VerificationError("release iOS archives contain no license payload")
    return {
        "platform": "ios",
        "engine_version": expected_version,
        "archives": report,
        "configure": configs,
        "release_profile": release,
    }


def _version_tuple(value: str) -> tuple[int, int, int]:
    parts = value.split(".")
    if not 1 <= len(parts) <= 3 or any(not part.isdigit() for part in parts):
        raise VerificationError(f"invalid deployment version: {value}")
    return tuple([*(int(part) for part in parts), 0, 0][:3])


def _parse_ios(values: list[str]) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for value in values:
        name, separator, raw_path = value.partition("=")
        if not separator or not name or name in result:
            raise VerificationError(f"invalid or duplicate --archive value: {value}")
        result[name] = Path(raw_path).resolve(strict=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--lock",
        type=Path,
        default=Path(__file__).with_name("mobile_engine_lock.json"),
    )
    subparsers = parser.add_subparsers(dest="platform", required=True)
    android = subparsers.add_parser("android")
    android.add_argument("--archive", type=Path, required=True)
    android.add_argument("--release", action="store_true")
    android.add_argument("--expected-sha256")
    ios = subparsers.add_parser("ios")
    ios.add_argument("--archive", action="append", default=[], required=True)
    ios.add_argument("--release", action="store_true")
    args = parser.parse_args()
    try:
        lock = json.loads(args.lock.read_text(encoding="utf-8"))
        if lock.get("schema") != 1:
            raise VerificationError("unsupported mobile engine lock schema")
        if args.platform == "android":
            path = args.archive.resolve(strict=True)
            expected = args.expected_sha256
            if not expected and not args.release:
                expected = lock["consumed_artifacts"]["android_full_2_2_1"]["sha256"]
            result = verify_android(path, lock, args.release, expected)
        else:
            result = verify_ios(_parse_ios(args.archive), lock, args.release)
        json.dump(result, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0
    except (
        BinaryClosureError,
        OSError,
        KeyError,
        TypeError,
        ValueError,
        VerificationError,
    ) as error:
        print(f"mobile engine verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
