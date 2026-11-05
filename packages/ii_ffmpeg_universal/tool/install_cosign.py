#!/usr/bin/env python3
"""Install one reviewed Cosign binary by exact release digest."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import urllib.request
from pathlib import Path


MAX_COSIGN_BYTES = 256 * 1024 * 1024


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--lock", type=Path, default=Path(__file__).with_name("cosign_lock.json")
    )
    args = parser.parse_args()
    if not args.output.is_absolute() or args.output.exists() or args.output.is_symlink():
        raise RuntimeError("Cosign output must be a new absolute path")
    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    identity = f"{platform.system().lower()}-{platform.machine().lower()}"
    record = lock["platforms"].get(identity)
    if lock.get("schema") != 1 or not isinstance(record, dict):
        raise RuntimeError(f"Unsupported Cosign host: {identity}")
    request = urllib.request.Request(record["url"], headers={"Accept": "application/octet-stream"})
    digest = hashlib.sha256()
    total = 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with urllib.request.urlopen(request, timeout=60) as response, args.output.open(
            "xb"
        ) as output:
            while chunk := response.read(1024 * 1024):
                total += len(chunk)
                if total > MAX_COSIGN_BYTES:
                    raise RuntimeError("Cosign binary exceeds the byte limit")
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != record["sha256"]:
            raise RuntimeError("Cosign binary checksum mismatch")
        os.chmod(args.output, 0o500)
    except BaseException:
        args.output.unlink(missing_ok=True)
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
