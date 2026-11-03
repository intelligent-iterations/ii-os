#!/usr/bin/env python3
"""Verify and attest the exact Apple engine build-tool executables."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

from apple_build_tool_tree import (
    PinnedDirectory,
    TreeAttestationError,
    attest_tree,
    hash_file_bounded,
    read_file_bounded,
)
from apple_xcode_toolchain import (
    XCODE_TOOL_NAMES,
    XcodeToolchainError,
    attest_xcode_toolchain,
)


MAX_EXECUTABLE_BYTES = 512 * 1024 * 1024
MAX_RECEIPT_BYTES = 256 * 1024
MAX_ATTESTATION_BYTES = 4 * 1024 * 1024
MAX_LOCK_BYTES = 1024 * 1024
SAFE_NAME = re.compile(r"^[a-z][a-z0-9-]{0,31}$")
SAFE_VERSION = re.compile(r"^[0-9]+(?:\.[0-9]+){1,3}$")
SAFE_FORMULA_PATH = re.compile(r"^Formula/[A-Za-z0-9]{1,8}/[A-Za-z0-9@+_.-]+\.rb$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class AttestationError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    try:
        return hash_file_bounded(path, MAX_EXECUTABLE_BYTES)
    except TreeAttestationError as error:
        raise AttestationError(
            f"build input cannot be hashed safely: {path.name}"
        ) from error


def _tree_attestation(root: Path) -> dict[str, Any]:
    try:
        return attest_tree(root)
    except TreeAttestationError as error:
        raise AttestationError(str(error)) from error


def _capture(
    command: list[str], environment: dict[str, str] | None = None
) -> str:
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
        env=environment,
    )
    output = (result.stdout + result.stderr).strip()
    if result.returncode != 0 or len(output) > 4096:
        raise AttestationError(f"build-tool command failed: {command[0]}")
    return output


def _selects_attested_executable(discovered: str | None, expected: Path) -> bool:
    if discovered is None:
        return False
    try:
        return Path(discovered).resolve(strict=True) == expected.resolve(strict=True)
    except (OSError, RuntimeError):
        return False


def _git_capture(formula_root: Path, arguments: list[str]) -> str:
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = os.devnull
    return _capture(["git", "-C", str(formula_root), *arguments], environment)


def read_lock(lock_path: Path) -> tuple[dict[str, Any], str]:
    try:
        raw = read_file_bounded(lock_path, MAX_LOCK_BYTES)
        value = json.loads(raw)
    except TreeAttestationError as error:
        raise AttestationError("Apple toolchain lock cannot be read safely") from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AttestationError("Apple toolchain lock is invalid JSON") from error
    if not isinstance(value, dict):
        raise AttestationError("Apple toolchain lock is not an object")
    return value, hashlib.sha256(raw).hexdigest()


def _specifications(
    lock_path: Path,
) -> tuple[
    dict[str, str],
    list[dict[str, str]],
    list[dict[str, str]],
    str,
]:
    lock, lock_sha256 = read_lock(lock_path)
    toolchains = lock.get("toolchains")
    if not isinstance(toolchains, dict):
        raise AttestationError("Apple toolchain lock is missing")
    homebrew = toolchains.get("homebrew_core")
    if (
        not isinstance(homebrew, dict)
        or homebrew.get("repository")
        != "https://github.com/Homebrew/homebrew-core.git"
        or not isinstance(homebrew.get("revision"), str)
        or not re.fullmatch(r"[0-9a-f]{40}", homebrew["revision"])
    ):
        raise AttestationError("Homebrew/core lock is missing or invalid")
    formula_values = toolchains.get("apple_build_formulae")
    if (
        not isinstance(formula_values, list)
        or not formula_values
        or len(formula_values) > 16
    ):
        raise AttestationError("Apple build-formula lock is missing or invalid")
    formulae: list[dict[str, str]] = []
    for value in formula_values:
        if not isinstance(value, dict) or set(value) != {
            "formula",
            "version",
            "path",
            "sha256",
        }:
            raise AttestationError("Apple build-formula record is invalid")
        if (
            not isinstance(value["formula"], str)
            or not SAFE_NAME.fullmatch(value["formula"])
            or not isinstance(value["version"], str)
            or not SAFE_VERSION.fullmatch(value["version"])
            or not isinstance(value["path"], str)
            or not SAFE_FORMULA_PATH.fullmatch(value["path"])
            or not isinstance(value["sha256"], str)
            or not SHA256.fullmatch(value["sha256"])
        ):
            raise AttestationError("Apple build-formula record has an invalid value")
        formulae.append(value)
    formula_map = {value["formula"]: value for value in formulae}
    if len(formula_map) != len(formulae):
        raise AttestationError("Apple build formulae are duplicated")

    values = toolchains.get("apple_build_tools")
    if not isinstance(values, list) or not values or len(values) > 24:
        raise AttestationError("Apple build-tool lock is missing or invalid")
    records: list[dict[str, str]] = []
    for value in values:
        if not isinstance(value, dict) or set(value) != {
            "formula",
            "executable",
            "version",
        }:
            raise AttestationError("Apple build-tool record is not an object")
        record = {key: value.get(key) for key in ("formula", "executable", "version")}
        if (
            not all(isinstance(item, str) for item in record.values())
            or not SAFE_NAME.fullmatch(record["formula"])
            or not SAFE_NAME.fullmatch(record["executable"])
            or not SAFE_VERSION.fullmatch(record["version"])
        ):
            raise AttestationError("Apple build-tool record has an invalid value")
        typed_record = {key: str(record[key]) for key in record}
        formula = formula_map.get(typed_record["formula"])
        if formula is None or formula["version"] != typed_record["version"]:
            raise AttestationError("Apple build tool does not match a locked formula")
        records.append(typed_record)
    if len({value["executable"] for value in records}) != len(records):
        raise AttestationError("Apple build-tool executables are duplicated")
    return (
        {"repository": homebrew["repository"], "revision": homebrew["revision"]},
        formulae,
        records,
        lock_sha256,
    )


def _bounded_json(path: Path) -> tuple[dict[str, Any], str]:
    try:
        raw = read_file_bounded(path, MAX_RECEIPT_BYTES)
        value = json.loads(raw)
    except TreeAttestationError as error:
        raise AttestationError(
            "Homebrew install receipt is missing or invalid"
        ) from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AttestationError("Homebrew install receipt is invalid JSON") from error
    if not isinstance(value, dict):
        raise AttestationError("Homebrew install receipt is not an object")
    return value, hashlib.sha256(raw).hexdigest()


def _xcode_toolchain() -> dict[str, Any]:
    try:
        return attest_xcode_toolchain(_capture, _sha256)
    except XcodeToolchainError as error:
        raise AttestationError(str(error)) from error


def _verify_clean_checkout(
    formula_root: Path, expected_revision: str, expected_repository: str
) -> str:
    if (
        not formula_root.is_absolute()
        or formula_root.is_symlink()
        or not formula_root.is_dir()
    ):
        raise AttestationError("Homebrew/core checkout is missing or linked")
    revision = _git_capture(formula_root, ["rev-parse", "HEAD"])
    remote = _git_capture(formula_root, ["remote", "get-url", "origin"])
    if revision != expected_revision or remote != expected_repository:
        raise AttestationError("Homebrew/core checkout does not match its lock")
    if _git_capture(formula_root, ["status", "--porcelain"]):
        raise AttestationError("Homebrew/core checkout is dirty")
    return revision


def attest(lock_path: Path, formula_root: Path) -> dict[str, Any]:
    homebrew, formulae, records, lock_sha256 = _specifications(lock_path)
    formula_map = {value["formula"]: value for value in formulae}
    try:
        checkout = PinnedDirectory(formula_root)
    except TreeAttestationError as error:
        raise AttestationError(str(error)) from error
    try:
        revision = _verify_clean_checkout(
            formula_root, homebrew["revision"], homebrew["repository"]
        )
        checkout.verify()
        formula_digests = {
            formula["path"]: checkout.hash_file(
                formula["path"], MAX_EXECUTABLE_BYTES
            )
            for formula in formulae
        }
        checkout.verify()
    except TreeAttestationError as error:
        raise AttestationError(str(error)) from error
    finally:
        checkout.close()
    locked_formulae: dict[str, dict[str, str]] = {}
    installed_formulae: list[dict[str, Any]] = []
    for formula in formulae:
        formula_file = formula_root / formula["path"]
        if formula_digests[formula["path"]] != formula["sha256"]:
            raise AttestationError(
                f"Homebrew formula does not match its lock: {formula['formula']}"
            )
        prefix = Path(_capture(["brew", "--prefix", formula["formula"]])).resolve(
            strict=True
        )
        receipt, receipt_sha256 = _bounded_json(prefix / "INSTALL_RECEIPT.json")
        source = receipt.get("source")
        versions = source.get("versions") if isinstance(source, dict) else None
        source_path = source.get("path") if isinstance(source, dict) else None
        dependency_values = receipt.get("runtime_dependencies")
        if (
            not isinstance(versions, dict)
            or versions.get("stable") != formula["version"]
            or not isinstance(source_path, str)
            or source_path != formula_file.as_posix()
            or receipt.get("poured_from_bottle") is not True
            or not isinstance(dependency_values, list)
        ):
            raise AttestationError(
                f"Homebrew formula receipt is not pinned: {formula['formula']}"
            )
        runtime_dependencies = []
        for dependency in dependency_values:
            full_name = (
                dependency.get("full_name") if isinstance(dependency, dict) else None
            )
            version = dependency.get("version") if isinstance(dependency, dict) else None
            name = full_name.rsplit("/", 1)[-1] if isinstance(full_name, str) else ""
            expected_dependency = formula_map.get(name)
            if (
                expected_dependency is None
                or version != expected_dependency["version"]
            ):
                raise AttestationError(
                    f"Homebrew formula has an unlocked dependency: {formula['formula']}"
                )
            runtime_dependencies.append({"formula": name, "version": version})
        runtime_dependencies.sort(key=lambda value: value["formula"])
        installed = {
            **formula,
            "receipt_sha256": receipt_sha256,
            "runtime_dependencies": runtime_dependencies,
            "installed_tree": _tree_attestation(prefix),
        }
        locked_formulae[formula["formula"]] = installed
        installed_formulae.append(installed)

    tools = []
    for expected in records:
        formula = locked_formulae[expected["formula"]]
        prefix = Path(_capture(["brew", "--prefix", expected["formula"]])).resolve(
            strict=True
        )
        path = (prefix / "bin" / expected["executable"]).resolve(strict=True)
        if not path.is_file() or path.is_symlink() or prefix not in path.parents:
            raise AttestationError(
                f"Apple build tool is outside its formula prefix: {expected['executable']}"
            )
        result = subprocess.run(
            [str(path), "--version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        output = (result.stdout + result.stderr)[:4096]
        version = expected["version"]
        if result.returncode != 0 or not re.search(
            rf"(?<![0-9.]){re.escape(version)}(?![0-9.])", output
        ):
            raise AttestationError(
                f"Apple build tool does not match its locked version: {expected['executable']}"
            )
        tools.append(
            {
                **expected,
                "formula_path": formula["path"],
                "formula_sha256": formula["sha256"],
                "formula_receipt_sha256": formula["receipt_sha256"],
                "resolved_name": path.name,
                "sha256": _sha256(path),
            }
        )
    xcode = _xcode_toolchain()
    report: dict[str, Any] = {
        "schema": 2,
        "lock_sha256": lock_sha256,
        "homebrew_core_revision": revision,
        "formulae": installed_formulae,
        "tools": tools,
        "xcode": xcode,
    }
    report["closure_sha256"] = hashlib.sha256(
        json.dumps(
            {"formulae": installed_formulae, "tools": tools, "xcode": xcode},
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
    ).hexdigest()
    return report


def validate_report(report: object, lock_path: Path) -> dict[str, Any]:
    homebrew, formulae, records, lock_sha256 = _specifications(lock_path)
    if not isinstance(report, dict):
        raise AttestationError("Apple build-tool report is not an object")
    installed = report.get("formulae")
    tools = report.get("tools")
    if (
        set(report)
        != {
            "schema",
            "lock_sha256",
            "homebrew_core_revision",
            "formulae",
            "tools",
            "xcode",
            "closure_sha256",
        }
        or report.get("schema") != 2
        or report.get("lock_sha256") != lock_sha256
        or report.get("homebrew_core_revision") != homebrew["revision"]
        or not isinstance(installed, list)
        or len(installed) != len(formulae)
        or not isinstance(tools, list)
        or len(tools) != len(records)
    ):
        raise AttestationError("Apple build-tool report header is invalid")
    tree_keys = {
        "entry_count",
        "file_count",
        "link_count",
        "total_bytes",
        "sha256",
    }

    def validate_tree(tree: object, label: str) -> dict[str, Any]:
        if (
            not isinstance(tree, dict)
            or set(tree) != tree_keys
            or not isinstance(tree.get("sha256"), str)
            or SHA256.fullmatch(str(tree["sha256"])) is None
        ):
            raise AttestationError(f"{label} tree digest is invalid")
        for key in ("entry_count", "file_count", "link_count", "total_bytes"):
            value = tree.get(key)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise AttestationError(f"{label} tree count is invalid")
        if tree["entry_count"] <= 0 or tree["file_count"] <= 0:
            raise AttestationError(f"{label} tree is empty")
        return tree

    formula_map = {value["formula"]: value for value in formulae}
    for actual, expected in zip(installed, formulae):
        tree = actual.get("installed_tree") if isinstance(actual, dict) else None
        if (
            not isinstance(actual, dict)
            or set(actual)
            != {
                *expected,
                "receipt_sha256",
                "runtime_dependencies",
                "installed_tree",
            }
            or any(actual.get(key) != value for key, value in expected.items())
            or not isinstance(actual.get("receipt_sha256"), str)
            or SHA256.fullmatch(actual["receipt_sha256"]) is None
        ):
            raise AttestationError("Apple build-formula report is invalid")
        validate_tree(tree, "Apple build-formula")
        dependencies = actual.get("runtime_dependencies")
        if (
            not isinstance(dependencies, list)
            or dependencies
            != sorted(
                dependencies,
                key=lambda value: (
                    str(value.get("formula")) if isinstance(value, dict) else ""
                ),
            )
            or any(
                not isinstance(value, dict)
                or set(value) != {"formula", "version"}
                or value.get("formula") not in formula_map
                or value.get("version")
                != formula_map[str(value.get("formula"))]["version"]
                for value in dependencies
            )
        ):
            raise AttestationError("Apple build-formula dependencies are invalid")
    tool_keys = {
        "formula",
        "executable",
        "version",
        "formula_path",
        "formula_sha256",
        "formula_receipt_sha256",
        "resolved_name",
        "sha256",
    }
    for actual, expected in zip(tools, records):
        formula = formula_map[expected["formula"]]
        if (
            not isinstance(actual, dict)
            or set(actual) != tool_keys
            or any(actual.get(key) != value for key, value in expected.items())
            or actual.get("formula_path") != formula["path"]
            or actual.get("formula_sha256") != formula["sha256"]
            or not isinstance(actual.get("resolved_name"), str)
            or re.fullmatch(r"[A-Za-z0-9@+_.-]{1,64}", actual["resolved_name"])
            is None
            or any(
                not isinstance(actual.get(key), str)
                or SHA256.fullmatch(actual[key]) is None
                for key in ("formula_receipt_sha256", "sha256")
            )
        ):
            raise AttestationError("Apple build-tool report is invalid")
    xcode = report.get("xcode")
    if (
        not isinstance(xcode, dict)
        or set(xcode)
        != {
            "developer_dir",
            "xcode_version",
            "iphoneos_sdk_relative_path",
            "iphoneos_sdk_version",
            "iphoneos_sdk_build_version",
            "iphoneos_sdk_settings_sha256",
            "iphoneos_sdk_tree",
            "launchers",
            "tools",
        }
        or not isinstance(xcode.get("developer_dir"), str)
        or not str(xcode["developer_dir"]).startswith("/Applications/")
        or not isinstance(xcode.get("xcode_version"), str)
        or not str(xcode["xcode_version"]).startswith("Xcode ")
        or not isinstance(xcode.get("iphoneos_sdk_relative_path"), str)
        or str(xcode["iphoneos_sdk_relative_path"]).startswith("/")
        or any(".." == part for part in Path(str(xcode["iphoneos_sdk_relative_path"])).parts)
        or any(
            not isinstance(xcode.get(key), str) or not str(xcode[key]).strip()
            for key in ("iphoneos_sdk_version", "iphoneos_sdk_build_version")
        )
        or not isinstance(xcode.get("iphoneos_sdk_settings_sha256"), str)
        or SHA256.fullmatch(str(xcode["iphoneos_sdk_settings_sha256"])) is None
    ):
        raise AttestationError("Xcode toolchain report is invalid")
    validate_tree(xcode.get("iphoneos_sdk_tree"), "iPhoneOS SDK")
    launchers = xcode.get("launchers")
    xcode_tools = xcode.get("tools")
    if (
        not isinstance(launchers, list)
        or [item.get("path") for item in launchers if isinstance(item, dict)]
        != ["/usr/bin/xcode-select", "/usr/bin/xcrun"]
        or any(
            not isinstance(item, dict)
            or set(item) != {"path", "sha256"}
            or not isinstance(item.get("sha256"), str)
            or SHA256.fullmatch(item["sha256"]) is None
            for item in launchers
        )
        or not isinstance(xcode_tools, list)
        or [item.get("name") for item in xcode_tools if isinstance(item, dict)]
        != list(XCODE_TOOL_NAMES)
        or any(
            not isinstance(item, dict)
            or set(item) != {"name", "relative_path", "sha256"}
            or not isinstance(item.get("relative_path"), str)
            or str(item["relative_path"]).startswith("/")
            or ".." in Path(str(item["relative_path"])).parts
            or not isinstance(item.get("sha256"), str)
            or SHA256.fullmatch(item["sha256"]) is None
            for item in xcode_tools
        )
    ):
        raise AttestationError("Xcode executable report is invalid")
    closure = hashlib.sha256(
        json.dumps(
            {"formulae": installed, "tools": tools, "xcode": xcode},
            separators=(",", ":"),
            sort_keys=True,
        ).encode()
    ).hexdigest()
    if report.get("closure_sha256") != closure:
        raise AttestationError("Apple build-tool closure digest is invalid")
    return report


def verify_attestation(
    attestation_path: Path, lock_path: Path, formula_root: Path
) -> str:
    try:
        attestation_bytes = read_file_bounded(
            attestation_path, MAX_ATTESTATION_BYTES
        )
        supplied = json.loads(attestation_bytes)
    except TreeAttestationError as error:
        raise AttestationError(
            "Apple build-tool attestation is missing or invalid"
        ) from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AttestationError("Apple build-tool attestation is invalid JSON") from error
    validate_report(supplied, lock_path)
    current = attest(lock_path, formula_root)
    if supplied != current:
        raise AttestationError("Apple build-tool attestation no longer matches the host")
    _, _, records, _ = _specifications(lock_path)
    for expected in records:
        prefix = Path(
            _capture(["brew", "--prefix", expected["formula"]])
        ).resolve(strict=True)
        path = (prefix / "bin" / expected["executable"]).resolve(strict=True)
        discovered = shutil.which(expected["executable"])
        if not _selects_attested_executable(discovered, path):
            raise AttestationError(
                f"PATH does not select the attested tool: {expected['executable']}"
            )
    for launcher in (Path("/usr/bin/xcode-select"), Path("/usr/bin/xcrun")):
        discovered = shutil.which(launcher.name)
        if not _selects_attested_executable(discovered, launcher):
            raise AttestationError(
                f"PATH does not select the attested launcher: {launcher.name}"
            )
    return hashlib.sha256(attestation_bytes).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--formula-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise AttestationError("Apple build-tool attestation output must be new")
    args.output.write_text(
        json.dumps(attest(args.lock, args.formula_root), indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
