#!/usr/bin/env python3
"""Validate and bind the immutable, prebuilt Android engine a release consumes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Any


SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
MAX_JSON_BYTES = 8 * 1024 * 1024
MAX_TEXT_BYTES = 32 * 1024 * 1024
MAX_AAR_BYTES = 2 * 1024 * 1024 * 1024


def _regular(path: Path, maximum: int) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise RuntimeError(f"required baked engine file is unavailable: {path}") from error
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_size <= 0:
        raise RuntimeError(f"required baked engine path is not a regular file: {path}")
    if metadata.st_size > maximum:
        raise RuntimeError(f"required baked engine file exceeds its limit: {path}")
    return path


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json(path: Path, *, require_schema: bool = True) -> dict[str, Any]:
    _regular(path, MAX_JSON_BYTES)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"baked engine JSON is invalid: {path}") from error
    if not isinstance(value, dict) or (require_schema and value.get("schema") != 1):
        raise RuntimeError(f"baked engine JSON has an unsupported schema: {path}")
    return value


def _require_digest(value: object, label: str) -> str:
    if not isinstance(value, str) or SHA256.fullmatch(value) is None:
        raise RuntimeError(f"{label} is not a SHA-256 digest")
    return value


def stage_engine(
    engine_root: Path,
    source_root: Path,
    expected_source_sha: str,
    expected_aar_sha256: str,
    output: Path,
) -> dict[str, Any]:
    engine_root = Path(engine_root)
    source_root = Path(source_root)
    output = Path(output)
    if COMMIT.fullmatch(expected_source_sha) is None:
        raise RuntimeError("expected source revision is not a full commit SHA")
    _require_digest(expected_aar_sha256, "expected AAR checksum")

    revision = _regular(engine_root / "source-revision", 256).read_text(
        encoding="utf-8"
    ).strip()
    if revision != expected_source_sha:
        raise RuntimeError(
            f"baked engine source revision mismatch: expected {expected_source_sha}, "
            f"got {revision}"
        )

    artifacts = engine_root / "artifacts"
    aar = _regular(artifacts / "ii-ffmpeg-mobile-android.aar", MAX_AAR_BYTES)
    attestation_path = artifacts / "build-attestation.json"
    ledger_path = artifacts / "source-ledger.json"
    notices_path = _regular(artifacts / "THIRD_PARTY_NOTICES.txt", MAX_TEXT_BYTES)
    verification_path = artifacts / "verification.json"
    attestation = _json(attestation_path)
    if attestation.get("platform") != "android":
        raise RuntimeError("baked engine attestation is not for Android")

    aar_sha256 = _sha256(aar)
    if aar_sha256 != expected_aar_sha256:
        raise RuntimeError(
            f"baked engine AAR checksum mismatch: expected {expected_aar_sha256}, "
            f"got {aar_sha256}"
        )
    artifacts_list = attestation.get("artifacts")
    matches = [
        value
        for value in artifacts_list if isinstance(value, dict)
        and value.get("path") == aar.name
    ] if isinstance(artifacts_list, list) else []
    if len(matches) != 1 or matches[0].get("sha256") != aar_sha256:
        raise RuntimeError("baked engine AAR checksum is not bound by its attestation")

    evidence = (
        (ledger_path, "source_ledger_sha256", "source ledger"),
        (notices_path, "notices_sha256", "notices"),
        (verification_path, "verification_sha256", "verification report"),
    )
    for path, field, label in evidence:
        expected = _require_digest(attestation.get(field), f"attested {label} checksum")
        if _sha256(path) != expected:
            raise RuntimeError(f"baked engine {label} differs from its attestation")

    ledger = _json(ledger_path)
    _json(verification_path, require_schema=False)

    lock = _regular(source_root / "tool/mobile_engine_lock.json", MAX_JSON_BYTES)
    builder = _regular(source_root / "tool/build_mobile_engine.py", MAX_TEXT_BYTES)
    verifier = _regular(source_root / "tool/verify_mobile_engine.py", MAX_TEXT_BYTES)
    if ledger.get("platform") not in (None, "android"):
        raise RuntimeError("baked engine source ledger is not for Android")
    if ledger.get("lock_sha256") != _sha256(lock):
        raise RuntimeError("baked engine source ledger does not match the pinned lock")
    if ledger.get("builder_sha256") != _sha256(builder):
        raise RuntimeError("baked engine source ledger does not match the pinned builder")

    command = [
        "python3",
        str(verifier),
        "--lock",
        str(lock),
        "android",
        "--archive",
        str(aar),
        "--release",
        "--expected-sha256",
        aar_sha256,
    ]
    subprocess.run(command, check=True)

    report: dict[str, Any] = {
        "schema": 1,
        "source_sha": expected_source_sha,
        "aar_path": str(aar),
        "aar_sha256": aar_sha256,
        "attestation_sha256": _sha256(attestation_path),
        "source_ledger_sha256": _sha256(ledger_path),
        "notices_sha256": _sha256(notices_path),
        "verification_sha256": _sha256(verification_path),
    }
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if output.exists() or output.is_symlink():
        raise RuntimeError(f"binding output path is already occupied: {output}")
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    try:
        with temporary.open("x", encoding="utf-8") as destination:
            json.dump(report, destination, indent=2, sort_keys=True)
            destination.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine-root", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--expected-aar-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = stage_engine(
            args.engine_root,
            args.source,
            args.source_sha,
            args.expected_aar_sha256,
            args.output,
        )
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"baked Android engine staging failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
