"""Bounded failure diagnostics for the mobile engine build."""

from __future__ import annotations

import sys
from pathlib import Path


BUILD_LOG_TAIL_BYTES = 1024 * 1024
CONFIG_LOG_TAIL_BYTES = 256 * 1024
CONFIG_LOG_SOURCE_LIMIT = 128


def print_bounded_build_log(workspace: Path) -> None:
    path = workspace / "ffmpeg-kit" / "build.log"
    if not path.is_file() or path.is_symlink():
        return
    try:
        with path.open("rb") as stream:
            size = stream.seek(0, 2)
            start = max(0, size - BUILD_LOG_TAIL_BYTES)
            stream.seek(start)
            payload = stream.read(BUILD_LOG_TAIL_BYTES)
    except OSError:
        return
    if start:
        newline = payload.find(b"\n")
        payload = payload[newline + 1 :] if newline >= 0 else b""
    lines = payload.decode("utf-8", errors="replace").splitlines()
    print("--- bounded ffmpeg-kit build.log tail ---", file=sys.stderr)
    for line in lines[-240:]:
        print(line[:4000], file=sys.stderr)
    print("--- end bounded ffmpeg-kit build.log tail ---", file=sys.stderr)


def print_bounded_config_logs(workspace: Path) -> None:
    source_root = workspace / "ffmpeg-kit" / "src"
    if not source_root.is_dir() or source_root.is_symlink():
        return
    candidates: list[Path] = []
    try:
        for source in source_root.iterdir():
            if len(candidates) >= CONFIG_LOG_SOURCE_LIMIT:
                break
            config_log = source / "config.log"
            if config_log.is_symlink() or not config_log.is_file():
                continue
            candidates.append(config_log)
    except OSError:
        return
    for path in sorted(candidates):
        try:
            with path.open("rb") as stream:
                size = stream.seek(0, 2)
                start = max(0, size - CONFIG_LOG_TAIL_BYTES)
                stream.seek(start)
                payload = stream.read(CONFIG_LOG_TAIL_BYTES)
        except OSError:
            continue
        if start:
            newline = payload.find(b"\n")
            payload = payload[newline + 1 :] if newline >= 0 else b""
        relative = path.relative_to(workspace / "ffmpeg-kit")
        print(f"--- bounded {relative.as_posix()} tail ---", file=sys.stderr)
        for line in payload.decode("utf-8", errors="replace").splitlines()[-160:]:
            print(line[:4000], file=sys.stderr)
        print(f"--- end bounded {relative.as_posix()} tail ---", file=sys.stderr)
