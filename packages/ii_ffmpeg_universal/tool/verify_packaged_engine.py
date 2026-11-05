#!/usr/bin/env python3
"""Bind one built application to the exact reviewed engine bytes it contains."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

from application_artifact_manifest import checked_files
from macho_engine_binding import require_packaged_macho_matches
from package_security_evidence import android_security, apple_security


MAX_MEMBER_BYTES = 512 * 1024 * 1024
MAX_MEMBERS = 30_000


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load_object(path: Path, description: str) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"{description} is not an object")
    return value


def checked_archive(path: Path) -> zipfile.ZipFile:
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"Archive is missing or linked: {path}")
    archive = zipfile.ZipFile(path)
    if len(archive.infolist()) > MAX_MEMBERS:
        archive.close()
        raise RuntimeError(f"Archive member count exceeds limit: {path}")
    for item in archive.infolist():
        member = PurePosixPath(item.filename)
        if (
            member.is_absolute()
            or ".." in member.parts
            or "\\" in item.filename
            or item.file_size > MAX_MEMBER_BYTES
        ):
            archive.close()
            raise RuntimeError(f"Archive has an unsafe member: {item.filename}")
    return archive


def member_bytes(archive: zipfile.ZipFile, name: str) -> bytes:
    info = archive.getinfo(name)
    if info.is_dir() or info.file_size > MAX_MEMBER_BYTES:
        raise RuntimeError(f"Archive member is not a bounded file: {name}")
    with archive.open(info) as source:
        value = source.read(MAX_MEMBER_BYTES + 1)
    if len(value) != info.file_size or len(value) > MAX_MEMBER_BYTES:
        raise RuntimeError(f"Archive member changed or exceeded its limit: {name}")
    return value


def regular_files(root: Path) -> list[Path]:
    values = [path for path in checked_files(root) if not path.is_symlink()]
    if len(values) > MAX_MEMBERS:
        raise RuntimeError("Application file count exceeds limit")
    return values


def unique_suffix(files: list[Path], suffix: str) -> Path:
    matches = [path for path in files if path.as_posix().endswith(suffix)]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one packaged file ending {suffix}: {matches}")
    return matches[0]


def verify_android(application: Path, engine: Path) -> dict[str, Any]:
    apk = checked_archive(application)
    aar = checked_archive(engine)
    try:
        expected = sorted(
            name for name in aar.namelist() if name.startswith("jni/") and name.endswith(".so")
        )
        if not expected:
            raise RuntimeError("Attested Android engine contains no JNI libraries")
        bindings = []
        for source_name in expected:
            _, abi, library = PurePosixPath(source_name).parts
            packaged_name = f"lib/{abi}/{library}"
            source_digest = digest_bytes(member_bytes(aar, source_name))
            packaged_digest = digest_bytes(member_bytes(apk, packaged_name))
            if packaged_digest != source_digest:
                raise RuntimeError(f"APK engine differs from attested AAR: {packaged_name}")
            bindings.append({"path": packaged_name, "sha256": packaged_digest})
    finally:
        apk.close()
        aar.close()
    return {
        "classification": "release-mode-debug-signed-package-only",
        "engine_files": bindings,
        **android_security(application),
    }


def _artifact_name(value: object) -> str:
    if (not isinstance(value, str) or value in {".", ".."}
            or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,127}", value) is None):
        raise RuntimeError("Engine artifact name is malformed")
    return value


def _artifact_digest(value: object) -> str:
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise RuntimeError("Engine artifact digest is malformed")
    return value


def expected_engine_artifacts(attestation: Path) -> dict[str, str]:
    value = load_object(attestation, "Engine attestation")
    artifacts = value.get("artifacts")
    if value.get("schema") != 1 or not isinstance(artifacts, list) or not artifacts:
        raise RuntimeError("Engine attestation has no artifact set")
    result: dict[str, str] = {}
    for item in artifacts:
        if not isinstance(item, dict) or set(item) != {"path", "sha256"}:
            raise RuntimeError("Engine attestation artifact is malformed")
        name = _artifact_name(item["path"])
        digest = _artifact_digest(item["sha256"])
        if name in result:
            raise RuntimeError("Engine attestation artifacts are duplicated")
        result[name] = digest
    if set(result) != {"ffmpeg.js", "ffmpeg-core.js", "ffmpeg-core.wasm"}:
        raise RuntimeError("Browser engine artifact set is incomplete or unexpected")
    return result


def verify_directory_assets(
    application: Path,
    expected: dict[str, str],
    suffix_prefix: str,
    classification: str,
) -> dict[str, Any]:
    if not expected:
        raise RuntimeError("Packaged engine proof requires a nonempty artifact set")
    for name, digest in expected.items():
        _artifact_name(name)
        _artifact_digest(digest)
    files = regular_files(application)
    bindings = []
    for name, expected_digest in sorted(expected.items()):
        packaged = unique_suffix(files, f"{suffix_prefix}{name}")
        actual = hashlib.sha256(packaged.read_bytes()).hexdigest()
        if actual != expected_digest:
            raise RuntimeError(f"Packaged engine differs from attestation: {packaged}")
        bindings.append(
            {"path": packaged.relative_to(application).as_posix(), "sha256": actual}
        )
    return {"classification": classification, "engine_files": bindings}


def verify_desktop(application: Path, attestation: Path, label: str) -> dict[str, Any]:
    value = load_object(attestation, "Desktop engine attestation")
    artifacts = value.get("artifacts")
    if (label not in {"linux", "macos"} or value.get("schema") != 1
            or value.get("platform") != label or not isinstance(artifacts, list)
            or not 2 <= len(artifacts) <= 512):
        raise RuntimeError("Desktop engine attestation has no closure")
    expected: dict[str, str] = {}
    roles: list[str] = []
    for item in artifacts:
        if not isinstance(item, dict) or set(item) != {
            "name", "role", "architecture", "sha256"
        }:
            raise RuntimeError("Desktop engine artifact record is malformed")
        name = _artifact_name(item["name"])
        digest = _artifact_digest(item["sha256"])
        role = item["role"]
        if (name.lower() in {key.lower() for key in expected}
                or role not in {"ffmpeg", "ffprobe", "library"}
                or item["architecture"] not in {"arm64", "x86_64"}
                or item["architecture"] != value.get("architecture")
                or (role in {"ffmpeg", "ffprobe"} and name != role)):
            raise RuntimeError("Desktop engine artifact identity is invalid")
        expected[name] = digest
        roles.append(role)
    if roles.count("ffmpeg") != 1 or roles.count("ffprobe") != 1:
        raise RuntimeError("Desktop engine requires exactly one ffmpeg and ffprobe")
    result = verify_directory_assets(
        application,
        expected,
        "/assets/desktop_engine/",
        "release-package-only-attested-engine",
    )
    if label == "macos":
        result.update(apple_security(application, label))
    return result


def ios_variant(label: str) -> str:
    return "ios-arm64_x86_64-simulator" if label == "ios-simulator" else "ios-arm64_arm64e"


def verify_ios(application: Path, archives: list[str], label: str) -> dict[str, Any]:
    if label not in {"ios-simulator", "ios-device-compile"}:
        raise RuntimeError("Unsupported iOS application proof label")
    lock = load_object(Path(__file__).with_name("mobile_engine_lock.json"), "Mobile engine lock")
    required = lock["release_profile"]["ios_libraries"]
    bindings_by_library: dict[str, Path] = {}
    for binding in archives:
        library, separator, raw_path = binding.partition("=")
        if (not separator or not raw_path or library not in required
                or library in bindings_by_library):
            raise RuntimeError("Invalid or duplicate iOS engine archive binding")
        bindings_by_library[library] = Path(raw_path)
    if set(bindings_by_library) != set(required):
        raise RuntimeError("iOS engine archive set is incomplete")
    files = regular_files(application)
    variant = ios_variant(label)
    bindings = []
    for library, archive_path in sorted(bindings_by_library.items()):
        archive = checked_archive(archive_path)
        source_name = f"{library}.xcframework/{variant}/{library}.framework/{library}"
        try:
            source = member_bytes(archive, source_name)
        finally:
            archive.close()
        packaged = unique_suffix(files, f"/Frameworks/{library}.framework/{library}")
        packaged_bytes = packaged.read_bytes()
        require_packaged_macho_matches(source, packaged_bytes, library)
        actual = hashlib.sha256(packaged_bytes).hexdigest()
        bindings.append({"path": packaged.relative_to(application).as_posix(), "sha256": actual})
    if label == "ios-simulator":
        classification = "simulator-acceptance"
    else:
        classification = "unsigned-device-compile-only"
    return {
        "classification": classification,
        "engine_files": bindings,
        **apple_security(application, label),
    }


def write_report(label: str, result: dict[str, Any], output: Path) -> None:
    report = {"schema": 1, "label": label, **result}
    if output.exists() or output.is_symlink():
        raise RuntimeError("Packaged-engine report output must be new")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=("android", "ios", "desktop", "web"))
    parser.add_argument("--label", required=True)
    parser.add_argument("--application", type=Path, required=True)
    parser.add_argument("--engine", type=Path)
    parser.add_argument("--attestation", type=Path)
    parser.add_argument("--archive", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.platform == "android":
        if args.engine is None:
            raise RuntimeError("Android verification requires --engine")
        result = verify_android(args.application, args.engine)
    elif args.platform == "ios":
        result = verify_ios(args.application, args.archive, args.label)
    elif args.platform == "desktop":
        if args.attestation is None:
            raise RuntimeError("Desktop verification requires --attestation")
        result = verify_desktop(args.application, args.attestation, args.label)
    else:
        if args.attestation is None:
            raise RuntimeError("Web verification requires --attestation")
        result = verify_directory_assets(
            args.application,
            expected_engine_artifacts(args.attestation),
            "/ffmpeg/",
            "production-browser-build",
        )
    write_report(args.label, result, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
