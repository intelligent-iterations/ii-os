#!/usr/bin/env python3
"""Check that a runner's model folder holds what a request needs.

The kit never downloads weights. Each runner ships `runners/<runner>/models.json`
listing the files it reads (relative path, size, sha256 when known, upstream
source and license). The operator fetches them once into
`${II_OS_MODEL_ROOT}/<runner>/`, which the container mounts read-only at
`/models`. Before a run, `check` confirms the files of the requested profile
are present, regular, sized as listed and resolve inside that folder (a symlink
that points elsewhere cannot resolve inside the container).

    python3 scripts/ii_os_model_folder.py check --manifest runners/comfyui-image/models.json \
        --model-root "$II_OS_MODEL_ROOT" --profile z-image-turbo
    python3 scripts/ii_os_model_folder.py verify ...   # also hashes every file with a sha256
    python3 scripts/ii_os_model_folder.py list --manifest runners/comfyui-image/models.json

With `--work-dir <run dir> --failure-code <code>`, a folder that is missing
files also writes `<run dir>/out/failure.json`, so the failure report names a
missing model with that code (the workflow lists it in `runner-error-codes`).
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
from typing import Any, Mapping, Sequence

RUNNER = re.compile(r"^[a-z0-9][a-z0-9-]{1,40}$")
PROFILE = re.compile(r"^[a-z0-9][a-z0-9.-]{0,63}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
PATH_SEGMENT = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.+-]{0,199}$")
ERROR_CODE = re.compile(r"^[A-Za-z0-9_.:-]{1,100}$")


@dataclass(frozen=True)
class ModelFile:
    path: str
    kind: str
    size_bytes: int | None
    sha256: str | None
    source: str
    license: str
    optional: bool
    note: str


@dataclass(frozen=True)
class Manifest:
    runner: str
    profiles: dict[str, list[str]]
    files: dict[str, ModelFile]

    @classmethod
    def parse(cls, value: Any) -> "Manifest":
        if not isinstance(value, dict) or value.get("schema_version") != 1:
            raise ValueError("models.json must declare schema_version 1")
        runner = value.get("runner")
        if not isinstance(runner, str) or not RUNNER.fullmatch(runner):
            raise ValueError("models.json runner must be a lowercase runner folder name")
        files: dict[str, ModelFile] = {}
        for entry in value.get("files") or []:
            item = _model_file(entry)
            if item.path in files:
                raise ValueError(f"models.json lists {item.path} twice")
            files[item.path] = item
        profiles = value.get("profiles")
        if profiles is None and files:
            # A runner that always reads the same files may omit profiles.
            profiles = {"default": [path for path, item in files.items() if not item.optional]}
        if not isinstance(profiles, dict) or not profiles:
            raise ValueError("models.json must define at least one profile")
        for name, paths in profiles.items():
            if not isinstance(name, str) or not PROFILE.fullmatch(name):
                raise ValueError(f"models.json profile name {name!s:.40} is invalid")
            if not isinstance(paths, list) or any(path not in files for path in paths):
                missing = [path for path in paths or [] if path not in files] if isinstance(paths, list) else []
                raise ValueError(f"profile {name} names files models.json does not list: {', '.join(map(str, missing))}")
        return cls(runner, {name: list(paths) for name, paths in profiles.items()}, files)


def _model_file(entry: Any) -> ModelFile:
    if not isinstance(entry, dict):
        raise ValueError("every models.json file entry must be an object")
    path = entry.get("path")
    if not isinstance(path, str) or not _relative(path):
        raise ValueError(f"{path!s:.80} is not a relative path inside the runner folder")
    kind = entry.get("kind", "file")
    if kind not in {"file", "directory"}:
        raise ValueError(f"{path}: kind must be file or directory")
    size = entry.get("size_bytes")
    if size is not None and (isinstance(size, bool) or not isinstance(size, int) or size <= 0):
        raise ValueError(f"{path}: size_bytes must be a positive integer or null")
    digest = entry.get("sha256")
    if digest is not None and (not isinstance(digest, str) or not SHA256.fullmatch(digest)):
        raise ValueError(f"{path}: sha256 must be 64 lowercase hex characters or null")
    if kind == "directory" and (size is not None or digest is not None):
        raise ValueError(f"{path}: a directory entry has no size_bytes or sha256")
    source = _source(path, entry.get("source"))
    license_name = entry.get("license")
    if not isinstance(license_name, str) or not license_name.strip():
        raise ValueError(f"{path}: license must name the upstream license (or 'unstated')")
    optional = entry.get("optional", False)
    note = entry.get("note", "")
    if not isinstance(optional, bool) or not isinstance(note, str):
        raise ValueError(f"{path}: optional must be a boolean and note a string")
    return ModelFile(path, kind, size, digest, source, license_name, optional, note)


def _source(path: str, value: Any) -> str:
    """An https URL, or {repository, revision (full commit), filename}."""
    if isinstance(value, str) and value.startswith("https://"):
        return value
    if isinstance(value, dict):
        repository, revision, filename = value.get("repository"), value.get("revision"), value.get("filename")
        if (
            isinstance(repository, str)
            and repository.startswith("https://")
            and isinstance(revision, str)
            and re.fullmatch(r"[0-9a-f]{40}", revision)
            and isinstance(filename, str)
            and filename
        ):
            return f"{repository} (revision {revision}, {filename})"
    raise ValueError(f"{path}: source must be the https URL the file comes from, or a repository pinned to a commit")


def _relative(path: str) -> bool:
    if not path or "\\" in path or path.startswith("/"):
        return False
    parts = PurePosixPath(path).parts
    return path == "/".join(parts) and all(PATH_SEGMENT.fullmatch(part) for part in parts)


@dataclass
class Report:
    folder: Path
    problems: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def check(model_root: Path, manifest: Manifest, profile: str, *, verify_sha256: bool = False) -> Report:
    if profile not in manifest.profiles:
        raise ValueError(f"runner {manifest.runner} has no model profile {profile}; it has {', '.join(sorted(manifest.profiles))}")
    folder = model_root / manifest.runner
    report = Report(folder)
    if folder.is_symlink() or not folder.is_dir():
        report.problems.append(f"model folder {folder} is missing; create it and fetch the files listed in runners/{manifest.runner}/models.json")
        return report
    real_folder = folder.resolve()
    for relative in manifest.profiles[profile]:
        item = manifest.files[relative]
        problem = _check_one(folder / relative, real_folder, item, verify_sha256)
        if problem is None:
            continue
        if item.optional and problem.endswith("is missing"):
            report.notes.append(f"optional {problem}; the runner works without it")
        else:
            report.problems.append(problem)
    return report


def _check_one(path: Path, real_folder: Path, item: ModelFile, verify_sha256: bool) -> str | None:
    if not path.exists():
        return f"{item.path} is missing"
    resolved = path.resolve()
    if resolved != real_folder and real_folder not in resolved.parents:
        return f"{item.path} resolves outside the runner folder, so it will not resolve inside the container"
    if item.kind == "directory":
        if not resolved.is_dir():
            return f"{item.path} must be a folder"
        if not any(resolved.iterdir()):
            return f"{item.path} is an empty folder"
        return None
    info = resolved.stat()
    if not stat.S_ISREG(info.st_mode):
        return f"{item.path} is not a regular file"
    if item.size_bytes is not None and info.st_size != item.size_bytes:
        return f"{item.path} size is {info.st_size} bytes; models.json expects {item.size_bytes}"
    if verify_sha256 and item.sha256 is not None and _sha256(resolved) != item.sha256:
        return f"{item.path} sha256 does not match models.json"
    return None


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_failure(work_dir: Path, code: str) -> Path:
    """Write `out/failure.json` in the run directory, never through a symlink."""
    out = work_dir / "out"
    if out.is_symlink() or not out.is_dir():
        raise ValueError(f"{out} is not the run's own out folder")
    path = out / "failure.json"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(json.dumps({"errorCode": code}) + "\n")
    return path


def load_manifest(path: Path) -> Manifest:
    return Manifest.parse(json.loads(path.read_text(encoding="utf-8")))


def main(argv: Sequence[str], env: Mapping[str, str] | None = None) -> int:
    env = os.environ if env is None else env
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("check", "verify"):
        child = sub.add_parser(command)
        child.add_argument("--manifest", type=Path, required=True)
        child.add_argument("--model-root", type=Path, default=Path(env.get("II_OS_MODEL_ROOT", "") or "."))
        child.add_argument("--profile", required=True)
        child.add_argument("--work-dir", type=Path)
        child.add_argument("--failure-code")
    listing = sub.add_parser("list")
    listing.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args(list(argv))
    manifest = load_manifest(args.manifest)
    if args.command == "list":
        for item in manifest.files.values():
            size = "unknown size" if item.size_bytes is None else f"{item.size_bytes} bytes"
            flag = " (optional)" if item.optional else ""
            print(f"{item.path}{flag}\t{size}\t{item.license}\t{item.source}")
        return 0
    if args.failure_code is not None:
        if not ERROR_CODE.fullmatch(args.failure_code):
            raise ValueError("the failure code is not a stable identifier")
        if args.work_dir is None:
            raise ValueError("--failure-code needs --work-dir, the run directory it reports through")
    report = check(args.model_root, manifest, args.profile, verify_sha256=args.command == "verify")
    for note in report.notes:
        print(f"::notice title=ii-os model folder::{note}")
    if report.problems:
        for problem in report.problems:
            print(f"::error title=ii-os model folder::{problem}")
        print(f"See runners/{manifest.runner}/README.md for where each file comes from.", file=sys.stderr)
        if args.failure_code is not None:
            write_failure(args.work_dir, args.failure_code)
        return 1
    print(f"model folder {report.folder} has every file profile {args.profile} needs")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (OSError, ValueError) as error:
        print(f"::error title=ii-os model folder::{error}")
        raise SystemExit(2) from None
