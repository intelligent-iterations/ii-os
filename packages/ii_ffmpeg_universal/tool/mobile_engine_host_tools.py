"""Build exact host tools used by the reviewed mobile FFmpeg recipe."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any, Callable

from mobile_engine_common import BuildError, run, sha256
from mobile_engine_sources import source_record
from web_engine_common import download_exact, extract_exact


def _autotools_executable(source: Path, prefix: Path, name: str) -> Path:
    configure = source / "configure"
    if (
        not configure.is_file()
        or configure.is_symlink()
        or not os.access(configure, os.X_OK)
    ):
        raise BuildError(f"host build tool configure script is unsafe: {configure}")
    run(["./configure", f"--prefix={prefix}"], source)
    # Avoid the unrelated Texinfo documentation target.
    run(["make", "-C", "lib", "-j2"], source)
    run(["make", "-C", "src", "-j2"], source)
    run(["make", "-C", "src", "install"], source)
    return prefix / "bin" / name


def _python_script_executable(
    source: Path, prefix: Path, specification: dict[str, Any]
) -> tuple[Path, dict[str, str]]:
    interpreter = Path(specification["interpreter"])
    entry_relative = Path(specification["entry_point"])
    if entry_relative.is_absolute() or ".." in entry_relative.parts:
        raise BuildError(f"host build tool entry point is unsafe: {entry_relative}")
    entry_point = source / entry_relative
    if (
        not interpreter.is_absolute()
        or not interpreter.is_file()
        or interpreter.is_symlink()
        or not os.access(interpreter, os.X_OK)
    ):
        raise BuildError(f"host build tool interpreter is unsafe: {interpreter}")
    if not entry_point.is_file() or entry_point.is_symlink():
        raise BuildError(f"host build tool entry point is unsafe: {entry_point}")
    executable = prefix / "bin" / specification["name"]
    executable.parent.mkdir(parents=True)
    source_relative = os.path.relpath(source, executable.parent)
    executable.write_text(
        f"#!{interpreter}\n"
        "import os\n"
        "import runpy\n"
        "import sys\n"
        "root = os.path.normpath(os.path.join(\n"
        f"    os.path.dirname(__file__), {source_relative!r}\n"
        "))\n"
        "sys.path.insert(0, root)\n"
        f"runpy.run_path(os.path.join(root, {entry_relative.as_posix()!r}), "
        "run_name='__main__')\n",
        encoding="utf-8",
    )
    executable.chmod(0o700)
    return executable, {
        "interpreter": str(interpreter),
        "interpreter_sha256": sha256(interpreter),
    }


def prepare_host_build_tools(
    workspace: Path,
    lock: dict[str, Any],
    platform: str,
    *,
    download: Callable[[str, str, Path], None] = download_exact,
    extract: Callable[[Path, Path], None] = extract_exact,
    record_source: Callable[..., dict[str, Any]] = source_record,
) -> tuple[list[dict[str, str]], list[dict[str, Any]]]:
    tools_root = workspace / "host-tools"
    tools_root.mkdir()
    identities: list[dict[str, str]] = []
    source_records: list[dict[str, Any]] = []
    bin_paths: list[str] = []
    for specification in lock["host_build_tools"]:
        if platform not in specification["platforms"]:
            continue
        name = specification["name"]
        archive = tools_root / f"{name}.source"
        unpacked = tools_root / f"{name}-unpacked"
        prefix = tools_root / f"{name}-prefix"
        download(specification["url"], specification["sha256"], archive)
        extract(archive, unpacked)
        source = unpacked / specification["root"]
        if not source.is_dir() or source.is_symlink():
            raise BuildError(f"host build tool source root is unsafe: {source}")
        source_records.append(
            record_source(
                name,
                specification["url"],
                specification["revision"],
                source,
                specification["license_paths"],
            )
        )
        build_kind = specification.get("build_kind", "autotools")
        extra_identity: dict[str, str] = {}
        if build_kind == "autotools":
            executable = _autotools_executable(source, prefix, name)
            expected = f"GNU {name} {specification['version']}"
        elif build_kind == "python-script":
            executable, extra_identity = _python_script_executable(
                source, prefix, specification
            )
            expected = specification["version"]
        else:
            raise BuildError(f"unsupported host build tool kind: {build_kind}")
        if not executable.is_file() or executable.is_symlink():
            raise BuildError(f"host build tool executable is unsafe: {executable}")
        version = subprocess.run(
            [str(executable), "--version"],
            check=False,
            capture_output=True,
            text=True,
        )
        first_line = version.stdout.splitlines()[0] if version.stdout else ""
        if version.returncode != 0 or first_line != expected:
            raise BuildError(
                f"host build tool identity mismatch for {name}: {first_line!r}"
            )
        identities.append(
            {
                "name": name,
                "version": specification["version"],
                "revision": specification["revision"],
                "source_archive_sha256": specification["sha256"],
                "sha256": sha256(executable),
                **extra_identity,
            }
        )
        bin_paths.append(str(executable.parent))
    if not identities:
        raise BuildError(f"no locked host build tools apply to {platform}")
    os.environ["PATH"] = os.pathsep.join([*bin_paths, os.environ.get("PATH", "")])
    return identities, source_records
