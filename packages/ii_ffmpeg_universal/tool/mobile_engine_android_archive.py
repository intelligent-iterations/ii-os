"""Android toolchain verification and deterministic AAR assembly."""

from __future__ import annotations

import zipfile
import os
from pathlib import Path
from typing import Callable, Optional

from mobile_engine_common import BuildError, capture, sha256


RunCommand = Callable[[list[str], Optional[Path]], None]


def android_toolchain(
    expected_ndk_revision: str, compile_sdk: int, java_version: int
) -> tuple[dict[str, object], Path]:
    for variable in ("ANDROID_SDK_ROOT", "ANDROID_NDK_ROOT"):
        if not os.environ.get(variable):
            raise BuildError(f"{variable} is required for Android builds")
    sdk_root = Path(os.environ["ANDROID_SDK_ROOT"]).resolve(strict=True)
    ndk_root = Path(os.environ["ANDROID_NDK_ROOT"]).resolve(strict=True)
    properties = (ndk_root / "source.properties").read_text(encoding="utf-8")
    revision = next(
        (
            line.partition("=")[2].strip()
            for line in properties.splitlines()
            if line.startswith("Pkg.Revision")
        ),
        "",
    )
    if revision != expected_ndk_revision:
        raise BuildError(
            f"Android NDK revision {revision!r} does not match {expected_ndk_revision}"
        )
    android_jar = sdk_root / "platforms" / f"android-{compile_sdk}" / "android.jar"
    if not android_jar.is_file() or android_jar.is_symlink():
        raise BuildError(f"Android SDK platform is missing: {android_jar}")
    javac_version = capture(["javac", "-version"])
    if not javac_version.startswith("javac "):
        raise BuildError(f"javac identity is invalid: {javac_version!r}")
    return (
        {
            "android_compile_sdk": compile_sdk,
            "android_jar_sha256": sha256(android_jar),
            "android_java_target": java_version,
            "android_ndk_revision": revision,
            "javac_version": javac_version,
        },
        android_jar,
    )


def build_android_aar(
    project: Path,
    output: Path,
    android_jar: Path,
    java_version: int,
    run: RunCommand,
) -> None:
    sources = sorted((project / "src/main/java").rglob("*.java"))
    if not sources or len(sources) > 256:
        raise BuildError("Android wrapper Java source set is invalid")
    build = project / "ii-offline-build"
    classes = build / "classes"
    classes.mkdir(parents=True)
    run(
        [
            "javac",
            "-encoding",
            "UTF-8",
            "-source",
            str(java_version),
            "-target",
            str(java_version),
            "-classpath",
            str(android_jar),
            "-d",
            str(classes),
            *(str(source) for source in sources),
        ],
        None,
    )
    classes_jar = build / "classes.jar"
    _zip_entries(
        classes_jar,
        [
            (compiled.relative_to(classes).as_posix(), compiled)
            for compiled in sorted(classes.rglob("*.class"))
        ],
    )
    entries: list[tuple[str, Path]] = [
        ("AndroidManifest.xml", project / "src/main/AndroidManifest.xml"),
        ("classes.jar", classes_jar),
    ]
    consumer_rules = project / "consumer-rules.pro"
    if consumer_rules.is_file():
        entries.append(("proguard.txt", consumer_rules))
    for root_name in ("jniLibs", "res"):
        root = project / "src/main" / root_name
        prefix = "jni" if root_name == "jniLibs" else "res"
        entries.extend(
            (f"{prefix}/{value.relative_to(root).as_posix()}", value)
            for value in sorted(root.rglob("*"))
            if value.is_file() and not value.is_symlink()
        )
    _zip_entries(output, entries)


def _zip_entries(destination: Path, entries: list[tuple[str, Path]]) -> None:
    names = [name for name, _ in entries]
    if len(names) != len(set(names)) or names != sorted(names):
        entries = sorted(entries)
        names = [name for name, _ in entries]
    if len(names) != len(set(names)):
        raise BuildError("Android archive contains duplicate paths")
    with zipfile.ZipFile(
        destination,
        "x",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        allowZip64=True,
    ) as archive:
        for name, source in entries:
            if not source.is_file() or source.is_symlink():
                raise BuildError(f"Android archive source is unsafe: {source}")
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (source.stat().st_mode & 0xFFFF) << 16
            with source.open("rb") as input_file, archive.open(info, "w") as target:
                while chunk := input_file.read(1024 * 1024):
                    target.write(chunk)
