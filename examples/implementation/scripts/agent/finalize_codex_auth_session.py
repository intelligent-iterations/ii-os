#!/usr/bin/env python3
"""Finalize Codex auth only after the runtime cleanup job has succeeded."""

from __future__ import annotations

import os
import re
import sys

from codex_auth_session_client import (
    REPOSITORY,
    SESSION_ID,
    SessionFailure,
    configured_connector,
    post_json,
    run_metadata,
)


def main() -> int:
    connector = configured_connector()
    session_id = os.environ.get("II_OS_CODEX_AUTH_SESSION_ID", "").strip()
    repository = os.environ.get("II_OS_CODEX_AUTH_REPOSITORY", "").strip()
    secret_digest = os.environ.get("II_OS_CODEX_SECRET_DIGEST", "").strip()
    if (
        not SESSION_ID.fullmatch(session_id)
        or not REPOSITORY.fullmatch(repository)
        or repository != os.environ.get("GITHUB_REPOSITORY")
        or not re.fullmatch(r"[0-9a-f]{64}", secret_digest)
    ):
        raise SessionFailure(
            "codex_auth_configuration_missing",
            "The Codex cleanup finalizer is not configured.",
        )
    post_json(
        connector,
        f"v1/codex-auth-sessions/{session_id}/events",
        {
            "status": "succeeded",
            "secretDigest": secret_digest,
            **run_metadata(),
        },
    )
    print("Codex authentication finalized after runtime cleanup proof.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SessionFailure as error:
        print(f"Codex authentication finalization failed: {error.code}: {error.detail}", file=sys.stderr)
        raise SystemExit(1)
