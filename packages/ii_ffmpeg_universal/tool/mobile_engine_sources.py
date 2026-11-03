"""Locked mobile source provenance and notice generation."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from mobile_engine_common import BuildError, capture, sha256


_LICENSE_RE = re.compile(
    r"(^|/)(copying|copyright|license|notice)([._-].*)?$", re.I
)


def _license_files(repository: Path) -> list[Path]:
    names = capture(["git", "ls-files"], repository).splitlines()
    return [repository / name for name in names if _LICENSE_RE.search(name)]


def source_record(
    name: str,
    repository: str,
    revision: str,
    path: Path,
    declared_license_paths: list[str] | None = None,
) -> dict[str, Any]:
    licenses = []
    license_files = (
        [path / relative for relative in declared_license_paths]
        if declared_license_paths
        else _license_files(path)
    )
    for license_path in license_files:
        if (
            not license_path.is_file()
            or path.resolve() not in license_path.resolve().parents
        ):
            raise BuildError(f"invalid declared license path for {name}: {license_path}")
        licenses.append(
            {
                "path": license_path.relative_to(path).as_posix(),
                "sha256": sha256(license_path),
            }
        )
    if not licenses:
        raise BuildError(f"source repository has no tracked license file: {name}")
    return {
        "name": name,
        "repository": repository,
        "revision": revision,
        "licenses": licenses,
    }


def prepare_source_destination(recipe: Path, name: str) -> Path:
    if name == "config":
        destination = recipe / ".tmp" / "source" / name
    else:
        destination = recipe / "src" / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    return destination


def write_notices(
    records: list[dict[str, Any]], roots: dict[str, Path], path: Path
) -> None:
    with path.open("w", encoding="utf-8") as output:
        output.write("II minimal mobile FFmpeg engine third-party notices\n\n")
        for record in records:
            output.write(
                f"== {record['name']} ==\nSource: {record['repository']}\n"
                f"Revision: {record['revision']}\n\n"
            )
            root = roots[record["name"]]
            for license_info in record["licenses"]:
                relative = license_info["path"]
                output.write(f"--- {relative} ---\n")
                output.write(
                    (root / relative).read_text(encoding="utf-8", errors="replace")
                )
                output.write("\n\n")
