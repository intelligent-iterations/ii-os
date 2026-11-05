#!/usr/bin/env python3
"""Reuse or connect Codex OAuth, verify it, and store it directly in GitHub."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from pathlib import Path

from codex_auth_session_client import (
    REPOSITORY,
    SESSION_ID,
    CodexAppServer,
    SessionFailure,
    configured_connector,
    post_json,
    require_subscription_oauth,
    run_metadata,
    smoke_codex,
)
from codex_credential_receipt import committed_credential


def wait_for_reusable_auth(auth_file: Path, timeout: float = 10) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if auth_file.is_symlink():
                raise OSError("auth file is a symlink")
            decoded = json.loads(auth_file.read_text(encoding="utf-8"))
            if isinstance(decoded, dict) and auth_file.stat().st_size >= 100:
                return
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            time.sleep(0.1)
    raise SessionFailure(
        "codex_auth_file_missing",
        "OpenAI sign-in completed, but Codex did not save a reusable credential.",
    )


def stage_saved_auth(auth_file: Path, encoded: str) -> bool:
    if not encoded:
        return False
    try:
        data = encoded.encode("utf-8")
        if not 100 <= len(data) <= 49152:
            raise ValueError("credential size")
        require_subscription_oauth(json.loads(data))
    except (UnicodeError, ValueError, TypeError) as error:
        raise SessionFailure(
            "codex_auth_repository_secret_invalid",
            "The repository Codex credential is missing or malformed.",
        ) from error
    try:
        descriptor = os.open(auth_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
    except OSError as error:
        raise SessionFailure("codex_auth_file_invalid", "The private Codex credential could not be staged.") from error
    return True


def main() -> int:
    saved_auth = os.environ.pop("CODEX_AUTH_JSON", "")
    # Refuse to start (no login, worker or callback) without a valid connector.
    connector = configured_connector()
    reauthenticate = os.environ.get("II_OS_CODEX_AUTH_REAUTHENTICATE", "false")
    if reauthenticate not in {"true", "false"}:
        raise SessionFailure("codex_auth_configuration_missing", "The Codex reauthentication choice is invalid.")
    session_id = os.environ.get("II_OS_CODEX_AUTH_SESSION_ID", "").strip()
    repository = os.environ.get("II_OS_CODEX_AUTH_REPOSITORY", "").strip()
    if (
        not SESSION_ID.fullmatch(session_id)
        or not REPOSITORY.fullmatch(repository)
        or repository != os.environ.get("GITHUB_REPOSITORY")
    ):
        raise SessionFailure(
            "codex_auth_configuration_missing",
            "The repository sign-in workflow is not configured.",
        )
    route = f"v1/codex-auth-sessions/{session_id}/events"
    metadata = run_metadata()
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp")).resolve()
    with tempfile.TemporaryDirectory(
        prefix="ii-os-codex-auth-", dir=runner_temp
    ) as root:
        root_path = Path(root)
        codex_home = root_path / "codex-home"
        smoke_dir = root_path / "smoke"
        codex_home.mkdir(mode=0o700)
        smoke_dir.mkdir(mode=0o700)
        config = codex_home / "config.toml"
        config.write_text(
            'cli_auth_credentials_store = "file"\n',
            encoding="utf-8",
        )
        config.chmod(0o600)
        auth_file = codex_home / "auth.json"
        reused = reauthenticate == "false" and stage_saved_auth(auth_file, saved_auth)
        if not reused:
            app_server = CodexAppServer(codex_home)
            try:
                app_server.initialize()
                login_id, verification_url, user_code = app_server.start_device_login()
                post_json(connector, route, {
                    "status": "waiting_for_user", "verificationUrl": verification_url,
                    "userCode": user_code, **metadata,
                })
                app_server.wait_for_login(login_id)
                wait_for_reusable_auth(auth_file)
            finally:
                app_server.close()
        post_json(
            connector,
            route,
            {"status": "validating", **metadata},
        )
        os.environ["II_OS_CODEX_AUTH_CREDENTIAL_PROVIDER"] = (
            "github-actions" if reused else "codex-device-login"
        )
        try:
            smoke_codex(codex_home, smoke_dir)
        finally:
            os.environ.pop("II_OS_CODEX_AUTH_CREDENTIAL_PROVIDER", None)
        post_json(
            connector,
            route,
            {"status": "writing_secret", **metadata},
        )
        # The trusted Node adapter saves refreshes only after worker cleanup.
        # Python emits lifecycle metadata; it does not obtain a second writer.
        receipt = committed_credential("codex-auth")
        post_json(
            connector,
            route,
            {
                "status": "awaiting_cleanup",
                "secretUpdatedAt": receipt["secretUpdatedAt"],
                "secretDigest": receipt["secretDigest"],
                **metadata,
            },
        )
    print("Codex OAuth smoke passed and the saved credential was confirmed.")
    return 0


def report_failure(error: SessionFailure) -> None:
    session_id = os.environ.get("II_OS_CODEX_AUTH_SESSION_ID", "").strip()
    if SESSION_ID.fullmatch(session_id):
        try:
            post_json(
                configured_connector(),
                f"v1/codex-auth-sessions/{session_id}/events",
                {
                    "status": "failed",
                    "errorCode": error.code,
                    "detail": error.detail,
                    **run_metadata(),
                },
            )
        except Exception:
            pass
    # Codes and details are fixed strings; credential bytes never reach them.
    print(f"Codex authentication failed: {error.code}: {error.detail}", file=sys.stderr)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SessionFailure as error:
        report_failure(error)
        raise SystemExit(1)
    except Exception:
        unexpected = SessionFailure(
            "codex_auth_unexpected_failure",
            "The secure Codex sign-in job stopped unexpectedly. "
            "Open the workflow logs and try again.",
        )
        report_failure(unexpected)
        raise SystemExit(1)
