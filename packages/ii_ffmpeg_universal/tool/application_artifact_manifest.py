#!/usr/bin/env python3
"""Hash one exact application build output into a bounded release manifest."""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
from pathlib import Path


MAX_FILES = 20_000
MAX_FILE_BYTES = 2 * 1024 * 1024 * 1024
MAX_TOTAL_BYTES = 8 * 1024 * 1024 * 1024
MAX_LINK_BYTES = 4096


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def _checked_link(root: Path, path: Path) -> str:
    target = os.readlink(path)
    encoded = target.encode("utf-8")
    if not target or len(encoded) > MAX_LINK_BYTES or Path(target).is_absolute():
        raise RuntimeError(f"Application artifact contains an unsafe link: {path}")
    try:
        resolved = (path.parent / target).resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise RuntimeError(f"Application artifact contains a broken link: {path}") from error
    root_resolved = root.resolve(strict=True)
    if resolved != root_resolved and root_resolved not in resolved.parents:
        raise RuntimeError(f"Application artifact link escapes its bundle: {path}")
    return target


def checked_files(root: Path) -> list[Path]:
    if root.is_symlink() or not root.exists():
        raise RuntimeError(f"Application artifact is missing or linked: {root}")
    if root.is_file():
        return [root]
    if not root.is_dir():
        raise RuntimeError(f"Application artifact is not regular: {root}")
    files: list[Path] = []
    for directory, names, filenames in os.walk(root, followlinks=False):
        current = Path(directory)
        linked_directories = [name for name in names if (current / name).is_symlink()]
        for name in linked_directories:
            path = current / name
            _checked_link(root, path)
            files.append(path)
            if len(files) > MAX_FILES:
                raise RuntimeError("Application artifact file count exceeds limit")
        names[:] = [name for name in names if name not in linked_directories]
        for name in filenames:
            path = current / name
            if path.is_symlink():
                _checked_link(root, path)
            elif not path.is_file():
                raise RuntimeError(f"Application artifact contains a non-file: {path}")
            files.append(path)
            if len(files) > MAX_FILES:
                raise RuntimeError("Application artifact file count exceeds limit")
    if not files:
        raise RuntimeError("Application artifact contains no files")
    return sorted(files)


def resolve_unique(pattern: str) -> Path:
    matches = [Path(value) for value in glob.glob(pattern, recursive=False)]
    if len(matches) != 1:
        raise RuntimeError(
            f"Application artifact pattern needs exactly one match: {pattern}"
        )
    return matches[0]


def build_manifest(label: str, pattern: str) -> dict[str, object]:
    root = resolve_unique(pattern)
    files = checked_files(root)
    total = 0
    entries: list[dict[str, object]] = []
    for path in files:
        link_target = _checked_link(root, path) if path.is_symlink() else None
        link_bytes = link_target.encode("utf-8") if link_target is not None else None
        size = len(link_bytes) if link_bytes is not None else path.stat().st_size
        if size > MAX_FILE_BYTES:
            raise RuntimeError(f"Application artifact file exceeds limit: {path}")
        total += size
        if total > MAX_TOTAL_BYTES:
            raise RuntimeError("Application artifact bytes exceed aggregate limit")
        relative = path.name if root.is_file() else path.relative_to(root).as_posix()
        entry: dict[str, object] = {
            "path": relative,
            "size_bytes": size,
            "sha256": (
                hashlib.sha256(link_bytes).hexdigest()
                if link_bytes is not None
                else digest(path)
            ),
            "type": "symlink" if link_target is not None else "file",
        }
        if link_target is not None:
            entry["target"] = link_target
        entries.append(entry)
    return {
        "schema": 1,
        "label": label,
        "source_name": root.name,
        "file_count": len(entries),
        "total_bytes": total,
        "files": entries,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", required=True)
    parser.add_argument("--glob", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.is_symlink() or args.output.exists():
        raise RuntimeError("Application artifact manifest output must be new")
    manifest = build_manifest(args.label, args.glob)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
