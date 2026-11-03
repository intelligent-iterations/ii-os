#!/usr/bin/env python3
"""Select one compatible iPhone device type and available iOS runtime."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


MAX_INVENTORY_BYTES = 1024 * 1024
VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){0,2}$")
IDENTIFIER_RE = re.compile(r"^com\.apple\.CoreSimulator\.[A-Za-z0-9.-]+$")


class SelectionError(RuntimeError):
    pass


def _read_inventory(path: Path, key: str) -> list[dict[str, Any]]:
    if path.is_symlink() or not path.is_file():
        raise SelectionError(f"{key} inventory is missing, linked, or non-regular")
    raw = path.read_bytes()
    if len(raw) > MAX_INVENTORY_BYTES:
        raise SelectionError(f"{key} inventory exceeds the byte limit")
    try:
        decoded = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SelectionError(f"{key} inventory is not valid UTF-8 JSON") from error
    values = decoded.get(key) if isinstance(decoded, dict) else None
    if not isinstance(values, list) or len(values) > 1024:
        raise SelectionError(f"{key} inventory has an invalid record set")
    if not all(isinstance(value, dict) for value in values):
        raise SelectionError(f"{key} inventory contains a non-object record")
    return values


def _version(value: object, *, default: tuple[int, int, int] | None = None) -> tuple[int, int, int]:
    if value is None and default is not None:
        return default
    if not isinstance(value, str) or not VERSION_RE.fullmatch(value):
        raise SelectionError(f"invalid CoreSimulator version: {value!r}")
    parts = [int(part) for part in value.split(".")]
    if any(part > 65535 for part in parts):
        raise SelectionError(f"CoreSimulator version component is too large: {value!r}")
    return tuple((parts + [0, 0])[:3])  # type: ignore[return-value]


def _identifier(value: object) -> str:
    if not isinstance(value, str) or not IDENTIFIER_RE.fullmatch(value):
        raise SelectionError(f"invalid CoreSimulator identifier: {value!r}")
    return value


def select(runtimes: list[dict[str, Any]], devices: list[dict[str, Any]]) -> dict[str, str]:
    available: list[tuple[tuple[int, int, int], dict[str, Any]]] = []
    for runtime in runtimes:
        identifier = runtime.get("identifier")
        if runtime.get("isAvailable") is not True or not isinstance(identifier, str) or ".iOS-" not in identifier:
            continue
        available.append((_version(runtime.get("version")), runtime))
    if not available:
        raise SelectionError("no available iOS simulator runtime was reported")

    device_ranges: list[
        tuple[tuple[int, int, int], tuple[int, int, int], str, dict[str, Any]]
    ] = []
    for device in devices:
        name = device.get("name")
        family = device.get("productFamily")
        if not isinstance(name, str) or not name.startswith("iPhone"):
            continue
        if family not in (None, "iPhone"):
            continue
        minimum = _version(device.get("minRuntimeVersionString"), default=(0, 0, 0))
        maximum = _version(device.get("maxRuntimeVersionString"), default=(65535, 65535, 65535))
        if maximum < minimum:
            raise SelectionError(f"iPhone device type has an invalid runtime range: {name}")
        device_ranges.append((minimum, maximum, name, device))

    compatible: list[
        tuple[
            tuple[int, int, int],
            tuple[int, int, int],
            str,
            dict[str, Any],
            dict[str, Any],
        ]
    ] = []
    for runtime_version, runtime in available:
        for minimum, maximum, device_name, device in device_ranges:
            if minimum <= runtime_version <= maximum:
                compatible.append(
                    (runtime_version, minimum, device_name, runtime, device)
                )
    if not compatible:
        raise SelectionError("no available iOS runtime has a compatible iPhone device type")
    runtime_version, _, device_name, runtime, device = max(
        compatible,
        key=lambda value: (
            value[0],
            value[1],
            value[2],
            str(value[3].get("identifier", "")),
            str(value[4].get("identifier", "")),
        ),
    )
    runtime_name = runtime.get("name")
    if not isinstance(runtime_name, str) or not runtime_name:
        raise SelectionError("selected iOS runtime has no name")
    return {
        "runtime_identifier": _identifier(runtime.get("identifier")),
        "runtime_name": runtime_name,
        "runtime_version": ".".join(str(value) for value in runtime_version),
        "device_type_identifier": _identifier(device.get("identifier")),
        "device_type_name": device_name,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtimes", type=Path, required=True)
    parser.add_argument("--device-types", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SelectionError("selection output must be a new regular path")
    result = select(
        _read_inventory(args.runtimes, "runtimes"),
        _read_inventory(args.device_types, "devicetypes"),
    )
    args.output.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
