"""Canonical validation for ii-os runtime agent permission profiles.

An executable profile is schema version 4: it approves references to the
runtime configuration and execution binding files by path and sha256, never a
copy of their CPU, memory, image, command or credential policy. The installed
agent runtime validates those exact files at execution time.
"""

import hashlib
import json
import re


SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
RUNTIME_REFERENCE_PATH = re.compile(
    r"^\.ii-os/runtimes/[A-Za-z0-9][A-Za-z0-9._/-]{0,180}\.json$"
)
REPOSITORY_ACTION_MODES = {
    "maintain_dev",
    "pull_request",
    "review_pull_requests",
}
AGENT_WORKFLOW = {"file": "ii-os-agent-task.yml", "ref": "dev"}
PROFILE_KEYS = {
    "schema_version",
    "engine",
    "id",
    "version",
    "display_name",
    "description",
    "allowed_actions",
    "denied_actions",
    "repository_actions",
    "runtime",
    "workflow",
}


def _exact_keys(value, allowed, label):
    if not isinstance(value, dict) or set(value) != set(allowed):
        raise SystemExit(f"{label} has missing or unknown fields")


def validate_profile_shape(profile):
    if not isinstance(profile, dict):
        raise SystemExit("permission profile must be an object")
    schema_version = profile.get("schema_version")
    if type(schema_version) is not int or schema_version != 4:
        raise SystemExit("profile identity or schema mismatch")
    _exact_keys(profile, PROFILE_KEYS, "permission profile")
    _exact_keys(profile.get("repository_actions"), {"mode"}, "repository actions")
    runtime = profile.get("runtime")
    _exact_keys(
        runtime, {"configuration", "execution_binding"}, "runtime references"
    )
    paths = set()
    for reference in runtime.values():
        _exact_keys(reference, {"path", "sha256"}, "runtime reference")
        path = reference["path"]
        if (
            not isinstance(path, str)
            or not RUNTIME_REFERENCE_PATH.fullmatch(path)
            or ".." in path
            or "//" in path
            or path in paths
            or not isinstance(reference["sha256"], str)
            or not re.fullmatch(r"[a-f0-9]{64}", reference["sha256"])
        ):
            raise SystemExit("runtime file reference is invalid")
        paths.add(path)
    _exact_keys(profile.get("workflow"), {"file", "ref"}, "workflow policy")


def validate_executable_profile(profile, *, expected_id=None):
    validate_profile_shape(profile)
    if (
        not isinstance(profile.get("id"), str)
        or not SAFE_NAME.fullmatch(profile["id"])
        or not isinstance(profile.get("version"), str)
        or not SAFE_NAME.fullmatch(profile["version"])
        or (expected_id is not None and profile.get("id") != expected_id)
    ):
        raise SystemExit("profile identity or schema mismatch")
    for field, maximum in (("display_name", 100), ("description", 1000)):
        value = profile.get(field)
        if (
            not isinstance(value, str)
            or value != value.strip()
            or not value
            or len(value) > maximum
        ):
            raise SystemExit(f"invalid {field}")
    for field in ("allowed_actions", "denied_actions"):
        values = profile.get(field)
        if (
            not isinstance(values, list)
            or any(
                not isinstance(value, str)
                or value != value.strip()
                or not value
                or len(value) > 300
                for value in values
            )
            or len(set(values)) != len(values)
        ):
            raise SystemExit(f"invalid {field}")
    if not profile["allowed_actions"]:
        raise SystemExit("allowed_actions must not be empty")
    if profile["repository_actions"].get("mode") not in REPOSITORY_ACTION_MODES:
        raise SystemExit("invalid repository actions")
    if profile["engine"] != "codex":
        raise SystemExit("runtime controller requires the supported Codex harness")
    if profile["workflow"] != AGENT_WORKFLOW:
        raise SystemExit("profile workflow must target dev")


def canonical_profile_digest(profile):
    return hashlib.sha256(json.dumps(
        profile,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode()).hexdigest()
