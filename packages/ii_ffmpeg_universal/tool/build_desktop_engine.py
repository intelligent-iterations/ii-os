#!/usr/bin/env python3
"""Build and attest an application-bundled desktop FFmpeg closure."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
import zipfile
from pathlib import Path


MAX_FILES = 512
MAX_FILE_BYTES = 1024 * 1024 * 1024
SYSTEM_MAC_PREFIXES = ("/usr/lib/", "/System/Library/")
SYSTEM_LINUX_NAMES = {
    "ld-linux-aarch64.so.1",
    "ld-linux-x86-64.so.2",
    "libc.so.6",
    "libdl.so.2",
    "libgcc_s.so.1",
    "libm.so.6",
    "libpthread.so.0",
    "libresolv.so.2",
    "librt.so.1",
    "libstdc++.so.6",
}


class BuildError(RuntimeError):
    pass


def run(
    command: list[str], *, capture: bool = True, cwd: Path | None = None
) -> str:
    process = subprocess.run(
        command,
        check=False,
        text=True,
        capture_output=capture,
        cwd=cwd,
        env={"PATH": os.environ.get("PATH", ""), "LANG": "C", "LC_ALL": "C"},
    )
    if process.returncode != 0:
        detail = process.stderr.strip()[:2000] if capture else ""
        raise BuildError(f"command failed ({process.returncode}): {command[0]}: {detail}")
    return process.stdout if capture else ""


def clone_exact(repository: str, revision: str, destination: Path) -> None:
    destination.mkdir()
    run(["git", "init", "--initial-branch=dev", str(destination)])
    run(["git", "remote", "add", "origin", repository], cwd=destination)
    run(["git", "fetch", "--depth", "1", "origin", revision], cwd=destination)
    run(["git", "reset", "--hard", "FETCH_HEAD"], cwd=destination)
    if run(["git", "branch", "--show-current"], cwd=destination).strip() != "dev":
        raise BuildError("reviewed desktop source is not checked out on dev")
    if run(["git", "rev-parse", "HEAD"], cwd=destination).strip() != revision:
        raise BuildError("reviewed desktop source revision mismatch")


def build_reviewed_engine(workspace: Path, lock_path: Path) -> tuple[Path, Path, dict[str, object]]:
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    source = next(value for value in lock["sources"] if value["name"] == "ffmpeg")
    revision = source["revision"]
    engine_version = lock["engine_version"]
    repository = source["repository"]
    checkout = workspace / "source"
    clone_exact(repository, revision, checkout)
    run(["git", "tag", engine_version, "HEAD"], cwd=checkout)
    prefix = workspace / "install"
    flags = [
        f"--prefix={prefix}",
        "--disable-autodetect",
        "--disable-debug",
        "--disable-doc",
        "--disable-network",
        "--disable-shared",
        "--disable-ffplay",
        "--enable-static",
    ]
    run(["./configure", *flags], cwd=checkout, capture=False)
    jobs = str(max(1, min(os.cpu_count() or 1, 8)))
    run(["make", f"-j{jobs}", "ffmpeg", "ffprobe"], cwd=checkout, capture=False)
    run(["make", "install"], cwd=checkout, capture=False)
    ffmpeg = regular(prefix / "bin" / "ffmpeg")
    ffprobe = regular(prefix / "bin" / "ffprobe")
    license_path = checkout / "COPYING.LGPLv2.1"
    if not license_path.is_file():
        raise BuildError("reviewed FFmpeg source license is missing")
    ledger = {
        "schema": 1,
        "engine_version": engine_version,
        "repository": repository,
        "revision": revision,
        "lock_sha256": sha256(lock_path),
        "builder_sha256": sha256(Path(__file__)),
        "configure_flags": flags,
        "license_path": license_path.name,
        "license_sha256": sha256(license_path),
    }
    return ffmpeg, ffprobe, ledger


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def regular(path: Path) -> Path:
    resolved = path.resolve(strict=True)
    if not resolved.is_file() or resolved.is_symlink() or resolved.stat().st_size > MAX_FILE_BYTES:
        raise BuildError(f"desktop engine input is not a bounded regular file: {path}")
    return resolved


def macho_id(path: Path) -> str | None:
    values = [line.strip() for line in run(["/usr/bin/otool", "-D", str(path)]).splitlines()[1:] if line.strip()]
    if len(values) > 1:
        raise BuildError(f"ambiguous Mach-O install name: {path}")
    return values[0] if values else None


def macho_dependencies(path: Path) -> list[str]:
    return [
        line.strip().split(" (")[0]
        for line in run(["/usr/bin/otool", "-L", str(path)]).splitlines()[1:]
        if line.strip()
    ]


def macho_rpaths(path: Path) -> list[str]:
    lines = run(["/usr/bin/otool", "-l", str(path)]).splitlines()
    values: list[str] = []
    for index, line in enumerate(lines):
        if line.strip() != "cmd LC_RPATH":
            continue
        candidate = next(
            (value.strip() for value in lines[index + 1 :] if value.strip().startswith("path ")),
            "",
        )
        if not candidate:
            raise BuildError(f"malformed Mach-O runtime path: {path}")
        values.append(candidate[5:].split(" (offset")[0])
    return values


def linux_dependencies(path: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for line in run(["/usr/bin/ldd", str(path)]).splitlines():
        value = line.strip()
        name = value.split()[0] if value else ""
        if name in SYSTEM_LINUX_NAMES or name.startswith("linux-vdso"):
            continue
        match = re.search(r"(?:=>\s+)?(/[^ ]+)\s+\(", value)
        if match and not name.startswith("/"):
            result[name] = regular(Path(match.group(1)))
    return result


def discover(platform: str, executables: list[Path]) -> dict[str, Path]:
    queue = list(executables)
    visited: set[Path] = set()
    libraries: dict[str, Path] = {}
    while queue:
        current = queue.pop()
        if current in visited:
            continue
        visited.add(current)
        if platform == "macos":
            identifier = macho_id(current)
            found = {}
            for value in macho_dependencies(current):
                if value == identifier or value.startswith(SYSTEM_MAC_PREFIXES):
                    continue
                if not value.startswith("/"):
                    raise BuildError(f"unresolved Mach-O dependency in source closure: {value}")
                found[Path(value).name] = regular(Path(value))
        else:
            found = linux_dependencies(current)
        for name, path in found.items():
            previous = libraries.get(name)
            if previous is not None and previous != path:
                raise BuildError(f"desktop dependency basename collision: {name}")
            if previous is None:
                libraries[name] = path
                queue.append(path)
                if len(libraries) + 2 > MAX_FILES:
                    raise BuildError("desktop dependency closure exceeds file limit")
    return libraries


def rewrite_macos(files: list[Path], library_names: set[str]) -> None:
    for path in files:
        for runtime_path in macho_rpaths(path):
            run(["/usr/bin/install_name_tool", "-delete_rpath", runtime_path, str(path)])
        identifier = macho_id(path)
        if identifier is not None:
            run(["/usr/bin/install_name_tool", "-id", f"@loader_path/{path.name}", str(path)])
        for dependency in macho_dependencies(path):
            if dependency == identifier or dependency.startswith(SYSTEM_MAC_PREFIXES):
                continue
            name = Path(dependency).name
            if name not in library_names:
                raise BuildError(f"unattested Mach-O dependency: {dependency}")
            local = f"@loader_path/{name}"
            if dependency != local:
                run(["/usr/bin/install_name_tool", "-change", dependency, local, str(path)])
        run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(path)])
    for path in files:
        identifier = macho_id(path)
        if identifier is not None and identifier != f"@loader_path/{path.name}":
            raise BuildError(f"Mach-O install name was not localized: {path}")
        if any(value not in {"@loader_path", "@executable_path"} for value in macho_rpaths(path)):
            raise BuildError(f"Mach-O has an external runtime path: {path}")
        for dependency in macho_dependencies(path):
            if dependency == identifier or dependency.startswith(SYSTEM_MAC_PREFIXES):
                continue
            if dependency != f"@loader_path/{Path(dependency).name}" or Path(dependency).name not in library_names:
                raise BuildError(f"Mach-O dependency was not localized: {dependency}")


def audit_linux(files: list[Path], library_names: set[str]) -> None:
    for path in files:
        output = run(["/usr/bin/readelf", "-d", str(path)])
        for line in output.splitlines():
            needed = re.search(r"\(NEEDED\).*\[([^]]+)\]", line)
            if needed and needed.group(1) not in SYSTEM_LINUX_NAMES | library_names:
                raise BuildError(f"unattested ELF dependency: {needed.group(1)}")
            search = re.search(r"\((?:RPATH|RUNPATH)\).*\[([^]]*)\]", line)
            if search and any(value != "$ORIGIN" for value in search.group(1).split(":")):
                raise BuildError(f"ELF contains an external runtime path: {path}")


def binary_architecture(platform: str, path: Path) -> str:
    if platform == "macos":
        architectures = run(["/usr/bin/lipo", "-archs", str(path)]).split()
        if len(architectures) != 1 or architectures[0] not in {"arm64", "x86_64"}:
            raise BuildError(f"desktop Mach-O architecture is unsupported: {path}")
        return architectures[0]
    header = run(["/usr/bin/readelf", "-h", str(path)])
    machine = next(
        (line.split(":", 1)[1].strip() for line in header.splitlines() if line.strip().startswith("Machine:")),
        "",
    )
    architecture = {
        "AArch64": "arm64",
        "Advanced Micro Devices X86-64": "x86_64",
    }.get(machine)
    if architecture is None:
        raise BuildError(f"desktop ELF architecture is unsupported: {path}")
    return architecture


def deterministic_zip(root: Path, output: Path) -> None:
    with zipfile.ZipFile(output, "x", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(root.iterdir(), key=lambda value: value.name):
            info = zipfile.ZipInfo(path.name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o100500 if path.name in {"ffmpeg", "ffprobe"} else 0o100400) << 16
            archive.writestr(info, path.read_bytes())


def validate_reviewed_build(
    ffmpeg: Path,
    ffprobe: Path,
    source_ledger: dict[str, object],
    version: str,
) -> None:
    if source_ledger["engine_version"] != f"n{version}":
        raise BuildError("reviewed desktop engine version does not match its lock")
    required = set(source_ledger["configure_flags"])
    forbidden_prefixes = (
        "--enable-gpl",
        "--enable-nonfree",
        "--enable-openssl",
        "--enable-gnutls",
        "--enable-libx264",
        "--enable-libx265",
    )
    identities: list[set[str]] = []
    for executable in (ffmpeg, ffprobe):
        buildconf = run([str(executable), "-buildconf"])
        flags = {
            line.strip()
            for line in buildconf.splitlines()
            if line.strip().startswith("--")
        }
        if not required.issubset(flags):
            raise BuildError("reviewed desktop engine omits a required configure flag")
        if any(
            flag == prefix or flag.startswith(f"{prefix}=")
            for flag in flags
            for prefix in forbidden_prefixes
        ):
            raise BuildError("reviewed desktop engine enables a forbidden dependency")
        identities.append(flags)
    if identities[0] != identities[1]:
        raise BuildError("ffmpeg and ffprobe configure identities differ")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path)
    parser.add_argument("--ffprobe", type=Path)
    parser.add_argument(
        "--lock",
        type=Path,
        default=Path(__file__).with_name("mobile_engine_lock.json"),
    )
    args = parser.parse_args()
    try:
        workspace = args.workspace
        if not workspace.is_absolute() or workspace.exists() or not workspace.parent.is_dir():
            raise BuildError("--workspace must be an absolute nonexistent path")
        workspace.mkdir(mode=0o700)
        (workspace / ".ii-disposable-owner").write_text(
            f"ii-ffmpeg-desktop-engine:{uuid.uuid4()}\n", encoding="utf-8"
        )
        platform = "macos" if sys.platform == "darwin" else "linux" if sys.platform.startswith("linux") else ""
        if not platform:
            raise BuildError("desktop engine builder supports macOS and Linux")
        lock_path = args.lock.resolve(strict=True)
        if (args.ffmpeg is None) != (args.ffprobe is None):
            raise BuildError("--ffmpeg and --ffprobe must be provided together")
        source_ledger = None
        if args.ffmpeg is None:
            ffmpeg, ffprobe, source_ledger = build_reviewed_engine(
                workspace, lock_path
            )
        else:
            ffmpeg = regular(args.ffmpeg)
            ffprobe = regular(args.ffprobe)
        version_lines = [run([str(value), "-version"]).splitlines()[0] for value in (ffmpeg, ffprobe)]
        versions = [re.search(r"\bversion\s+n?([0-9]+\.[0-9]+(?:\.[0-9]+)?)\b", line) for line in version_lines]
        if any(value is None for value in versions) or versions[0].group(1) != versions[1].group(1):
            raise BuildError("ffmpeg and ffprobe versions are not exact and equal")
        if source_ledger is not None:
            validate_reviewed_build(
                ffmpeg,
                ffprobe,
                source_ledger,
                versions[0].group(1),
            )
        libraries = discover(platform, [ffmpeg, ffprobe])
        assets = workspace / "assets"
        assets.mkdir()
        copied: list[tuple[str, str, Path]] = []
        for role, source, name in (("ffmpeg", ffmpeg, "ffmpeg"), ("ffprobe", ffprobe, "ffprobe")):
            target = assets / name
            shutil.copy2(source, target)
            copied.append((name, role, target))
        for name, source in sorted(libraries.items()):
            target = assets / name
            shutil.copy2(source, target)
            copied.append((name, "library", target))
        files = [value[2] for value in copied]
        if platform == "macos":
            rewrite_macos(files, set(libraries))
        else:
            audit_linux(files, set(libraries))
        for name, role, path in copied:
            path.chmod(0o500 if role in {"ffmpeg", "ffprobe"} else 0o400)
        architecture_by_path = {
            path: binary_architecture(platform, path) for _, _, path in copied
        }
        architectures = set(architecture_by_path.values())
        if len(architectures) != 1:
            raise BuildError("desktop engine closure mixes CPU architectures")
        architecture = architectures.pop()
        artifacts = [
            {
                "name": name,
                "role": role,
                "architecture": architecture_by_path[path],
                "sha256": sha256(path),
            }
            for name, role, path in copied
        ]
        artifacts.sort(key=lambda value: value["name"])
        canonical = json.dumps(
            artifacts, separators=(",", ":"), ensure_ascii=True, sort_keys=True
        ).encode()
        manifest = {
            "schema": 1,
            "platform": platform,
            "architecture": architecture,
            "engine_version": f"n{versions[0].group(1)}",
            "closure_sha256": hashlib.sha256(canonical).hexdigest(),
            "artifacts": artifacts,
        }
        manifest_path = assets / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        ledger_path = workspace / "source-ledger.json"
        notices_path = workspace / "THIRD_PARTY_NOTICES.txt"
        if source_ledger is not None:
            ledger_path.write_text(
                json.dumps(source_ledger, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            license_path = workspace / "source" / source_ledger["license_path"]
            notices_path.write_text(
                "II desktop FFmpeg engine third-party notices\n\n"
                f"FFmpeg {source_ledger['engine_version']}\n"
                f"Source: {source_ledger['repository']}\n"
                f"Revision: {source_ledger['revision']}\n\n"
                + license_path.read_text(encoding="utf-8", errors="replace"),
                encoding="utf-8",
            )
            shutil.copy2(ledger_path, assets / ledger_path.name)
            shutil.copy2(notices_path, assets / notices_path.name)
        archive = workspace / "desktop-engine.zip"
        deterministic_zip(assets, archive)
        attestation = {
            "schema": 1,
            "platform": platform,
            "architecture": architecture,
            "engine_version": manifest["engine_version"],
            "manifest_sha256": sha256(manifest_path),
            "archive_sha256": sha256(archive),
            "closure_sha256": manifest["closure_sha256"],
            "artifacts": artifacts,
            "reviewed_source": source_ledger is not None,
            "source_ledger_sha256": (
                sha256(ledger_path) if source_ledger is not None else None
            ),
            "notices_sha256": (
                sha256(notices_path) if source_ledger is not None else None
            ),
        }
        attestation_path = workspace / "build-attestation.json"
        attestation_path.write_text(json.dumps(attestation, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"workspace": str(workspace), **attestation}, sort_keys=True))
        return 0
    except (BuildError, OSError, ValueError) as error:
        print(f"desktop engine build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
