#!/usr/bin/env python3
"""Small deterministic process, source, and archive helpers for mobile builds."""

from __future__ import annotations

import hashlib
import subprocess
import zipfile
from pathlib import Path


class BuildError(RuntimeError):
    pass


def run(command: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(command), flush=True)
    process = subprocess.run(command, cwd=cwd, text=True, check=False)
    if process.returncode:
        raise BuildError(f"command failed with exit {process.returncode}")


def capture(command: list[str], cwd: Path | None = None) -> str:
    process = subprocess.run(
        command, cwd=cwd, text=True, check=False, capture_output=True
    )
    if process.returncode:
        raise BuildError(
            f"command failed ({' '.join(command)}): {process.stderr.strip()}"
        )
    return process.stdout.strip()


def clone_exact(repository: str, revision: str, destination: Path) -> None:
    destination.mkdir()
    run(["git", "init", "--quiet", "--initial-branch=dev"], destination)
    run(["git", "remote", "add", "origin", repository], destination)
    run(["git", "fetch", "--quiet", "--depth", "1", "origin", revision], destination)
    run(["git", "reset", "--quiet", "--hard", "FETCH_HEAD"], destination)
    branch = capture(["git", "branch", "--show-current"], destination)
    if branch != "dev":
        raise BuildError(f"source checkout moved off dev for {repository}: {branch}")
    actual = capture(["git", "rev-parse", "HEAD"], destination)
    if actual != revision:
        raise BuildError(f"revision mismatch for {repository}: {actual}")


def replace_once(path: Path, old: str, new: str) -> None:
    content = path.read_text(encoding="utf-8")
    if content.count(old) != 1:
        raise BuildError(f"expected one patch location in {path}: {old!r}")
    path.write_text(content.replace(old, new), encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def deterministic_zip(source: Path, destination: Path) -> None:
    with zipfile.ZipFile(
        destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for path in sorted(source.rglob("*")):
            if path.is_dir():
                continue
            relative = Path(source.name) / path.relative_to(source)
            info = zipfile.ZipInfo(relative.as_posix(), (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (path.stat().st_mode & 0xFFFF) << 16
            archive.writestr(info, path.read_bytes())
