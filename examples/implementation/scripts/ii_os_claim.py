#!/usr/bin/env python3
"""Claim one ii-os request and stage its inputs in a run-owned directory.

ii-os dispatches a generation workflow with only an opaque `ii_request_id`.
The workflow proves its exact run to ii-os (the claim) and receives the
validated inputs, the workspace upload contract and short-lived signed read
URLs for any source assets. This script:

1. claims the request with `II_OS_TOKEN`;
2. creates `${RUNNER_TEMP}/ii-os-run-<run id>-<attempt>/` (mode 0700) with an
   ownership marker naming this request and run attempt;
3. writes `in/inputs.json`, downloads each source asset in ordinal order to
   `in/sources/NN.<ext>` and records `in/sources.json` (no URLs);
4. creates the empty `out/` folder the model container writes into.

The model container later mounts `in/` read-only and `out/` read-write, with
no network. `cleanup` removes the directory only after re-checking its marker.

    python3 scripts/ii_os_claim.py claim --max-sources 3 --source-kinds image
    python3 scripts/ii_os_claim.py cleanup
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
from typing import Any, Mapping, Sequence
import urllib.error
import urllib.parse
import urllib.request

from ii_os_connector import Connector, ConnectorError, Opener, RunIdentity
from ii_os_settings import SettingError, connector as connector_settings

MARKER = ".ii-os-run-owner.json"
MAX_SOURCES = 12
CHUNK = 1024 * 1024
DOWNLOAD_TIMEOUT_SECONDS = 900
SOURCE_TYPES: dict[str, tuple[str, str, int]] = {
    # content type: (kind, extension, largest accepted size in bytes)
    "image/jpeg": ("image", "jpg", 50 * 1024**2),
    "image/png": ("image", "png", 50 * 1024**2),
    "image/webp": ("image", "webp", 50 * 1024**2),
    "video/mp4": ("video", "mp4", 2 * 1024**3),
    "video/webm": ("video", "webm", 2 * 1024**3),
    "video/quicktime": ("video", "mov", 2 * 1024**3),
    "audio/wav": ("audio", "wav", 512 * 1024**2),
    "audio/x-wav": ("audio", "wav", 512 * 1024**2),
    "audio/mpeg": ("audio", "mp3", 512 * 1024**2),
    "audio/mp4": ("audio", "m4a", 512 * 1024**2),
    "audio/aac": ("audio", "aac", 512 * 1024**2),
    "audio/flac": ("audio", "flac", 512 * 1024**2),
}
SOURCE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$")
SOURCE_ROLE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
BUCKET = re.compile(r"^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$")
WORKLOAD_PROVIDER = re.compile(
    r"^projects/[0-9]{1,20}/locations/global/workloadIdentityPools/[a-z0-9-]{4,32}/providers/[a-z0-9-]{4,32}$"
)
SERVICE_ACCOUNT = re.compile(r"^[a-z0-9-]{6,30}@[a-z0-9-]{4,30}\.iam\.gserviceaccount\.com$")
SUPPORTED_UPLOAD_PROVIDERS = ("gcp_wif",)


@dataclass(frozen=True)
class UploadContract:
    provider: str
    bucket: str
    object_prefix: str
    workload_identity_provider: str
    service_account: str


@dataclass(frozen=True)
class SourceAsset:
    asset_id: str
    url: str = field(repr=False)
    content_type: str
    size_bytes: int
    kind: str
    extension: str
    ordinal: int
    role: str | None


@dataclass(frozen=True)
class Claim:
    inputs: dict[str, str]
    upload: UploadContract
    sources: list[SourceAsset]


def parse_claim(data: Any, *, max_sources: int, source_kinds: set[str] | frozenset[str] = frozenset()) -> Claim:
    if not isinstance(data, dict):
        raise ValueError("the ii-os claim response has no data object")
    inputs = data.get("inputs")
    if (
        not isinstance(inputs, dict)
        or not inputs
        or any(not isinstance(key, str) or not isinstance(value, str) for key, value in inputs.items())
    ):
        raise ValueError("the ii-os claim inputs must be a non-empty map of strings")
    return Claim(
        inputs=dict(inputs),
        upload=_upload_contract(data.get("gcpUpload")),
        sources=_sources(data, max_sources=max_sources, source_kinds=source_kinds),
    )


def _upload_contract(value: Any) -> UploadContract:
    if not isinstance(value, dict):
        raise ValueError("the ii-os claim has no upload contract")
    provider = value.get("provider", "gcp_wif")
    if provider not in SUPPORTED_UPLOAD_PROVIDERS:
        raise ValueError(
            f"upload provider {provider} is not supported by this workflow kit; "
            f"it uploads through {', '.join(SUPPORTED_UPLOAD_PROVIDERS)} only"
        )
    bucket = value.get("bucket")
    prefix = value.get("objectPrefix")
    workload = value.get("workloadIdentityProvider")
    account = value.get("serviceAccount")
    if not isinstance(bucket, str) or not BUCKET.fullmatch(bucket):
        raise ValueError("the upload contract bucket is invalid")
    if not isinstance(prefix, str) or not _valid_prefix(prefix):
        raise ValueError("the upload contract object prefix is not a workspace run prefix")
    if not isinstance(workload, str) or not WORKLOAD_PROVIDER.fullmatch(workload):
        raise ValueError("the upload contract workload identity provider is invalid")
    if not isinstance(account, str) or not SERVICE_ACCOUNT.fullmatch(account):
        raise ValueError("the upload contract service account is invalid")
    return UploadContract(provider, bucket, prefix, workload, account)


def _valid_prefix(prefix: str) -> bool:
    if not prefix.startswith("workspaces/") or not prefix.endswith("/") or len(prefix) > 600:
        return False
    segments = prefix[:-1].split("/")
    return len(segments) == 4 and segments[2] in {"ghost", "runs"} and all(
        segment and segment not in {".", ".."} and re.fullmatch(r"[A-Za-z0-9_.:-]+", segment)
        for segment in segments
    )


def _sources(data: dict[str, Any], *, max_sources: int, source_kinds: set[str] | frozenset[str]) -> list[SourceAsset]:
    raw = data.get("sourceAssets")
    if raw is None and data.get("sourceAsset") is not None:
        raw = [data["sourceAsset"]]
    if raw is None:
        raw = []
    if not isinstance(raw, list) or len(raw) > MAX_SOURCES:
        raise ValueError("the ii-os claim source assets are invalid")
    if len(raw) > max_sources:
        raise ValueError(f"the claim delivered {len(raw)} source assets; this workflow reads at most {max_sources} source assets")
    return [_source(item, ordinal, source_kinds) for ordinal, item in enumerate(raw)]


def _source(item: Any, ordinal: int, source_kinds: set[str] | frozenset[str]) -> SourceAsset:
    if not isinstance(item, dict):
        raise ValueError(f"source asset {ordinal} is invalid")
    asset_id = item.get("assetId")
    url = item.get("url")
    expires_at = item.get("expiresAt")
    content_type = item.get("contentType")
    size = item.get("sizeBytes")
    role = item.get("role")
    if not isinstance(asset_id, str) or not SOURCE_ID.fullmatch(asset_id):
        raise ValueError(f"source asset {ordinal} has an invalid asset id")
    if not isinstance(content_type, str) or content_type not in SOURCE_TYPES:
        raise ValueError(f"source asset {ordinal} has unsupported content type {content_type!s:.40}")
    kind, extension, limit = SOURCE_TYPES[content_type]
    if source_kinds and kind not in source_kinds:
        raise ValueError(f"source asset {ordinal} is {content_type}; this workflow reads {', '.join(sorted(source_kinds))} only")
    if item.get("kind") is not None and item.get("kind") != kind:
        raise ValueError(f"source asset {ordinal} declares a kind that does not match {content_type}")
    if item.get("ordinal") is not None and item.get("ordinal") != ordinal:
        raise ValueError(f"source asset {ordinal} is out of order")
    if role is not None and (not isinstance(role, str) or not SOURCE_ROLE.fullmatch(role)):
        raise ValueError(f"source asset {ordinal} has an invalid role")
    if isinstance(size, bool) or not isinstance(size, int) or not 0 < size <= limit:
        raise ValueError(f"source asset {ordinal} size is outside the accepted range")
    if not isinstance(url, str) or not _signed_gcs_url(url):
        raise ValueError(f"source asset {ordinal} is not an HTTPS Google Cloud Storage URL")
    if not isinstance(expires_at, str) or _expired(expires_at):
        raise ValueError(f"source asset {ordinal} read grant is expired or has no expiry")
    return SourceAsset(asset_id, url, content_type, size, kind, extension, ordinal, role)


def _signed_gcs_url(url: str) -> bool:
    try:
        parsed = urllib.parse.urlparse(url)
        host = (parsed.hostname or "").lower()
        port = parsed.port
    except ValueError:
        return False
    return (
        parsed.scheme == "https"
        and port in (None, 443)
        and not parsed.username
        and bool(parsed.path.strip("/"))
        and (host == "storage.googleapis.com" or host.endswith(".storage.googleapis.com"))
    )


def _expired(value: str) -> bool:
    try:
        expiry = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return True
    return expiry.tzinfo is None or expiry <= datetime.now(timezone.utc)


def work_dir_path(runner_temp: Path, identity: RunIdentity) -> Path:
    return runner_temp / f"ii-os-run-{identity.run_id}-{identity.run_attempt}"


def create_work_dir(runner_temp: Path, identity: RunIdentity) -> Path:
    if runner_temp.is_symlink() or not runner_temp.is_dir() or not runner_temp.is_absolute():
        raise ValueError("RUNNER_TEMP must be an existing absolute directory")
    work = work_dir_path(runner_temp.resolve(), identity)
    work.mkdir(mode=0o700)
    try:
        os.chmod(work, 0o700)  # nosemgrep: python.lang.security.audit.insecure-file-permissions.insecure-file-permissions -- Directory traversal is required; mode 0700 grants access only to its owner.
        _write_private(work / MARKER, identity.owner_record())
        for child in ("in", "in/sources", "out"):
            (work / child).mkdir(mode=0o700)
        return work
    except BaseException:
        shutil.rmtree(work, ignore_errors=True)
        raise


def materialize(claim: Claim, work: Path, *, opener: Opener | None = None) -> None:
    _write_private(work / "in" / "inputs.json", claim.inputs)
    staged: list[dict[str, Any]] = []
    for source in claim.sources:
        relative = f"sources/{source.ordinal:02d}.{source.extension}"
        digest = _download(source, work / "in" / relative, opener or _no_redirect_opener())
        staged.append(
            {
                "assetId": source.asset_id,
                "contentType": source.content_type,
                "file": relative,
                "kind": source.kind,
                "ordinal": source.ordinal,
                "role": source.role,
                "sha256": digest,
                "sizeBytes": source.size_bytes,
            }
        )
    _write_private(work / "in" / "sources.json", staged)


def _download(source: SourceAsset, destination: Path, opener: Opener) -> str:
    partial = destination.with_name(destination.name + ".part")
    request = urllib.request.Request(source.url, method="GET")
    digest = hashlib.sha256()
    received = 0
    try:
        with opener(request, timeout=DOWNLOAD_TIMEOUT_SECONDS) as response, _private_file(partial) as handle:
            while True:
                chunk = response.read(CHUNK)
                if not chunk:
                    break
                received += len(chunk)
                if received > source.size_bytes:
                    raise ValueError(f"source asset {source.ordinal} is larger than its recorded size")
                digest.update(chunk)
                handle.write(chunk)
        if received != source.size_bytes:
            raise ValueError(f"source asset {source.ordinal} size does not match its recorded size")
        partial.replace(destination)
        return digest.hexdigest()
    except urllib.error.HTTPError as error:
        error.close()
        raise ValueError(f"source asset {source.ordinal} download was refused with HTTP {error.code}") from None
    except urllib.error.URLError:
        raise ValueError(f"source asset {source.ordinal} could not be downloaded") from None
    finally:
        partial.unlink(missing_ok=True)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args: Any, **kwargs: Any) -> None:
        return None


def _no_redirect_opener() -> Opener:
    return urllib.request.build_opener(_NoRedirect()).open


def _private_file(path: Path) -> Any:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    return os.fdopen(descriptor, "wb")


def _write_private(path: Path, value: Any) -> None:
    with _private_file(path) as handle:
        handle.write((json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))


def cleanup(runner_temp: Path, identity: RunIdentity) -> bool:
    work = work_dir_path(runner_temp.resolve(), identity)
    if not work.exists() and not work.is_symlink():
        return False
    if work.is_symlink() or not work.is_dir():
        raise ValueError("the run directory is not an owned directory")
    marker = work / MARKER
    if marker.is_symlink() or not marker.is_file():
        raise ValueError("the run directory ownership marker is missing")
    if json.loads(marker.read_text(encoding="utf-8")) != identity.owner_record():
        raise ValueError("the run directory ownership marker does not match this run")
    if stat.S_IMODE(work.stat().st_mode) != 0o700:
        raise ValueError("the run directory permissions are not private")
    shutil.rmtree(work)
    return True


def write_outputs(path: str, values: Mapping[str, str]) -> None:
    for key, value in values.items():
        if "\n" in value or "\r" in value:
            raise ValueError(f"step output {key} contains a line break")
    with open(path, "a", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")


def _runner_temp(env: Mapping[str, str]) -> Path:
    value = env.get("RUNNER_TEMP", "").strip()
    if not value:
        raise ValueError("RUNNER_TEMP is not set; run this inside a GitHub Actions job")
    return Path(value)


def main(argv: Sequence[str], env: Mapping[str, str] | None = None, opener: Opener | None = None) -> int:
    env = os.environ if env is None else env
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    claim_parser = sub.add_parser("claim")
    claim_parser.add_argument("--max-sources", type=int, required=True)
    claim_parser.add_argument("--source-kinds", default="", help="comma-separated: image,video,audio")
    sub.add_parser("cleanup")
    args = parser.parse_args(list(argv))
    identity = RunIdentity.from_env(env)
    runner_temp = _runner_temp(env)
    if args.command == "cleanup":
        removed = cleanup(runner_temp, identity)
        print("ii-os run directory removed" if removed else "no ii-os run directory to remove")
        return 0

    url, token = connector_settings(env)
    if not 0 <= args.max_sources <= MAX_SOURCES:
        raise ValueError(f"--max-sources must be between 0 and {MAX_SOURCES}")
    kinds = frozenset(kind for kind in args.source_kinds.split(",") if kind)
    if not kinds <= {"image", "video", "audio"}:
        raise ValueError("--source-kinds accepts image, video and audio")
    data = Connector(url, token, opener=opener).claim(identity)
    claim = parse_claim(data, max_sources=args.max_sources, source_kinds=kinds)
    work = create_work_dir(runner_temp, identity)
    try:
        materialize(claim, work, opener=opener)
        write_outputs(
            env.get("GITHUB_OUTPUT", "") or os.devnull,
            {
                "work-dir": str(work),
                "upload-provider": claim.upload.provider,
                "bucket": claim.upload.bucket,
                "object-prefix": claim.upload.object_prefix,
                "workload-identity-provider": claim.upload.workload_identity_provider,
                "service-account": claim.upload.service_account,
                "source-count": str(len(claim.sources)),
            },
        )
    except BaseException:
        cleanup(runner_temp, identity)
        raise
    print(f"claimed ii-os request {identity.request_id} with {len(claim.sources)} source asset(s)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except SettingError as error:
        print(f"::error title=ii-os setting::{error}")
        raise SystemExit(2) from None
    except ConnectorError as error:
        print(f"::error title=ii-os claim rejected::{error}")
        print("Check that this repository holds the II_OS_TOKEN and II_OS_CONNECTOR_URL issued for it.", file=sys.stderr)
        raise SystemExit(1) from None
    except (OSError, ValueError) as error:
        print(f"::error title=ii-os claim::{error}")
        raise SystemExit(1) from None
