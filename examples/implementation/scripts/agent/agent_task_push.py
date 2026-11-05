"""Trusted post-cleanup publication of one exact agent change bundle.

Environment (each is required and reported by name when missing):
  AGENT_RESULT_B64           base64 JSON agent result carrying the PR intent
  AGENT_BUNDLE_ARTIFACT_B64  base64 JSON descriptor of the collected bundle
  GITHUB_PUSH_TOKEN          publication token issued by the ii-os broker
  PUSH_APP_LOGIN             the broker App's bot login, ``<slug>[bot]``
  II_OS_AGENT_ARTIFACT_ROOT  absolute private root of collected artifacts
  GITHUB_OUTPUT              receives ``publication_receipt_b64``

The bundle is verified against its digest, must resolve to the reviewed head,
must descend from the unchanged base with a real diff, and is pushed only to a
previously absent dispatch branch with an expected-old-SHA lease.
"""

import base64
import hashlib
import json
import os
import re
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

from agent_task_result import read_verified_artifact


BUNDLE_PATH = "artifacts/ii-os-agent-change.bundle"
_SHA = re.compile(r"^[0-9a-f]{40}$")
_REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
_APP_LOGIN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,98}[a-z0-9])?\[bot\]$")


def publish_agent_bundle_artifact(
    artifact, artifact_root, result, *, push_token, remote_url=None,
    repository_id_lookup=None,
):
    """Verify and push the exact result commit with an expected-old-SHA lease."""
    intent = result.get("pull_request")
    if intent is None:
        if artifact is not None:
            raise RuntimeError("change bundle requires a PR intent")
        return None
    if not isinstance(artifact, dict) or artifact.get("path") != BUNDLE_PATH:
        raise RuntimeError("PR intent requires its exact change bundle")
    dispatch_id = result.get("dispatch_id")
    if not isinstance(dispatch_id, str):
        raise RuntimeError("redacted artifact needs its exact dispatch scope")
    scope = hashlib.sha256(dispatch_id.encode()).hexdigest()[:32]
    bundle = read_verified_artifact(
        artifact_root,
        artifact,
        scope=scope,
        maximum=64 * 1024 * 1024,
        label="change bundle",
    )
    repository = intent.get("repository")
    expected_repository_id = intent.get("repository_id")
    if not isinstance(repository, str) or not _REPOSITORY.fullmatch(repository):
        raise RuntimeError("agent pull request needs its target repository")
    if (
        not isinstance(expected_repository_id, int)
        or isinstance(expected_repository_id, bool)
        or expected_repository_id <= 0
    ):
        raise RuntimeError("agent pull request needs its immutable repository ID")
    remote = remote_url or f"https://github.com/{repository}.git"
    lookup_repository_id = (
        repository_id_lookup
        if repository_id_lookup is not None
        else lambda: _github_repository_id(repository, push_token)
    )
    head = intent["head"]
    base = intent["base"]
    head_sha = intent["head_sha"]
    base_sha = intent["base_sha"]
    expected_old = intent["expected_old_head_sha"]
    if (
        not _SHA.fullmatch(head_sha)
        or not _SHA.fullmatch(base_sha)
        or expected_old is not None
    ):
        raise RuntimeError(
            "agent bundle intent must target one previously absent dispatch branch"
        )

    with tempfile.TemporaryDirectory(prefix="ii-os-agent-push-") as scratch:
        scratch_path = Path(scratch)
        home = scratch_path / "home"
        home.mkdir(mode=0o700)
        (scratch_path / ".ii-os-disposable-owner").write_text(
            f"repository={repository}\nhead={head}\n",
            encoding="utf-8",
        )
        bundle_path = scratch_path / "change.bundle"
        bundle_path.write_bytes(bundle)
        mirror = scratch_path / "repository.git"
        _git_with_token(
            home, push_token, "clone", "--mirror", remote, str(mirror)
        )
        current_base = _remote_sha(home, push_token, remote, base)
        current_head = _remote_sha(home, push_token, remote, head)
        if current_base != base_sha or current_head not in ("", head_sha):
            raise RuntimeError(
                "repository refs changed after the agent checkout; refusing push"
            )
        _git(home, "-C", str(mirror), "bundle", "verify", str(bundle_path))
        _git(
            home, "-C", str(mirror), "fetch", str(bundle_path),
            f"refs/heads/{head}",
        )
        fetched = _git(
            home, "-C", str(mirror), "rev-parse", "FETCH_HEAD"
        ).stdout.strip()
        if fetched != head_sha:
            raise RuntimeError("change bundle did not resolve to the reviewed head")
        _git(
            home, "-C", str(mirror), "merge-base", "--is-ancestor",
            base_sha, head_sha,
        )
        if _git(
            home, "-C", str(mirror), "diff", "--quiet", base_sha, head_sha,
            check=False,
        ).returncode != 1:
            raise RuntimeError("change bundle does not contain one meaningful diff")
        lease = f"refs/heads/{head}:{expected_old or ''}"
        _require_repository_identity(lookup_repository_id, expected_repository_id)
        if current_head == "":
            try:
                _git_with_token(
                    home,
                    push_token,
                    "-C",
                    str(mirror),
                    "push",
                    f"--force-with-lease={lease}",
                    remote,
                    f"{head_sha}:refs/heads/{head}",
                )
            except RuntimeError:
                if _remote_sha(home, push_token, remote, head) != head_sha:
                    raise
        if _remote_sha(home, push_token, remote, head) != head_sha:
            raise RuntimeError("pushed branch does not resolve to the reviewed head")
        _require_repository_identity(lookup_repository_id, expected_repository_id)
        return _publication_receipt(
            dispatch_id=dispatch_id,
            repository=repository,
            repository_id=expected_repository_id,
            head=head,
            head_sha=head_sha,
            base=base,
            base_sha=base_sha,
            bundle_sha256=artifact["sha256"],
        )


def _publication_receipt(
    *, dispatch_id, repository, repository_id, head, head_sha, base, base_sha,
    bundle_sha256,
):
    return {
        "schema_version": 1,
        "disposition": "published",
        "dispatch_id": dispatch_id,
        "repository": repository,
        "repository_id": repository_id,
        "head": head,
        "head_sha": head_sha,
        "base": base,
        "base_sha": base_sha,
        "bundle_sha256": bundle_sha256,
    }


def _remote_sha(home, token, remote, ref):
    output = _git_with_token(
        home, token, "ls-remote", "--heads", remote, f"refs/heads/{ref}"
    )
    values = [line.split()[0] for line in output.splitlines() if line.strip()]
    if len(values) > 1 or (values and not _SHA.fullmatch(values[0])):
        raise RuntimeError("GitHub returned an ambiguous branch identity")
    return values[0] if values else ""


def _git_with_token(home, token, *arguments):
    if not token or "\n" in token or "\r" in token:
        raise RuntimeError("trusted GitHub token is invalid")
    encoded = base64.b64encode(f"x-access-token:{token}".encode()).decode()
    return _git(
        home,
        "-c",
        f"http.extraHeader=Authorization: Basic {encoded}",
        *arguments,
    ).stdout


def _github_repository_id(repository, token):
    if not token or "\n" in token or "\r" in token:
        raise RuntimeError("trusted GitHub token is invalid")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}",
        method="GET",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "ii-os-agent-publisher",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            value = json.loads(response.read().decode())
    except (urllib.error.HTTPError, urllib.error.URLError, ValueError) as error:
        raise RuntimeError(
            "GitHub repository identity could not be verified"
        ) from error
    if not isinstance(value, dict) or value.get("full_name") != repository:
        raise RuntimeError("GitHub returned a different repository identity")
    return value.get("id")


def _require_repository_identity(lookup, expected_repository_id):
    actual = lookup()
    if (
        not isinstance(actual, int)
        or isinstance(actual, bool)
        or actual != expected_repository_id
    ):
        raise RuntimeError(
            "numeric GitHub repository identity changed before publication"
        )


def _git(home, *arguments, check=True):
    completed = subprocess.run(
        ["git", "-c", "core.hooksPath=/dev/null", *arguments],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
        env={
            "PATH": os.environ.get("PATH", ""),
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(Path(home) / ".config"),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_ATTR_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_ALLOW_PROTOCOL": "https:file",
        },
    )
    if check and completed.returncode != 0:
        detail = completed.stderr.strip().replace("\n", " ")[:500]
        raise RuntimeError(f"trusted git command failed: {detail}")
    return completed


def _required(environment, name):
    value = environment.get(name, "")
    if not value:
        raise SystemExit(f"{name} is required")
    return value


def _decoded_json(environment, name):
    try:
        return json.loads(
            base64.b64decode(_required(environment, name), validate=True)
        )
    except (ValueError, UnicodeDecodeError):
        raise SystemExit(f"{name} must be base64-encoded JSON") from None


def run(environment, *, remote_url=None, repository_id_lookup=None):
    """Publish from step environment and append the publication receipt."""
    login = _required(environment, "PUSH_APP_LOGIN")
    if not _APP_LOGIN.fullmatch(login):
        raise SystemExit("PUSH_APP_LOGIN must be a GitHub App bot login")
    artifact_root = _required(environment, "II_OS_AGENT_ARTIFACT_ROOT")
    if not os.path.isabs(artifact_root):
        raise SystemExit("II_OS_AGENT_ARTIFACT_ROOT must be an absolute path")
    push_token = _required(environment, "GITHUB_PUSH_TOKEN")
    output_path = _required(environment, "GITHUB_OUTPUT")
    result = _decoded_json(environment, "AGENT_RESULT_B64")
    descriptor = _decoded_json(environment, "AGENT_BUNDLE_ARTIFACT_B64")
    if not isinstance(result, dict):
        raise SystemExit("AGENT_RESULT_B64 must encode one result object")
    receipt = publish_agent_bundle_artifact(
        descriptor,
        artifact_root,
        result,
        push_token=push_token,
        remote_url=remote_url,
        repository_id_lookup=repository_id_lookup,
    )
    if not isinstance(receipt, dict):
        raise RuntimeError("change bundle publication returned no receipt")
    encoded = base64.b64encode(
        json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode()
    ).decode()
    with open(output_path, "a", encoding="utf-8") as output:
        output.write(f"publication_receipt_b64={encoded}\n")
    return receipt


def main():
    try:
        run(os.environ)
    except RuntimeError as error:
        raise SystemExit(f"agent_task_push: {error}") from None


if __name__ == "__main__":
    main()
