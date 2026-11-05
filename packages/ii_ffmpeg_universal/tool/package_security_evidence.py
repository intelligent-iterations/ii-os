"""Reconstruct package-signing and permission evidence from application bytes."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Any


def _android_tool(name: str) -> str | None:
    direct = shutil.which(name)
    if direct:
        return direct
    roots: list[Path] = []
    for variable in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        raw = os.environ.get(variable, "").strip()
        if raw:
            roots.append(Path(raw))
    analyzer = shutil.which("apkanalyzer")
    if analyzer:
        resolved = Path(analyzer).resolve()
        for parent in resolved.parents:
            if parent.name == "cmdline-tools":
                roots.append(parent.parent)
                break
    candidates: list[Path] = []
    for root in roots:
        candidates.append(root / "cmdline-tools/latest/bin" / name)
        build_tools = root / "build-tools"
        if build_tools.is_dir() and not build_tools.is_symlink():
            candidates.extend(
                directory / name
                for directory in sorted(build_tools.iterdir(), reverse=True)
                if directory.is_dir() and not directory.is_symlink()
            )
    return next(
        (str(path) for path in candidates if path.is_file() and not path.is_symlink()),
        None,
    )


def run_checked(command: list[str]) -> str:
    executable = _android_tool(command[0]) if command[0] in {
        "apkanalyzer",
        "apksigner",
    } else shutil.which(command[0])
    if executable is None:
        raise RuntimeError(f"Required package inspector is unavailable: {command[0]}")
    result = subprocess.run(
        [executable, *command[1:]],
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    output = (result.stdout + result.stderr).strip()
    if result.returncode != 0:
        raise RuntimeError(
            f"Package inspection failed: {command[0]}: {output[:1000]}"
        )
    return output


def android_security(application: Path) -> dict[str, Any]:
    signing = run_checked(
        ["apksigner", "verify", "--verbose", "--print-certs", str(application)]
    )
    permissions = run_checked(
        ["apkanalyzer", "manifest", "permissions", str(application)]
    )
    permission_set = sorted(
        line.strip() for line in permissions.splitlines() if line.strip()
    )
    if "android.permission.INTERNET" in permission_set:
        raise RuntimeError("Release-mode Android package unexpectedly requests INTERNET")
    cert_lines = sorted(
        line.strip()
        for line in signing.splitlines()
        if "certificate SHA-256 digest:" in line
    )
    if len(cert_lines) != 1:
        raise RuntimeError("Android acceptance APK signer evidence is ambiguous")
    return {
        "permissions": permission_set,
        "signer_certificate_sha256": cert_lines[0].rsplit(":", 1)[1]
        .strip()
        .lower(),
    }


def apple_security(application: Path, label: str) -> dict[str, Any]:
    if label == "ios-device-compile":
        result = subprocess.run(
            [shutil.which("codesign") or "codesign", "-dv", str(application)],
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode == 0:
            raise RuntimeError("Compile-only iOS fixture was unexpectedly signed")
        return {"codesigned": False}
    run_checked(["codesign", "--verify", "--deep", "--strict", str(application)])
    if label == "ios-simulator":
        return {"codesigned": True}
    entitlements = run_checked(
        ["codesign", "-d", "--entitlements", ":-", str(application)]
    )
    if "com.apple.security.app-sandbox" in entitlements:
        raise RuntimeError(
            "The process-backed macOS fixture must not claim App Sandbox support"
        )
    return {
        "codesign_verified": True,
        "app_sandbox": False,
        "execution_model": "attested-child-process",
    }
