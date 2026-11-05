#!/usr/bin/env python3
"""Resolve the reviewed implementation and source commits for workflow proofs.

II_OS_WORKFLOW_REPOSITORY is required and has no default. A workflow in a
separate implementation repository also binds II_OS_WORKFLOW_REPO_ROOT,
II_OS_IMPLEMENTATION_SHA, and II_OS_SOURCE_SHA together.
"""

from __future__ import annotations

import os
import re


_SHA = re.compile(r"^[0-9a-f]{40}$")
_REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
_SPLIT_FIELDS = (
    "II_OS_WORKFLOW_REPO_ROOT",
    "II_OS_IMPLEMENTATION_SHA",
    "II_OS_SOURCE_SHA",
)


def _required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


def workflow_source_identity() -> dict[str, str]:
    workflow_repository = _required("II_OS_WORKFLOW_REPOSITORY")
    if _REPOSITORY.fullmatch(workflow_repository) is None:
        raise RuntimeError("workflow repository must be an owner/repository name")
    configured = [name for name in _SPLIT_FIELDS if os.environ.get(name)]
    if configured and len(configured) != len(_SPLIT_FIELDS):
        raise RuntimeError(
            "workflow root, implementation SHA, and source SHA must be "
            "configured together"
        )

    github_sha = _required("GITHUB_SHA")
    github_repository = _required("GITHUB_REPOSITORY")
    if configured:
        implementation_sha = _required("II_OS_IMPLEMENTATION_SHA")
        source_sha = _required("II_OS_SOURCE_SHA")
    else:
        implementation_sha = github_sha
        source_sha = github_sha

    for name, value in (
        ("implementation commit", implementation_sha),
        ("source commit", source_sha),
    ):
        if _SHA.fullmatch(value) is None:
            raise RuntimeError(f"{name} must be an exact lowercase Git SHA")
    if github_sha != implementation_sha:
        raise RuntimeError("workflow commit does not match the implementation commit")
    if github_repository != workflow_repository:
        raise RuntimeError(
            "workflow repository does not match the configured repository"
        )

    return {
        "implementation_commit": implementation_sha,
        "source_commit": source_sha,
        "workflow_repository": workflow_repository,
    }
