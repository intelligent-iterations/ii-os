#!/usr/bin/env python3
"""Shared exact-source and archive helpers for the browser engine build."""

from __future__ import annotations

import hashlib
import http.client
import math
import os
import subprocess
import tarfile
import time
import urllib.error
import urllib.request
from pathlib import Path


class WebEngineError(RuntimeError):
    pass


class _RetryableDownload(WebEngineError):
    pass


class _RejectedDownloadLocation(WebEngineError):
    pass


DOWNLOAD_ATTEMPTS = 5
DOWNLOAD_TIMEOUT_SECONDS = 180


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(
    command: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    *,
    capture: bool = False,
) -> str:
    print("+", " ".join(command), flush=True)
    process = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        check=False,
        capture_output=capture,
    )
    if process.returncode:
        detail = process.stderr.strip() if capture else ""
        raise WebEngineError(
            f"command failed with exit {process.returncode}: {detail}"
        )
    return process.stdout.strip() if capture else ""


def clone_exact(repository: str, revision: str, destination: Path) -> None:
    destination.mkdir()
    run(["git", "init", "--quiet", "--initial-branch=dev"], destination)
    run(["git", "remote", "add", "origin", repository], destination)
    run(["git", "fetch", "--quiet", "--depth", "1", "origin", revision], destination)
    run(["git", "reset", "--quiet", "--hard", "FETCH_HEAD"], destination)
    branch = run(
        ["git", "branch", "--show-current"], destination, capture=True
    )
    if branch != "dev":
        raise WebEngineError(
            f"source checkout moved off dev for {repository}: {branch}"
        )
    actual = run(["git", "rev-parse", "HEAD"], destination, capture=True)
    if actual != revision:
        raise WebEngineError(f"toolchain revision mismatch: {actual}")


def download_exact(
    url: str,
    expected: str,
    destination: Path,
    *,
    fallback_urls: tuple[str, ...] = (),
) -> str:
    candidates = (url, *fallback_urls)
    if len(candidates) != len(set(candidates)):
        raise WebEngineError("source download URLs must be unique")
    for candidate in candidates:
        if candidate.partition(":")[0] != "https":
            raise WebEngineError(f"source URL is not HTTPS: {candidate}")
    partial = destination.with_suffix(destination.suffix + ".partial")
    last_error: BaseException | None = None
    for candidate in candidates:
        request = urllib.request.Request(
            candidate, headers={"User-Agent": "ii-ffmpeg-build/1"}
        )
        for attempt in range(1, DOWNLOAD_ATTEMPTS + 1):
            try:
                # Only HTTPS candidates reach here (checked above), and a
                # redirect away from HTTPS is rejected below.
                with urllib.request.urlopen(  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected
                    request, timeout=DOWNLOAD_TIMEOUT_SECONDS
                ) as response:
                    if response.geturl().partition(":")[0] != "https":
                        raise _RejectedDownloadLocation(
                            f"source redirected away from HTTPS: {candidate}"
                        )
                    raw_length = getattr(response, "headers", {}).get(
                        "Content-Length"
                    )
                    try:
                        declared_length = (
                            int(raw_length) if raw_length is not None else None
                        )
                    except (TypeError, ValueError) as error:
                        raise WebEngineError(
                            "source response has an invalid Content-Length: "
                            f"{candidate}"
                        ) from error
                    if (
                        declared_length is not None
                        and not 0 <= declared_length <= 256 * 1024 * 1024
                    ):
                        raise WebEngineError(
                            f"source archive exceeds limit: {candidate}"
                        )
                    with partial.open("xb") as output:
                        size = 0
                        while chunk := response.read(1024 * 1024):
                            size += len(chunk)
                            if size > 256 * 1024 * 1024:
                                raise WebEngineError(
                                    f"source archive exceeds limit: {candidate}"
                                )
                            output.write(chunk)
                    if declared_length is not None and size != declared_length:
                        raise _RetryableDownload(
                            "source response ended before Content-Length: "
                            f"{candidate}"
                        )
                if sha256(partial) != expected:
                    raise _RetryableDownload(
                        f"source archive checksum mismatch: {candidate}"
                    )
                partial.replace(destination)
                return candidate
            except (
                TimeoutError,
                urllib.error.URLError,
                http.client.IncompleteRead,
                http.client.RemoteDisconnected,
                ConnectionResetError,
                _RetryableDownload,
            ) as error:
                last_error = error
                if attempt < DOWNLOAD_ATTEMPTS:
                    time.sleep(attempt * 2)
            except _RejectedDownloadLocation as error:
                last_error = error
                break
            finally:
                partial.unlink(missing_ok=True)
    assert last_error is not None
    raise WebEngineError(
        f"source download failed from {len(candidates)} HTTPS location(s); "
        f"last download error: {type(last_error).__name__}"
    ) from last_error


def extract_exact(archive: Path, destination: Path) -> None:
    destination.mkdir()
    root = destination.resolve()
    count = 0
    total = 0
    with tarfile.open(archive, "r:*") as source:
        for member in source:
            count += 1
            total += max(0, member.size)
            if count > 100_000 or total > 768 * 1024 * 1024:
                raise WebEngineError(f"source archive exceeds extraction limits: {archive}")
            target = (destination / member.name).resolve()
            if target != root and root not in target.parents:
                raise WebEngineError(f"source archive escapes its root: {member.name}")
            if member.issym() or member.islnk() or member.isdev():
                raise WebEngineError(f"source archive contains a link/device: {member.name}")
            if not (member.isdir() or member.isfile()):
                raise WebEngineError(f"unsupported archive entry: {member.name}")
            source.extract(member, destination, set_attrs=False)
            target.chmod(member.mode & 0o777)
            if member.isfile():
                mtime = float(member.mtime)
                if not math.isfinite(mtime) or not 0 <= mtime <= 4_102_444_800:
                    raise WebEngineError(
                        f"source archive has an invalid timestamp: {member.name}"
                    )
                # tarfile's set_attrs also applies ownership and other metadata
                # that the builder must not trust. Restore only the reviewed
                # source timestamp so generated Autotools inputs stay newer
                # than their source files regardless of extraction order.
                os.utime(target, (mtime, mtime), follow_symlinks=False)


def activated_emsdk_environment(emsdk: Path) -> dict[str, str]:
    helper = Path(__file__).with_name("print_emsdk_environment.sh")
    command = [str(helper), str(emsdk / "emsdk_env.sh")]
    process = subprocess.run(command, check=False, capture_output=True)
    if process.returncode:
        raise WebEngineError("unable to activate the exact Emscripten SDK")
    environment = os.environ.copy()
    for entry in process.stdout.split(b"\0"):
        if b"=" not in entry:
            continue
        key, value = entry.split(b"=", 1)
        environment[key.decode()] = value.decode()
    return environment
