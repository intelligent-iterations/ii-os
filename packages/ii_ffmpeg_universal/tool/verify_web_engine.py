#!/usr/bin/env python3
"""Fail-closed verifier for the release browser FFmpeg JavaScript/Wasm core."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from web_engine_common import WebEngineError, sha256


def _u32(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    for _ in range(5):
        if offset >= len(data):
            raise WebEngineError("truncated Wasm integer")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
    raise WebEngineError("oversized Wasm integer")


def _name(data: bytes, offset: int) -> tuple[str, int]:
    size, offset = _u32(data, offset)
    end = offset + size
    if end > len(data):
        raise WebEngineError("truncated Wasm name")
    return data[offset:end].decode("utf-8"), end


def _limits(data: bytes, offset: int) -> tuple[dict[str, Any], int]:
    flags, offset = _u32(data, offset)
    minimum, offset = _u32(data, offset)
    maximum = None
    if flags & 1:
        maximum, offset = _u32(data, offset)
    return {
        "minimum_pages": minimum,
        "maximum_pages": maximum,
        "shared": bool(flags & 2),
        "memory64": bool(flags & 4),
    }, offset


def _memories(wasm: bytes) -> list[dict[str, Any]]:
    if wasm[:8] != b"\x00asm\x01\x00\x00\x00":
        raise WebEngineError("invalid Wasm header")
    memories: list[dict[str, Any]] = []
    offset = 8
    while offset < len(wasm):
        section = wasm[offset]
        size, offset = _u32(wasm, offset + 1)
        payload = wasm[offset : offset + size]
        if len(payload) != size:
            raise WebEngineError("truncated Wasm section")
        offset += size
        cursor = 0
        if section == 2:
            count, cursor = _u32(payload, cursor)
            for _ in range(count):
                _, cursor = _name(payload, cursor)
                _, cursor = _name(payload, cursor)
                kind = payload[cursor]
                cursor += 1
                if kind == 0:
                    _, cursor = _u32(payload, cursor)
                elif kind == 1:
                    cursor += 1
                    _, cursor = _limits(payload, cursor)
                elif kind == 2:
                    memory, cursor = _limits(payload, cursor)
                    memories.append(memory)
                elif kind == 3:
                    cursor += 2
                else:
                    raise WebEngineError("unknown Wasm import kind")
        elif section == 5:
            count, cursor = _u32(payload, cursor)
            for _ in range(count):
                memory, cursor = _limits(payload, cursor)
                memories.append(memory)
    return memories


def _verify_js(path: Path) -> None:
    if path.stat().st_size > 5 * 1024 * 1024:
        raise WebEngineError("browser core JavaScript exceeds its size limit")
    source = path.read_text(encoding="utf-8")
    required = (
        "function getHeapMax(){return 536870912}",
        "function ffprobe(..._args){const args=[...Module[\"DEFAULT_ARGS_FFPROBE\"]",
        "function _locateFile(path,prefix)",
        "var createFFmpegCore = (() => {",
        "export default createFFmpegCore;",
    )
    forbidden = ("ENVIRONMENT_IS_PTHREAD", "SharedArrayBuffer", "PThread")
    if any(source.count(value) != 1 for value in required):
        raise WebEngineError("browser core JavaScript has an unreviewed shape")
    if any(value in source for value in forbidden):
        raise WebEngineError("browser core JavaScript enables pthread machinery")


def verify(artifacts: Path, lock: dict[str, Any], ledger: dict[str, Any]) -> dict[str, Any]:
    expected_names = set(lock["release_profile"]["artifacts"])
    recorded = {item["path"]: item["sha256"] for item in ledger["artifacts"]}
    if set(recorded) != expected_names:
        raise WebEngineError("browser artifact set does not match the release profile")
    for name, digest in recorded.items():
        path = artifacts / name
        if not path.is_file() or path.is_symlink() or sha256(path) != digest:
            raise WebEngineError(f"browser artifact checksum mismatch: {name}")

    flags = ledger.get("configure_flags", [])
    for flag in lock["release_profile"]["required_flags"]:
        if flag not in flags:
            raise WebEngineError(f"required browser configure flag is absent: {flag}")
    for flag in lock["release_profile"]["forbidden_flags"]:
        if flag in flags:
            raise WebEngineError(f"forbidden browser configure flag is enabled: {flag}")

    core_js = artifacts / "ffmpeg-core.js"
    core_wasm = artifacts / "ffmpeg-core.wasm"
    _verify_js(core_js)
    wasm = core_wasm.read_bytes()
    build_roots = {
        str(artifacts.parent).encode(),
        str(artifacts.parent.resolve()).encode(),
    }
    core_source = core_js.read_bytes()
    if any(root in wasm or root in core_source for root in build_roots):
        raise WebEngineError("browser artifacts embed their disposable build path")
    if len(wasm) > 64 * 1024 * 1024:
        raise WebEngineError("browser Wasm core exceeds its size limit")
    memories = _memories(wasm)
    expected_initial = lock["release_profile"]["initial_memory_bytes"] // 65536
    expected_maximum = lock["release_profile"]["maximum_memory_bytes"] // 65536
    if len(memories) != 1 or memories[0] != {
        "minimum_pages": expected_initial,
        "maximum_pages": expected_maximum,
        "shared": False,
        "memory64": False,
    }:
        raise WebEngineError(f"browser Wasm memory is not exact and bounded: {memories}")
    for marker in (b"--disable-network", b"libvpx", b"libopus", b"subtitles"):
        if marker not in wasm:
            raise WebEngineError(f"browser Wasm capability/config marker is absent: {marker!r}")
    return {
        "schema": 1,
        "engine_version": ledger["engine_version"],
        "single_threaded": True,
        "network_disabled": True,
        "memory": memories[0],
        "artifacts": recorded,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument(
        "--lock",
        type=Path,
        default=Path(__file__).with_name("web_engine_lock.json"),
    )
    args = parser.parse_args()
    try:
        lock = json.loads(args.lock.resolve(strict=True).read_text())
        ledger = json.loads(args.ledger.resolve(strict=True).read_text())
        result = verify(args.artifacts.resolve(strict=True), lock, ledger)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (KeyError, OSError, TypeError, ValueError, WebEngineError) as error:
        print(f"web engine verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
