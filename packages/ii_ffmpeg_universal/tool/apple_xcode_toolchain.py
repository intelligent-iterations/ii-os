"""Attest the Xcode and iPhoneOS SDK inputs used by mobile compilation."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Callable

from apple_build_tool_tree import TreeAttestationError, attest_tree_bounded


MAX_SDK_FILE_BYTES = 4 * 1024 * 1024 * 1024
MAX_SDK_TOTAL_BYTES = 64 * 1024 * 1024 * 1024
MAX_SDK_ENTRIES = 1_000_000
XCODE_TOOL_NAMES = (
    "ar",
    "clang",
    "clang++",
    "ld",
    "libtool",
    "lipo",
    "nm",
    "ranlib",
    "strip",
    "xcodebuild",
)


class XcodeToolchainError(RuntimeError):
    pass


def _resolve_sdk_directory(sdk: Path, developer_dir: Path) -> Path:
    if not sdk.is_absolute():
        raise XcodeToolchainError("iPhoneOS SDK directory is unsafe")
    try:
        if sdk.is_symlink():
            target = Path(os.readlink(sdk))
            if not target.as_posix() or target.is_absolute():
                raise XcodeToolchainError("iPhoneOS SDK directory is unsafe")
        elif not sdk.is_dir():
            raise XcodeToolchainError("iPhoneOS SDK directory is unsafe")
        resolved = sdk.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise XcodeToolchainError("iPhoneOS SDK directory is unsafe") from error
    if not resolved.is_dir():
        raise XcodeToolchainError("iPhoneOS SDK directory is unsafe")
    if developer_dir not in resolved.parents:
        raise XcodeToolchainError("iPhoneOS SDK is outside the selected Xcode")
    return resolved


def attest_xcode_toolchain(
    capture: Callable[[list[str]], str],
    sha256: Callable[[Path], str],
) -> dict[str, Any]:
    xcode_select = Path("/usr/bin/xcode-select")
    xcrun = Path("/usr/bin/xcrun")
    for launcher in (xcode_select, xcrun):
        if launcher.is_symlink() or not launcher.is_file():
            raise XcodeToolchainError("Xcode launcher is unsafe")
    developer_dir = Path(capture([str(xcode_select), "-p"]))
    if (
        not developer_dir.is_absolute()
        or developer_dir.is_symlink()
        or not developer_dir.is_dir()
    ):
        raise XcodeToolchainError("Xcode developer directory is unsafe")
    developer_dir = developer_dir.resolve(strict=True)
    sdk = _resolve_sdk_directory(
        Path(capture([str(xcrun), "--sdk", "iphoneos", "--show-sdk-path"])),
        developer_dir,
    )
    settings = next(
        (
            path
            for path in (sdk / "SDKSettings.json", sdk / "SDKSettings.plist")
            if path.is_file() and not path.is_symlink()
        ),
        None,
    )
    if settings is None:
        raise XcodeToolchainError("iPhoneOS SDK settings are missing")
    tools: list[dict[str, str]] = []
    tool_paths: dict[str, Path] = {}
    for name in XCODE_TOOL_NAMES:
        path = Path(
            capture([str(xcrun), "--sdk", "iphoneos", "--find", name])
        ).resolve(strict=True)
        if not path.is_file() or path.is_symlink() or developer_dir not in path.parents:
            raise XcodeToolchainError(f"Xcode build tool is unsafe: {name}")
        tools.append(
            {
                "name": name,
                "relative_path": path.relative_to(developer_dir).as_posix(),
                "sha256": sha256(path),
            }
        )
        tool_paths[name] = path
    try:
        sdk_tree = attest_tree_bounded(
            sdk,
            max_file_bytes=MAX_SDK_FILE_BYTES,
            max_total_bytes=MAX_SDK_TOTAL_BYTES,
            max_entries=MAX_SDK_ENTRIES,
        )
    except TreeAttestationError as error:
        raise XcodeToolchainError(str(error)) from error
    return {
        "developer_dir": developer_dir.as_posix(),
        "xcode_version": capture([str(tool_paths["xcodebuild"]), "-version"]),
        "iphoneos_sdk_relative_path": sdk.relative_to(developer_dir).as_posix(),
        "iphoneos_sdk_version": capture(
            [str(xcrun), "--sdk", "iphoneos", "--show-sdk-version"]
        ),
        "iphoneos_sdk_build_version": capture(
            [str(xcrun), "--sdk", "iphoneos", "--show-sdk-build-version"]
        ),
        "iphoneos_sdk_settings_sha256": sha256(settings),
        "iphoneos_sdk_tree": sdk_tree,
        "launchers": [
            {"path": path.as_posix(), "sha256": sha256(path)}
            for path in (xcode_select, xcrun)
        ],
        "tools": tools,
    }
