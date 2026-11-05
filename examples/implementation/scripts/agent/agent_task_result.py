"""Verify one bounded agent decision collected after runtime cleanup.

Collected artifacts live under a private artifact root at
``ii-os-agent/<scope>/<runtime>/<artifact path>``, where ``<scope>`` is the
first 32 hex characters of sha256(dispatch_id). A descriptor names exactly
``path``, ``storage_path``, ``size_bytes``, ``sha256`` and ``content_type``;
the bytes are read without following symlinks and must match the digest.
"""

import hashlib
import json
import os
import re
import stat


RESULT_PATH = "artifacts/ii-os-agent-result.json"
_REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


def verified_agent_result_artifact(artifact, artifact_root, expected):
    """Apply the result policy to an exact collected descriptor."""
    if artifact.get("path") != RESULT_PATH:
        raise RuntimeError("agent result descriptor names another artifact")
    encoded = read_verified_artifact(
        artifact_root,
        artifact,
        scope=hashlib.sha256(expected["dispatch_id"].encode()).hexdigest()[:32],
        maximum=32768,
        label="agent result",
    )
    result = json.loads(encoded)
    if not isinstance(result, dict):
        raise RuntimeError("agent result must be an object")
    comments = result.get("comments")
    pull_request = result.get("pull_request")
    automation_failure = result.get("automation_failure")
    outcome = result.get("outcome")
    status = result.get("status")
    consistent = (
        outcome == "ready_for_qa" and status == "ready_for_qa"
    ) or (
        outcome == "not_ready"
        and status in ("todo", "needs_human_input")
    )
    if (
        {key: result.get(key) for key in expected} != expected
        or type(result.get("issue_number")) is not int
        or type(result.get("repository_id")) is not int
        or result["repository_id"] <= 0
        or set(result) != {
            *expected,
            "outcome",
            "status",
            "comments",
            "pull_request",
            "automation_failure",
        }
        or not consistent
        or (outcome == "ready_for_qa" and pull_request is None)
        or not isinstance(comments, list)
        or len(comments) > 8
        or any(
            not isinstance(comment, str)
            or not comment
            or comment != comment.strip()
            or len(comment) > 8000
            for comment in comments
        )
        or sum(len(comment) for comment in comments) > 24000
        or not _valid_automation_failure(
            automation_failure,
            allowed=outcome == "not_ready" and status == "todo",
        )
        or not _valid_pull_request(pull_request, expected["dispatch_id"])
    ):
        raise RuntimeError("agent result is not bound to this dispatch")
    return result


def read_verified_artifact(root_value, artifact, *, scope="", maximum, label):
    """Return the exact bytes one collected descriptor names."""
    root = os.path.abspath(root_value)
    relative_path = artifact.get("path")
    storage_path = artifact.get("storage_path")
    if (
        set(artifact) != {
            "path",
            "storage_path",
            "size_bytes",
            "sha256",
            "content_type",
        }
        or not isinstance(relative_path, str)
        or not isinstance(storage_path, str)
        or not relative_path
        or not storage_path
        or type(artifact.get("size_bytes")) is not int
        or artifact["size_bytes"] < 0
        or not isinstance(artifact.get("sha256"), str)
        or not re.fullmatch(r"[0-9a-f]{64}", artifact["sha256"])
        or not isinstance(artifact.get("content_type"), str)
        or not artifact["content_type"]
        or not re.fullmatch(r"[A-Za-z0-9._/-]+", relative_path)
        or not re.fullmatch(r"[A-Za-z0-9._/-]+", storage_path)
        or ".." in relative_path.split("/")
        or ".." in storage_path.split("/")
        or not re.fullmatch(r"[0-9a-f]{32}", scope)
    ):
        raise RuntimeError(f"{label} descriptor is invalid")
    artifact_parts = relative_path.split("/")
    storage_parts = storage_path.split("/")
    prefix_parts = ["ii-os-agent", scope]
    if (
        storage_parts[:2] != prefix_parts
        or len(storage_parts) != len(artifact_parts) + 3
        or storage_parts[-len(artifact_parts):] != artifact_parts
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", storage_parts[2])
    ):
        raise RuntimeError(f"{label} storage locator is invalid")
    path = os.path.abspath(os.path.join(root, storage_path))
    if os.path.commonpath([root, path]) != root or path == root:
        raise RuntimeError(f"{label} path is outside its durable root")
    relative = os.path.relpath(path, root)
    parts = relative.split(os.sep)
    if any(part in ("", ".", "..") for part in parts):
        raise RuntimeError(f"{label} path is invalid")
    root_fd = os.open(
        root,
        os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0),
    )
    directories = [root_fd]
    try:
        _require_owned_directory(root_fd, label)
        parent_fd = root_fd
        for part in parts[:-1]:
            parent_fd = os.open(
                part,
                os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=parent_fd,
            )
            directories.append(parent_fd)
            _require_owned_directory(parent_fd, label)
        descriptor = os.open(
            parts[-1],
            os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=parent_fd,
        )
        before = os.fstat(descriptor)
        try:
            if (
                not stat.S_ISREG(before.st_mode)
                or before.st_uid != os.geteuid()
                or before.st_nlink != 1
                or before.st_size < 0
                or before.st_size > maximum
            ):
                raise RuntimeError(
                    f"{label} is not a bounded owned regular file"
                )
            encoded = b""
            while len(encoded) <= maximum:
                chunk = os.read(descriptor, min(65536, maximum + 1 - len(encoded)))
                if not chunk:
                    break
                encoded += chunk
            after = os.fstat(descriptor)
        finally:
            os.close(descriptor)
        stable = (
            before.st_dev,
            before.st_ino,
            before.st_size,
            before.st_mtime_ns,
        ) == (
            after.st_dev,
            after.st_ino,
            after.st_size,
            after.st_mtime_ns,
        )
    finally:
        for directory in reversed(directories):
            os.close(directory)
    if (
        not stable
        or len(encoded) > maximum
        or hashlib.sha256(encoded).hexdigest() != artifact.get("sha256")
        or len(encoded) != artifact.get("size_bytes")
    ):
        raise RuntimeError(f"{label} digest is invalid")
    return encoded


def _require_owned_directory(descriptor, label):
    metadata = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.geteuid()
        or stat.S_IMODE(metadata.st_mode) & 0o022
    ):
        raise RuntimeError(f"{label} path is not privately controlled")


def _valid_pull_request(value, dispatch_id):
    if value is None:
        return True
    expected_head = (
        "ii-os-agent/"
        + hashlib.sha256(dispatch_id.encode()).hexdigest()[:32]
    )
    return (
        isinstance(value, dict)
        and set(value) == {
            "repository",
            "repository_id",
            "head",
            "base",
            "head_sha",
            "base_sha",
            "expected_old_head_sha",
        }
        and isinstance(value.get("repository"), str)
        and bool(_REPOSITORY.fullmatch(value["repository"]))
        and type(value.get("repository_id")) is int
        and value["repository_id"] > 0
        and value.get("head") == expected_head
        and value.get("base") == "dev"
        and _valid_sha(value.get("head_sha"))
        and _valid_sha(value.get("base_sha"))
        and (
            value.get("expected_old_head_sha") is None
            or _valid_sha(value.get("expected_old_head_sha"))
        )
    )


def _valid_automation_failure(value, *, allowed):
    if value is None:
        return True
    return bool(
        allowed
        and isinstance(value, dict)
        and set(value) == {"code", "detail"}
        and isinstance(value.get("code"), str)
        and re.fullmatch(r"[a-z][a-z0-9_]{0,99}", value["code"])
        and isinstance(value.get("detail"), str)
        and value["detail"]
        and value["detail"] == value["detail"].strip()
        and len(value["detail"]) <= 500
        and "\n" not in value["detail"]
        and "\r" not in value["detail"]
    )


def _valid_sha(value):
    return (
        isinstance(value, str)
        and len(value) == 40
        and all(character in "0123456789abcdef" for character in value)
    )
