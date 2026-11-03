#!/usr/bin/env python3
"""Create a deterministic archive of one already-validated app artifact."""

from __future__ import annotations

import argparse
import glob
import os
import stat
import zipfile
from pathlib import Path

from application_artifact_manifest import _checked_link, checked_files


def resolve_unique(pattern: str) -> Path:
    matches = [Path(value) for value in glob.glob(pattern, recursive=False)]
    if len(matches) != 1:
        raise RuntimeError(
            f"Application artifact pattern needs exactly one match: {pattern}"
        )
    return matches[0]


def archive_artifact(pattern: str, destination: Path) -> None:
    root = resolve_unique(pattern)
    files = checked_files(root)
    if destination.exists() or destination.is_symlink():
        raise RuntimeError("Application archive output must be new")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(
        destination,
        "x",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        allowZip64=True,
    ) as archive:
        for source in files:
            relative = (
                source.name
                if root.is_file()
                else (Path(root.name) / source.relative_to(root)).as_posix()
            )
            info = zipfile.ZipInfo(relative, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            if source.is_symlink():
                target = _checked_link(root, source).encode("utf-8")
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(info, target)
            else:
                mode = os.stat(source, follow_symlinks=False).st_mode
                info.create_system = 3
                info.external_attr = mode << 16
                with source.open("rb") as input_file, archive.open(info, "w") as output:
                    while chunk := input_file.read(1024 * 1024):
                        output.write(chunk)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glob", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    archive_artifact(args.glob, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
