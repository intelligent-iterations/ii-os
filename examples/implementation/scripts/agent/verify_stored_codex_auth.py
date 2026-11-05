#!/usr/bin/env python3
"""Smoke the exact repository-secret snapshot through a fresh runtime worker."""

import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

from codex_auth_session_client import SessionFailure, require_subscription_oauth, smoke_codex
from codex_credential_receipt import committed_credential


def main():
    encoded = os.environ.pop("CODEX_AUTH_JSON", "").encode()
    if not 100 <= len(encoded) <= 49152:
        raise SessionFailure(
            "codex_auth_repository_secret_invalid",
            "The repository Codex credential is missing or malformed.",
        )
    try:
        decoded = json.loads(encoded)
    except json.JSONDecodeError as error:
        raise SessionFailure(
            "codex_auth_repository_secret_invalid",
            "The repository Codex credential is not valid JSON.",
        ) from error
    if not isinstance(decoded, dict):
        raise SessionFailure(
            "codex_auth_repository_secret_invalid",
            "The repository Codex credential is not a JSON object.",
        )
    try:
        # Subscription OAuth only: refuse an API key before any file write.
        require_subscription_oauth(decoded)
    except ValueError as error:
        raise SessionFailure(
            "codex_auth_repository_secret_invalid",
            "The repository Codex credential is not a subscription OAuth login.",
        ) from error
    digest = hashlib.sha256(encoded).hexdigest()
    runner_temp = Path(os.environ["RUNNER_TEMP"]).resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="ii-os-stored-codex-", dir=runner_temp) as root:
        codex_home = Path(root) / "codex-home"
        smoke_dir = Path(root) / "smoke"
        codex_home.mkdir(mode=0o700)
        smoke_dir.mkdir(mode=0o700)
        (codex_home / "config.toml").write_text(
            'cli_auth_credentials_store = "file"\n',
            encoding="utf-8",
        )
        auth = codex_home / "auth.json"
        descriptor = os.open(auth, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(encoded)
        smoke_codex(codex_home, smoke_dir)
        receipt = committed_credential("codex-auth-verify", original_digest=digest)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"secret_digest={receipt['secretDigest']}\n")


if __name__ == "__main__":
    try:
        main()
    except SessionFailure as error:
        print(f"Stored Codex verification failed: {error.code}: {error.detail}", file=sys.stderr)
        raise SystemExit(1)
