#!/usr/bin/env python3
"""Generate the reviewed-source values ii-os needs for this agent kit.

Run from the root of the repository that holds the kit (after copying it in):

  python3 scripts/agent_kit_manifest.py trusted-sources --write
      Rewrite .ii-os/agent-trusted-source-manifest.json from the current files.
  python3 scripts/agent_kit_manifest.py trusted-sources --base64
      Print the value for the ii-os setting II_OS_AGENT_TRUSTED_SOURCE_MANIFEST_BASE64.
  python3 scripts/agent_kit_manifest.py runtime-references
      Print the value for the ii-os app build define II_OS_DEFAULT_AGENT_RUNTIME_REFERENCES.
  python3 scripts/agent_kit_manifest.py profile-examples --write
      Rewrite docs/agent-permission-examples/*.json with the current file digests.

ii-os compares every listed file's Git blob with this manifest before it lets
anyone deploy an agent, so regenerate it, review the diff, and update the
ii-os setting in the same change whenever a workflow or script changes.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import sys


WORKFLOWS = [
    "ii-os-agent-permissions.yml",
    "ii-os-agent-permissions-impl.yml",
    "ii-os-agent-task.yml",
    "ii-os-agent-work-ticket.yml",
    "ii-os-codex-auth.yml",
    "ii-os-codex-auth-finalize.yml",
]
NAMESPACES = ["scripts/agent", "scripts/agent/providers", "scripts/agent/worker"]
RUNTIME_FILES = [".ii-os/runtimes/codex-verification.json", ".ii-os/runtimes/execution-binding.json", ".ii-os/agent-controller.json"]
MANIFEST = ".ii-os/agent-trusted-source-manifest.json"
TICKET_PROFILES = {
    "repository-maintainer": {
        "display_name": "Repository maintainer",
        "description": "Implements and verifies repository changes, opens a pull request, and may merge the exact reviewed change to dev.",
        "allowed_actions": [
            "Read and edit files in the selected repository",
            "Run repository tests and validation commands",
            "Create implementation commits and a reviewable pull request",
            "Merge the exact approved pull request to dev",
            "Comment implementation evidence on the existing source ticket",
        ],
        "denied_actions": [
            "Create new GitHub issues or Project items",
            "Set Done or another human-only Project status",
            "Push to public mirrors",
            "Use credentials not declared by this profile",
        ],
        "repository_actions": {"mode": "maintain_dev"},
    },
    "pull-request-author": {
        "display_name": "Pull request author",
        "description": "Implements and verifies repository changes, then opens a pull request for someone else to approve and merge.",
        "allowed_actions": [
            "Read and edit files in the selected repository",
            "Run repository tests and validation commands",
            "Create implementation commits and a reviewable pull request",
            "Comment implementation evidence on the existing source ticket",
        ],
        "denied_actions": [
            "Approve or merge pull requests",
            "Create new GitHub issues or Project items",
            "Set Done or another human-only Project status",
            "Push to public mirrors",
        ],
        "repository_actions": {"mode": "pull_request"},
    },
    "pull-request-reviewer": {
        "display_name": "Pull request reviewer",
        "description": "Reviews an existing pull request and may approve it without publishing code or merging it.",
        "allowed_actions": [
            "Read repository code, pull request changes, and verification results",
            "Approve the exact reviewed pull request",
            "Comment review evidence on the existing source ticket",
        ],
        "denied_actions": [
            "Edit or publish repository files",
            "Create or merge pull requests",
            "Create new GitHub issues or Project items",
            "Set Done or another human-only Project status",
        ],
        "repository_actions": {"mode": "review_pull_requests"},
    },
}
PROFILE_VERSION = "2026-11-04.1"


def git_blob_sha(data):
    # Git names blobs by SHA-1; this reproduces that identity, it is not a security hash.
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()  # nosemgrep: python.lang.security.insecure-hash-algorithms.insecure-hash-algorithm-sha1 -- Git blob identity


def _python_entries(root, directory):
    names = []
    for entry in sorted(os.listdir(root / directory)):
        path = root / directory / entry
        if entry == "__pycache__" or entry.endswith(".pyc"):
            continue
        if path.is_dir() and not path.is_symlink():
            if f"{directory}/{entry}" not in NAMESPACES:
                raise SystemExit(f"{directory}/{entry}: only reviewed namespaces may be directories here")
            continue
        if path.is_symlink() or not path.is_file():
            raise SystemExit(f"{directory}/{entry}: only regular files may live in a reviewed namespace")
        if entry.endswith((".py", ".pyo", ".pyd", ".so")):
            names.append(entry)
    return names


def trusted_sources(root):
    paths = [f".github/workflows/{name}" for name in WORKFLOWS] + list(RUNTIME_FILES)
    for directory in NAMESPACES:
        for entry in sorted(os.listdir(root / directory)):
            path = root / directory / entry
            if path.is_file() and not path.is_symlink() and entry != "__pycache__" and not entry.endswith(".pyc"):
                paths.append(f"{directory}/{entry}")
    blob_shas, executable = {}, []
    for relative in paths:
        path = root / relative
        if path.is_symlink() or not path.is_file():
            raise SystemExit(f"{relative} is missing or not a regular file")
        blob_shas[relative] = git_blob_sha(path.read_bytes())
        if path.stat().st_mode & 0o111:
            executable.append(relative)
    namespaces = {directory: _python_entries(root, directory) for directory in NAMESPACES}
    return {"schema_version": 1, "blob_shas": dict(sorted(blob_shas.items())), "executable_paths": sorted(executable),
            "python_import_namespaces": namespaces}


def encode(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def runtime_references(root):
    binding = ".ii-os/runtimes/execution-binding.json"
    references = {}
    for profile_id in TICKET_PROFILES:
        configuration = f".ii-os/runtimes/{profile_id}.json"
        references[profile_id] = {
            "configuration": {"path": configuration, "sha256": hashlib.sha256((root / configuration).read_bytes()).hexdigest()},
            "execution_binding": {"path": binding, "sha256": hashlib.sha256((root / binding).read_bytes()).hexdigest()},
        }
    return references


def profile_examples(root):
    references = runtime_references(root)
    return {profile_id: {"schema_version": 4, "engine": "codex", "id": profile_id, **shape, "version": PROFILE_VERSION,
                         "runtime": references[profile_id], "workflow": {"file": "ii-os-agent-task.yml", "ref": "dev"}}
            for profile_id, shape in TICKET_PROFILES.items()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=["trusted-sources", "runtime-references", "profile-examples"])
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--base64", action="store_true")
    parser.add_argument("--root", default=".")
    arguments = parser.parse_args(argv)
    root = Path(arguments.root).resolve()
    if arguments.command == "trusted-sources":
        encoded = encode(trusted_sources(root))
        if arguments.write:
            (root / MANIFEST).write_bytes(encoded)
        elif arguments.base64:
            print(base64.b64encode((root / MANIFEST).read_bytes()).decode())
        else:
            sys.stdout.write(encoded.decode())
    elif arguments.command == "runtime-references":
        print(json.dumps(runtime_references(root), sort_keys=True, separators=(",", ":")))
    else:
        examples = profile_examples(root)
        if arguments.write:
            directory = root / "docs" / "agent-permission-examples"
            directory.mkdir(parents=True, exist_ok=True)
            for profile_id, value in examples.items():
                (directory / f"{profile_id}.json").write_bytes(encode(value))
        else:
            sys.stdout.write(json.dumps(examples, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
