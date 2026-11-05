#!/usr/bin/env python3
"""Mint one operation-scoped GitHub App token by immutable repository ID.

Environment (each is required and reported by name when missing):
  II_OS_GITHUB_APP_ID, II_OS_GITHUB_APP_PRIVATE_KEY, II_OS_GITHUB_APP_SLUG
      The operator's GitHub App. The App reported by GitHub and the
      repository installation must both carry exactly this ID and slug.
  TARGET_REPOSITORY, TARGET_REPOSITORY_ID
      ``owner/name`` and the immutable numeric repository ID to scope to.
  GITHUB_PERMISSION_LEVEL
      ``read`` or ``write`` for the ``contents`` permission
      (``GITHUB_PERMISSION`` optionally names it and defaults to contents).
  GITHUB_OUTPUT
      Receives ``token``, ``app-slug`` and ``repository-id``.

The token is masked with ``::add-mask::`` before anything else is printed.
"""

from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone


_API = "https://api.github.com"
_API_VERSION = "2026-03-10"
_REPOSITORY = re.compile(
    r"^[A-Za-z0-9](?:[A-Za-z0-9_.-]{0,99})/"
    r"[A-Za-z0-9](?:[A-Za-z0-9_.-]{0,99})$"
)
_SLUG = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,98}[a-z0-9])?$")
_TOKEN = re.compile(r"^[^\s]{20,4096}$")
_ALLOWED_PERMISSIONS = {"contents"}
_ALLOWED_LEVELS = {"read", "write"}
_MAX_RESPONSE = 1 << 20


@dataclass(frozen=True)
class RepositoryToken:
    token: str
    app_slug: str
    repository_id: int


class GitHubApi:
    def __init__(self, base_url: str = _API):
        self.base_url = base_url.rstrip("/")

    def request(self, method, path, authorization, body=None):
        encoded = None
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {authorization}",
            "X-GitHub-Api-Version": _API_VERSION,
            "User-Agent": "ii-os-repository-token/1",
        }
        if body is not None:
            encoded = json.dumps(
                body, sort_keys=True, separators=(",", ":")
            ).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            self.base_url + path,
            data=encoded,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                value = response.read(_MAX_RESPONSE + 1)
        except urllib.error.HTTPError as error:
            raise RuntimeError(
                f"GitHub App request failed with HTTP {error.code}"
            ) from error
        except urllib.error.URLError as error:
            raise RuntimeError("GitHub App request could not complete") from error
        if len(value) > _MAX_RESPONSE:
            raise RuntimeError("GitHub App response exceeded the size limit")
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError as error:
            raise RuntimeError("GitHub App returned invalid JSON") from error
        if not isinstance(decoded, dict):
            raise RuntimeError("GitHub App returned an invalid response")
        return decoded

def mint_repository_token(
    *,
    app_id,
    private_key,
    expected_app_slug,
    repository,
    repository_id,
    permission,
    level,
    api=None,
    jwt_factory=None,
):
    app_id = _positive_integer(app_id, "GitHub App ID")
    repository_id = _positive_integer(repository_id, "repository ID")
    if not isinstance(repository, str) or not _REPOSITORY.fullmatch(repository):
        raise RuntimeError("target repository is invalid")
    if (
        not isinstance(expected_app_slug, str)
        or not _SLUG.fullmatch(expected_app_slug)
    ):
        raise RuntimeError("expected GitHub App slug is invalid")
    if permission not in _ALLOWED_PERMISSIONS or level not in _ALLOWED_LEVELS:
        raise RuntimeError("requested GitHub App permission is unsupported")
    if not isinstance(private_key, str) or not private_key.strip():
        raise RuntimeError("GitHub App private key is missing")
    github = api or GitHubApi()
    jwt = (jwt_factory or github_app_jwt)(app_id, private_key)
    app = github.request("GET", "/app", jwt)
    if app.get("id") != app_id or app.get("slug") != expected_app_slug:
        raise RuntimeError("GitHub App identity does not match")
    owner, name = repository.split("/", 1)
    installation = github.request(
        "GET",
        "/repos/"
        + urllib.parse.quote(owner, safe="")
        + "/"
        + urllib.parse.quote(name, safe="")
        + "/installation",
        jwt,
    )
    installation_id = installation.get("id")
    if (
        type(installation_id) is not int
        or installation_id <= 0
        or installation.get("app_id") != app_id
        or installation.get("app_slug") != expected_app_slug
    ):
        raise RuntimeError("GitHub App installation identity does not match")
    minted = github.request(
        "POST",
        f"/app/installations/{installation_id}/access_tokens",
        jwt,
        {
            "repository_ids": [repository_id],
            "permissions": {permission: level},
        },
    )
    _validate_minted_token(
        minted,
        repository_id=repository_id,
        permission=permission,
        level=level,
    )
    return RepositoryToken(minted["token"], expected_app_slug, repository_id)


def github_app_jwt(app_id, private_key):
    now = int(time.time())
    header = _base64url(json.dumps(
        {"alg": "RS256", "typ": "JWT"}, separators=(",", ":")
    ).encode())
    payload = _base64url(json.dumps(
        {"iat": now - 60, "exp": now + 540, "iss": str(app_id)},
        separators=(",", ":"),
    ).encode())
    unsigned = f"{header}.{payload}".encode()
    key = private_key.replace("\\n", "\n").encode()
    if len(key) > 8192:
        raise RuntimeError("GitHub App private key is invalid")
    read_fd, write_fd = os.pipe()
    try:
        offset = 0
        while offset < len(key):
            written = os.write(write_fd, key[offset:])
            if written <= 0:
                raise RuntimeError("GitHub App private key handoff stopped")
            offset += written
        os.close(write_fd)
        write_fd = -1
        signed = subprocess.run(
            [
                "openssl",
                "dgst",
                "-sha256",
                "-sign",
                f"/dev/fd/{read_fd}",
            ],
            input=unsigned,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
            pass_fds=(read_fd,),
        )
    finally:
        if write_fd >= 0:
            os.close(write_fd)
        os.close(read_fd)
    if signed.returncode != 0 or not signed.stdout:
        raise RuntimeError("GitHub App JWT signing failed")
    return unsigned.decode() + "." + _base64url(signed.stdout)


def _validate_minted_token(
    minted, *, repository_id, permission, level
):
    token = minted.get("token")
    permissions = minted.get("permissions")
    expires_at = minted.get("expires_at")
    repository_selection = minted.get("repository_selection")
    if (
        not isinstance(token, str)
        or not _TOKEN.fullmatch(token)
        or not isinstance(expires_at, str)
    ):
        raise RuntimeError("GitHub App minted an invalid token envelope")
    if (
        not isinstance(permissions, dict)
        or permissions.get(permission) != level
        or set(permissions) - {permission, "metadata"}
        or (
            "metadata" in permissions
            and permissions.get("metadata") != "read"
        )
    ):
        raise RuntimeError(
            "GitHub App minted overbroad or invalid token permissions"
        )
    if repository_selection != "selected":
        raise RuntimeError("GitHub App minted an unscoped repository token")
    repositories = minted.get("repositories")
    if not isinstance(repositories, list) or len(repositories) != 1:
        raise RuntimeError(
            "GitHub App minted an overbroad or invalid repository response"
        )
    candidate = repositories[0]
    if not isinstance(candidate, dict):
        raise RuntimeError("GitHub App minted an invalid repository response")
    candidate_id = candidate.get("id")
    candidate_name = candidate.get("full_name")
    if (
        candidate_id != repository_id
        or not isinstance(candidate_name, str)
        or not _REPOSITORY.fullmatch(candidate_name)
    ):
        raise RuntimeError("GitHub App minted a substituted repository response")
    try:
        expiry = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise RuntimeError("GitHub App token expiry is invalid") from error
    if expiry.tzinfo is None or expiry <= datetime.now(timezone.utc):
        raise RuntimeError("GitHub App minted an expired token")


def _positive_integer(value, label):
    if type(value) is int:
        parsed = value
    elif isinstance(value, str) and value.isdigit():
        parsed = int(value)
    else:
        raise RuntimeError(f"{label} is invalid")
    if parsed <= 0:
        raise RuntimeError(f"{label} is invalid")
    return parsed


def _base64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()



def _required(environment, name):
    value = environment.get(name, "")
    if not value:
        raise SystemExit(f"{name} is required")
    return value


def run(environment, *, api=None, jwt_factory=None, emit=print):
    """Mint from operator settings and append the step outputs."""
    settings = {
        name: _required(environment, name)
        for name in (
            "II_OS_GITHUB_APP_ID",
            "II_OS_GITHUB_APP_PRIVATE_KEY",
            "II_OS_GITHUB_APP_SLUG",
            "TARGET_REPOSITORY",
            "TARGET_REPOSITORY_ID",
            "GITHUB_PERMISSION_LEVEL",
            "GITHUB_OUTPUT",
        )
    }
    permission = environment.get("GITHUB_PERMISSION") or "contents"
    result = mint_repository_token(
        app_id=settings["II_OS_GITHUB_APP_ID"],
        private_key=settings["II_OS_GITHUB_APP_PRIVATE_KEY"],
        expected_app_slug=settings["II_OS_GITHUB_APP_SLUG"],
        repository=settings["TARGET_REPOSITORY"],
        repository_id=settings["TARGET_REPOSITORY_ID"],
        permission=permission,
        level=settings["GITHUB_PERMISSION_LEVEL"],
        api=api,
        jwt_factory=jwt_factory,
    )
    emit(f"::add-mask::{result.token}")
    with open(settings["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"token={result.token}\n")
        output.write(f"app-slug={result.app_slug}\n")
        output.write(f"repository-id={result.repository_id}\n")
    emit(
        json.dumps(
            {
                "app_slug": result.app_slug,
                "repository_id": result.repository_id,
                "permission": permission,
                "level": settings["GITHUB_PERMISSION_LEVEL"],
            },
            sort_keys=True,
        )
    )
    return result


def _main():
    try:
        run(os.environ)
    except RuntimeError as error:
        raise SystemExit(f"github_app_repository_token: {error}") from None


if __name__ == "__main__":
    _main()
