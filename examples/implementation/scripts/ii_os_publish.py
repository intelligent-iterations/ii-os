#!/usr/bin/env python3
"""Publish what a model container produced and report the run to ii-os.

The container writes its files and `out/result.json` into the run directory.
It ran third-party model code, so nothing it wrote is trusted until checked:

    plan            validate result.json and every file it names: a plain name
                    inside out/, a regular file, a declared content type whose
                    bytes look like that type, under the catalog's size ceiling
    upload          resumable upload of each planned file to the workspace
                    bucket with ifGenerationMatch=0 (never overwrite) and the
                    ii-os-sha256 metadata ii-os verifies
    complete        report status=completed with the uploaded artifacts
    report-failure  report failed/cancelled; claims first only when this run
                    never claimed, and leaves a request another run owns or
                    that is already terminal alone

Objects are named `<request prefix><image|video|audio|data>/<stem>-<run>-<attempt>.<ext>`
unless an artifact names an `objectPath` (one or two plain folders and a file
name) because a documented contract reads it from a fixed place.

Example result.json:

    {"schema_version": 1,
     "artifacts": [{"file": "video.mp4", "contentType": "video/mp4"},
                   {"file": "poster.jpg", "contentType": "image/jpeg",
                    "role": "poster", "posterFor": "video.mp4"}]}
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
from typing import Any, Mapping, Sequence
import urllib.error
import urllib.parse
import urllib.request

from ii_os_connector import ERROR_CODE, Connector, ConnectorError, Opener, RunIdentity
from ii_os_settings import SettingError, connector as connector_settings

MAX_ARTIFACTS = 20
MAX_RESULT_BYTES = 64 * 1024
MAX_JSON_ARTIFACT_BYTES = 1024 * 1024
UPLOAD_TIMEOUT_SECONDS = 3600
ARTIFACT_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}(?:\.[A-Za-z0-9]{1,8})$")
# A runner may name where an artifact goes under the request prefix when a
# documented contract expects a fixed path (classification decisions are read
# from `open-jev/decisions.json`). One or two folders, plain segments.
OBJECT_PATH = re.compile(r"^(?:[a-z0-9][a-z0-9_-]{0,31}/){1,2}[A-Za-z0-9][A-Za-z0-9_-]{0,63}\.[a-z0-9]{1,8}$")
GCS_UPLOAD = "https://storage.googleapis.com/upload/storage/v1/b/{bucket}/o"
# content type: (object folder, accepted extensions, the extension objects get)
OUTPUT_TYPES: dict[str, tuple[str, tuple[str, ...], str]] = {
    "image/png": ("image", ("png",), "png"),
    "image/jpeg": ("image", ("jpg", "jpeg"), "jpg"),
    "image/webp": ("image", ("webp",), "webp"),
    "video/mp4": ("video", ("mp4",), "mp4"),
    "video/webm": ("video", ("webm",), "webm"),
    "audio/wav": ("audio", ("wav",), "wav"),
    "audio/mpeg": ("audio", ("mp3",), "mp3"),
    "audio/flac": ("audio", ("flac",), "flac"),
    "application/json": ("data", ("json",), "json"),
}


@dataclass(frozen=True)
class PlannedArtifact:
    path: Path
    object_name: str
    content_type: str
    size_bytes: int
    sha256: str
    role: str | None = None
    poster_for: str | None = None

    def to_json(self) -> dict[str, Any]:
        return {
            "path": str(self.path),
            "objectName": self.object_name,
            "contentType": self.content_type,
            "sizeBytes": self.size_bytes,
            "sha256": self.sha256,
            "role": self.role,
            "posterFor": self.poster_for,
        }

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "PlannedArtifact":
        return cls(
            path=Path(value["path"]),
            object_name=value["objectName"],
            content_type=value["contentType"],
            size_bytes=int(value["sizeBytes"]),
            sha256=value["sha256"],
            role=value.get("role"),
            poster_for=value.get("posterFor"),
        )


def plan(
    work: Path,
    *,
    object_prefix: str,
    run_id: int,
    run_attempt: int,
    allowed_content_types: Sequence[str],
    max_bytes: int,
) -> list[PlannedArtifact]:
    out = (work / "out").resolve(strict=True)
    entries = _result_entries(out / "result.json")
    seen: dict[str, str] = {}
    planned: list[PlannedArtifact] = []
    for entry in entries:
        name, content_type = entry.get("file"), entry.get("contentType")
        if not isinstance(name, str) or not ARTIFACT_NAME.fullmatch(name):
            raise ValueError("an artifact file name must be a plain name inside out/, like image.png")
        if name in seen:
            raise ValueError(f"result.json names {name} twice")
        if content_type not in allowed_content_types:
            raise ValueError(f"{content_type!s:.40} is not an output this workflow declares")
        if content_type not in OUTPUT_TYPES:
            raise ValueError(f"{content_type} has no upload mapping in this kit")
        folder, extensions, extension = OUTPUT_TYPES[content_type]
        stem, suffix = name.rsplit(".", 1)
        if suffix.lower() not in extensions:
            raise ValueError(f"{name} has an extension that does not match {content_type}")
        path = out / name
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode):
            raise ValueError(f"{name} is not a regular file")
        limit = min(max_bytes, MAX_JSON_ARTIFACT_BYTES) if content_type == "application/json" else max_bytes
        if info.st_size == 0:
            raise ValueError(f"{name} is empty")
        if info.st_size > limit:
            raise ValueError(f"{name} is larger than the {limit} bytes this workflow may publish")
        if not _looks_like(path, content_type):
            raise ValueError(f"{name} does not look like {content_type}")
        object_name = f"{object_prefix}{folder}/{stem}-{run_id}-{run_attempt}.{extension}"
        named = entry.get("objectPath")
        if named is not None:
            if not isinstance(named, str) or not OBJECT_PATH.fullmatch(named) or named.rsplit(".", 1)[1] not in extensions:
                raise ValueError(f"the object path for {name} must be a plain folder/name.{extension} under the request prefix")
            object_name = object_prefix + named
        if object_name in seen.values():
            raise ValueError(f"two artifacts would be stored as the same object ({name})")
        seen[name] = object_name
        planned.append(
            PlannedArtifact(path, object_name, content_type, info.st_size, _sha256(path), entry.get("role"), entry.get("posterFor"))
        )
    return [_with_poster_target(item, seen, planned) for item in planned]


def _result_entries(result: Path) -> list[dict[str, Any]]:
    try:
        info = result.lstat()
    except FileNotFoundError:
        raise ValueError("the model container did not write out/result.json") from None
    if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_RESULT_BYTES:
        raise ValueError("out/result.json must be a regular file under 64 KiB")
    try:
        value = json.loads(result.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ValueError("out/result.json is not JSON") from None
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        raise ValueError("out/result.json must declare schema_version 1")
    artifacts = value.get("artifacts")
    if not isinstance(artifacts, list) or not 1 <= len(artifacts) <= MAX_ARTIFACTS:
        raise ValueError(f"out/result.json must list 1 to {MAX_ARTIFACTS} artifacts")
    if any(not isinstance(item, dict) for item in artifacts):
        raise ValueError("every result.json artifact must be an object")
    return artifacts


def _with_poster_target(item: PlannedArtifact, objects: Mapping[str, str], planned: Sequence[PlannedArtifact]) -> PlannedArtifact:
    if item.role is None and item.poster_for is None:
        return item
    target = objects.get(item.poster_for or "")
    target_item = next((other for other in planned if other.object_name == target), None)
    if (
        item.role != "poster"
        or not item.content_type.startswith("image/")
        or target_item is None
        or target_item is item
        or target_item.role is not None
    ):
        raise ValueError("a poster must be an image naming another, non-poster artifact of this run")
    return PlannedArtifact(item.path, item.object_name, item.content_type, item.size_bytes, item.sha256, "poster", target)


def _looks_like(path: Path, content_type: str) -> bool:
    with path.open("rb") as handle:
        head = handle.read(16)
    if content_type == "image/png":
        return head.startswith(b"\x89PNG\r\n\x1a\n")
    if content_type == "image/jpeg":
        return head.startswith(b"\xff\xd8\xff")
    if content_type == "image/webp":
        return head[:4] == b"RIFF" and head[8:12] == b"WEBP"
    if content_type == "video/mp4":
        return head[4:8] == b"ftyp"
    if content_type == "video/webm":
        return head.startswith(b"\x1a\x45\xdf\xa3")
    if content_type == "audio/wav":
        return head[:4] == b"RIFF" and head[8:12] == b"WAVE"
    if content_type == "audio/mpeg":
        return head.startswith(b"ID3") or (len(head) > 1 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0)
    if content_type == "audio/flac":
        return head.startswith(b"fLaC")
    if content_type == "application/json":
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return False
        return True
    return False


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def upload(artifacts: Sequence[PlannedArtifact], *, bucket: str, access_token: str, opener: Opener | None = None) -> list[dict[str, Any]]:
    if not access_token:
        raise ValueError("GCP_ACCESS_TOKEN is empty; the workload identity step did not run")
    open_url = opener or urllib.request.urlopen
    return [_upload_one(item, bucket, access_token, open_url) for item in artifacts]


def _upload_one(item: PlannedArtifact, bucket: str, token: str, open_url: Opener) -> dict[str, Any]:
    info = item.path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size != item.size_bytes:
        raise ValueError(f"{item.path.name} changed after it was validated")
    query = urllib.parse.urlencode({"uploadType": "resumable", "ifGenerationMatch": "0", "name": item.object_name})
    init = urllib.request.Request(
        GCS_UPLOAD.format(bucket=urllib.parse.quote(bucket, safe="")) + "?" + query,
        data=json.dumps(
            {"name": item.object_name, "contentType": item.content_type, "metadata": {"ii-os-sha256": item.sha256}},
            separators=(",", ":"),
        ).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=UTF-8",
            "X-Upload-Content-Type": item.content_type,
            "X-Upload-Content-Length": str(item.size_bytes),
        },
    )
    with _gcs(open_url, init, item) as response:
        session = response.getheader("Location") or ""
    parsed = urllib.parse.urlparse(session)
    if parsed.scheme != "https" or parsed.hostname != "storage.googleapis.com":
        raise ValueError("the storage service returned an unexpected upload session location")
    with item.path.open("rb") as body:
        put = urllib.request.Request(
            session,
            data=body,
            method="PUT",
            headers={"Content-Type": item.content_type, "Content-Length": str(item.size_bytes)},
        )
        with _gcs(open_url, put, item) as response:
            stored = json.loads(response.read().decode("utf-8") or "{}")
    generation = str(stored.get("generation", ""))
    if stored.get("name") != item.object_name or str(stored.get("size")) != str(item.size_bytes):
        raise ValueError(f"the stored object for {item.path.name} does not match its size or name")
    if not re.fullmatch(r"[1-9][0-9]{0,29}", generation):
        raise ValueError(f"the stored object for {item.path.name} has no generation")
    reported: dict[str, Any] = {
        "path": item.object_name,
        "contentType": item.content_type,
        "sizeBytes": item.size_bytes,
        "sha256": item.sha256,
        "generation": generation,
    }
    if item.role == "poster":
        reported.update(role="poster", posterFor=item.poster_for)
    return reported


class _gcs:
    """Opens one storage request and maps refusals onto messages without URLs."""

    def __init__(self, open_url: Opener, request: urllib.request.Request, item: PlannedArtifact):
        self.open_url, self.request, self.item = open_url, request, item

    def __enter__(self) -> Any:
        try:
            self.response = self.open_url(self.request, timeout=UPLOAD_TIMEOUT_SECONDS)
        except urllib.error.HTTPError as error:
            error.close()
            if error.code == 412:
                raise ValueError(f"{self.item.object_name} already exists; artifacts are never overwritten") from None
            raise ValueError(f"the storage service refused {self.item.path.name} with HTTP {error.code}") from None
        except urllib.error.URLError:
            raise ValueError("the storage service could not be reached") from None
        return self.response.__enter__()

    def __exit__(self, *exc: object) -> None:
        self.response.__exit__(*exc)


def report_failure(client: Connector, identity: RunIdentity, *, status: str, error_code: str) -> str:
    """Report failed/cancelled. Returns reported, already-terminal or not-owned."""
    try:
        client.complete(identity, status=status, error_code=error_code)
        return "reported"
    except ConnectorError as error:
        if error.code == "workflow_run_already_completed":
            return "already-terminal"
        if error.code != "workflow_run_identity_mismatch":
            raise
    try:
        client.claim(identity)
    except ConnectorError as error:
        if error.code in {"workflow_run_already_claimed", "workflow_run_not_claimable"}:
            return "not-owned"
        if error.code != "ghost_payload_consumed":
            raise
    try:
        client.complete(identity, status=status, error_code=error_code)
    except ConnectorError as error:
        if error.code == "workflow_run_already_completed":
            return "already-terminal"
        raise
    return "reported"


def failure_code(work: Path | None, *, default: str, allowed: Sequence[str]) -> str:
    """The runner may name a more specific error code from the allowed list."""
    if work is None or not allowed:
        return default
    failure = work / "out" / "failure.json"
    try:
        if failure.is_symlink() or failure.stat().st_size > 4096:
            return default
        value = json.loads(failure.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return default
    code = value.get("errorCode") if isinstance(value, dict) else None
    return code if isinstance(code, str) and code in allowed else default


def _private_json(path: Path, value: Any) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(value, handle, sort_keys=True)


def _csv(value: str) -> tuple[str, ...]:
    return tuple(item.strip() for item in value.split(",") if item.strip())


def main(argv: Sequence[str], env: Mapping[str, str] | None = None, opener: Opener | None = None) -> int:
    env = os.environ if env is None else env
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    plan_parser = sub.add_parser("plan")
    plan_parser.add_argument("--work-dir", type=Path, required=True)
    plan_parser.add_argument("--object-prefix", required=True)
    plan_parser.add_argument("--allowed-content-types", required=True)
    plan_parser.add_argument("--max-bytes", type=int, required=True)
    upload_parser = sub.add_parser("upload")
    upload_parser.add_argument("--work-dir", type=Path, required=True)
    upload_parser.add_argument("--bucket", required=True)
    complete_parser = sub.add_parser("complete")
    complete_parser.add_argument("--work-dir", type=Path, required=True)
    failure_parser = sub.add_parser("report-failure")
    failure_parser.add_argument("--job-status", required=True)
    failure_parser.add_argument("--error-code", required=True)
    failure_parser.add_argument("--cancelled-error-code", required=True)
    failure_parser.add_argument("--work-dir", type=Path)
    failure_parser.add_argument("--runner-error-codes", default="")
    args = parser.parse_args(list(argv))
    identity = RunIdentity.from_env(env)

    if args.command == "plan":
        planned = plan(
            args.work_dir,
            object_prefix=args.object_prefix,
            run_id=identity.run_id,
            run_attempt=identity.run_attempt,
            allowed_content_types=_csv(args.allowed_content_types),
            max_bytes=args.max_bytes,
        )
        _private_json(args.work_dir / "publish-plan.json", [item.to_json() for item in planned])
        for item in planned:
            print(f"validated {item.path.name}: {item.content_type}, {item.size_bytes} bytes, sha256 {item.sha256}")
        return 0
    if args.command == "upload":
        planned = [PlannedArtifact.from_json(item) for item in json.loads((args.work_dir / "publish-plan.json").read_text())]
        uploaded = upload(planned, bucket=args.bucket, access_token=env.get("GCP_ACCESS_TOKEN", ""), opener=opener)
        _private_json(args.work_dir / "uploaded.json", uploaded)
        print(f"uploaded {len(uploaded)} artifact(s) to the workspace bucket")
        return 0

    url, token = connector_settings(env)
    client = Connector(url, token, opener=opener)
    if args.command == "complete":
        artifacts = json.loads((args.work_dir / "uploaded.json").read_text(encoding="utf-8"))
        client.complete(identity, status="completed", artifacts=artifacts)
        print(f"reported {len(artifacts)} artifact(s) to ii-os")
        return 0

    cancelled = args.job_status == "cancelled"
    code = args.cancelled_error_code if cancelled else failure_code(
        args.work_dir, default=args.error_code, allowed=_csv(args.runner_error_codes)
    )
    if not ERROR_CODE.fullmatch(code):
        raise ValueError("the error code is not a stable ii-os error code")
    outcome = report_failure(client, identity, status="cancelled" if cancelled else "failed", error_code=code)
    print(f"ii-os failure report: {outcome} ({code})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except SettingError as error:
        print(f"::error title=ii-os setting::{error}")
        raise SystemExit(2) from None
    except ConnectorError as error:
        print(f"::error title=ii-os rejected the report::{error}")
        raise SystemExit(1) from None
    except (OSError, ValueError, KeyError) as error:
        print(f"::error title=ii-os publish::{error}")
        raise SystemExit(1) from None
