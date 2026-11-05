"""Read only the run-bound metadata receipt of a committed private handoff.

The receipt is the credential-rotation journal kept by the trusted Node
adapter at ``$II_OS_CONTROLLER_STATE_DIR/credential-rotation/journal.json``.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import json
import os
from pathlib import Path
import re
import stat

from codex_auth_session_client import SessionFailure, controller_state_dir


DIGEST = re.compile(r"^[0-9a-f]{64}$")


def journal_path() -> Path:
    return controller_state_dir() / "credential-rotation" / "journal.json"


def committed_credential(kind: str, *, original_digest: str | None = None) -> dict:
    try:
        path = journal_path()
        for parent in (path.parent, path.parent.parent):
            info = parent.lstat()
            if (not stat.S_ISDIR(info.st_mode) or parent.resolve(strict=True) != parent
                    or info.st_uid != os.getuid() or info.st_mode & 0o077):
                raise ValueError("private receipt directory required")
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as source:
            info = os.fstat(source.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or info.st_nlink != 1 or info.st_mode & 0o077
                    or not 1 <= info.st_size <= 16384):
                raise ValueError("private receipt inode required")
            raw = source.read(16385)
            current = path.lstat()
            if (len(raw) != info.st_size
                    or (info.st_dev, info.st_ino) != (current.st_dev, current.st_ino)):
                raise ValueError("receipt inode changed")
        journal = json.loads(raw)
        owner, receipt = journal["owner"], journal["commit"]
        if (journal.get("schemaVersion") != 1 or journal.get("phase") != "committed"
                or owner.get("kind") != kind
                or owner.get("repository") != os.environ["GITHUB_REPOSITORY"]
                or owner.get("repositoryId") != int(os.environ["GITHUB_REPOSITORY_ID"])
                or owner.get("runId") != int(os.environ["GITHUB_RUN_ID"])
                or owner.get("runAttempt") != 1
                or receipt.get("committed") is not True
                or not DIGEST.fullmatch(receipt.get("secretDigest", ""))
                or journal.get("candidateDigest") != receipt["secretDigest"]
                or type(receipt.get("generation")) is not int or receipt["generation"] < 0
                or type(receipt.get("changed")) is not bool
                or (original_digest is not None and journal.get("originalDigest") != original_digest)):
            raise ValueError("receipt does not match this run")
        version = receipt["secretUpdatedAt"]
        if not isinstance(version, str) or not 20 <= len(version) <= 40:
            raise ValueError("updated provider version required")
        parsed = datetime.fromisoformat(version.replace("Z", "+00:00"))
        if parsed.year < 2025 or parsed.utcoffset() != timedelta(0):
            raise ValueError("UTC provider version required")
        return {"secretDigest": receipt["secretDigest"], "secretUpdatedAt": version,
                "generation": receipt["generation"], "changed": receipt["changed"]}
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        raise SessionFailure(
            "credential_refresh_unconfirmed",
            "The cleaned runtime did not confirm the repository credential handoff.",
        ) from error
