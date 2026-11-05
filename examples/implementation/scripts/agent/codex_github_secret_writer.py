"""Exact repository-secret update for a trusted, already-cleaned OAuth run.

The caller authorizes and serializes the binding before issuing the token.
This adapter never obtains authority, reads a repository secret, or logs bytes.

Invocation: no arguments; one JSON object on stdin with exactly the keys
``repository``, ``authFile``, ``token``, ``expectedSecretUpdatedAt`` and
``expectedAbsent``. Stdout is one JSON line, either
``{"secretUpdatedAt": ..., "writerTokenRevoked": true}`` (exit 0) or
``{"error": "<code>"}`` (exit 1).

A writer token is single use: its first use is recorded as an empty 0600
marker ``.secret-writer-<sha256(token)>`` beside ``authFile`` before GitHub is
contacted, and any later call with the same token is refused without using it.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys


WRITER_MARKER_PREFIX = ".secret-writer-"


class SecretWriterFailure(RuntimeError):
    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code, self.detail = code, detail


def read_oauth_file(auth_file: Path) -> bytes:
    """Check a private, unchanged inode before any writer is requested."""
    try:
        parent, original = auth_file.parent.lstat(), auth_file.lstat()
        if (auth_file.resolve(strict=True) != auth_file
                or not stat.S_ISDIR(parent.st_mode)
                or parent.st_uid != os.getuid() or parent.st_mode & 0o077
                or not stat.S_ISREG(original.st_mode)):
            raise OSError("auth path is not private")
        descriptor = os.open(auth_file, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as source:
            info = os.fstat(source.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                    or info.st_uid != os.getuid() or info.st_mode & 0o077
                    or not 100 <= info.st_size <= 49152
                    or (info.st_dev, info.st_ino) != (original.st_dev, original.st_ino)):
                raise OSError("auth inode is not private")
            encoded = source.read(49153)
            current = auth_file.lstat()
            if (len(encoded) != info.st_size or current.st_nlink != 1
                    or current.st_mode & 0o077
                    or (current.st_dev, current.st_ino) != (original.st_dev, original.st_ino)):
                raise OSError("auth inode changed")
        auth = json.loads(encoded.decode("utf-8"))
        if (not isinstance(auth, dict) or auth.get("OPENAI_API_KEY")
                or not isinstance(auth.get("tokens"), dict)
                or not all(isinstance(auth["tokens"].get(key), str) and auth["tokens"][key]
                           for key in ("access_token", "refresh_token"))):
            raise ValueError("subscription OAuth required")
        return encoded
    except (OSError, UnicodeDecodeError, ValueError) as error:
        raise SecretWriterFailure(
            "codex_auth_file_invalid",
            "Codex did not create a valid reusable OAuth credential.",
        ) from error


def _consume_writer(directory: Path, token: str) -> bool:
    """Durably record a writer's first use; False when it was already used."""
    info = directory.lstat()
    if (not directory.is_absolute() or not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.getuid() or info.st_mode & 0o077):
        raise OSError("writer ledger directory is not private")
    marker = directory / (WRITER_MARKER_PREFIX + hashlib.sha256(token.encode("ascii")).hexdigest())
    try:
        descriptor = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        return False
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    parent = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(parent)
    finally:
        os.close(parent)
    return True


def _environment(auth_file: Path, token: str) -> dict[str, str]:
    allowed = ("PATH", "LANG", "LC_ALL", "TZ", "TMPDIR", "TEMP", "TMP",
               "SSL_CERT_FILE", "SSL_CERT_DIR")
    env = {key: os.environ[key] for key in allowed if os.environ.get(key)}
    # Never inherit host gh config, OAuth, GitHub or reporting credentials.
    env.update(HOME=str(auth_file.parent.parent), GH_TOKEN=token,
               GH_PROMPT_DISABLED="1", GH_HOST="github.com")
    return env


def _version(value: str) -> datetime:
    try:
        if not isinstance(value, str) or not 20 <= len(value) <= 40:
            raise ValueError("invalid provider version")
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.year < 2025 or parsed.utcoffset() != timedelta(0):
            raise ValueError("UTC provider version required")
        return parsed
    except ValueError as error:
        raise SecretWriterFailure(
            "github_secret_metadata_failed", "GitHub returned an invalid Codex secret version.",
        ) from error


def write_repository_secret(
    repository: str, auth_file: Path, token: str, *,
    expected_secret_updated_at: str | None, expected_absent: bool,
) -> str:
    """Write only CODEX_AUTH_JSON, inspect its version, and always revoke.

    The installation token is supplied in memory by the trusted caller. A
    failed/unknown write or revocation never returns a success receipt.
    """
    if not isinstance(token, str) or not re.fullmatch(r"[\x21-\x7e]{1,1024}", token):
        raise SecretWriterFailure("github_secret_writer_failed", "Invalid secret-writer authority.")
    try:
        first_use = _consume_writer(auth_file.parent, token)
    except OSError:
        first_use = None
    if first_use is False:
        # Its first use already ran the write and revocation; never use it again.
        raise SecretWriterFailure("github_secret_writer_reused", "The one-time secret writer was already used.")
    options = {"text": True, "capture_output": True,
               "env": _environment(auth_file, token), "check": False}
    try:
        if not isinstance(repository, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise SecretWriterFailure("github_secret_writer_failed", "Invalid secret-writer repository.")
        auth_json = read_oauth_file(auth_file).decode("utf-8")
        if first_use is None:
            raise SecretWriterFailure("github_secret_writer_failed", "The one-time secret writer could not be recorded.")
        try:
            if (type(expected_absent) is not bool
                    or (expected_absent and expected_secret_updated_at is not None)
                    or (not expected_absent and not isinstance(expected_secret_updated_at, str))):
                raise SecretWriterFailure("github_secret_precondition_invalid", "The secret version precondition is invalid.")
            before = subprocess.run(
                ["gh", "api", "--include", f"repos/{repository}/actions/secrets/CODEX_AUTH_JSON", "--jq", ".updated_at"],
                timeout=30, **options,
            )
            status = re.match(r"^HTTP/\S+\s+([0-9]{3})(?:\s|$)", before.stdout)
            status_code = int(status.group(1)) if status else None
            current_version = before.stdout.strip().splitlines()[-1] if before.stdout.strip() else None
            if ((expected_absent and (status_code != 404 or before.returncode == 0))
                    or (not expected_absent and (status_code != 200 or before.returncode != 0
                                                or _version(current_version) != _version(expected_secret_updated_at)))):
                raise SecretWriterFailure(
                    "github_secret_snapshot_stale", "The GitHub credential version no longer matches this run.",
                )
            written = subprocess.run(
                ["gh", "secret", "set", "CODEX_AUTH_JSON", "--repo", repository],
                input=auth_json, timeout=60, **options,
            )
            if written.returncode != 0:
                raise SecretWriterFailure(
                    "github_secret_write_failed", "GitHub rejected the refreshed Codex credential.",
                )
            metadata = subprocess.run(
                ["gh", "api", f"repos/{repository}/actions/secrets/CODEX_AUTH_JSON", "--jq", ".updated_at"],
                timeout=30, **options,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise SecretWriterFailure(
                "github_secret_write_unconfirmed", "GitHub could not confirm the Codex credential update.",
            ) from error
        if metadata.returncode != 0:
            raise SecretWriterFailure(
                "github_secret_metadata_failed", "GitHub could not attest the updated Codex secret version.",
            )
        updated_at = metadata.stdout.strip()
        _version(updated_at)
        return updated_at
    finally:
        try:
            revoked = subprocess.run(
                ["gh", "api", "--method", "DELETE", "/installation/token"],
                timeout=30, **options,
            )
            if revoked.returncode != 0:
                raise OSError("revocation unconfirmed")
        except (OSError, subprocess.TimeoutExpired) as error:
            raise SecretWriterFailure(
                "github_secret_writer_revoke_failed",
                "GitHub could not revoke the temporary secret-writer token.",
            ) from error


def main() -> int:
    try:
        raw = sys.stdin.buffer.read(65537)
        if len(raw) > 65536 or len(sys.argv) != 1:
            raise ValueError("invalid invocation")
        request = json.loads(raw)
        if not isinstance(request, dict) or set(request) != {
            "repository", "authFile", "token", "expectedSecretUpdatedAt", "expectedAbsent",
        }:
            raise ValueError("invalid request")
        updated_at = write_repository_secret(
            request["repository"], Path(request["authFile"]), request["token"],
            expected_secret_updated_at=request["expectedSecretUpdatedAt"], expected_absent=request["expectedAbsent"],
        )
        print(json.dumps({"secretUpdatedAt": updated_at, "writerTokenRevoked": True}))
        return 0
    except SecretWriterFailure as error:
        print(json.dumps({"error": error.code}))
    except (ValueError, TypeError, OSError):
        print(json.dumps({"error": "github_secret_writer_invocation_invalid"}))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
