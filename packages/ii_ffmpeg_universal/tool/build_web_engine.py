#!/usr/bin/env python3
"""Build the exact, single-thread, local-only production FFmpeg Wasm core."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import uuid
from pathlib import Path
from typing import Any

from web_engine_common import (
    WebEngineError,
    activated_emsdk_environment,
    clone_exact,
    download_exact,
    extract_exact,
    run,
    sha256,
)


def _prepare(workspace: Path, lock: dict[str, Any], lock_path: Path) -> dict[str, Any]:
    if not workspace.is_absolute() or workspace.exists() or not workspace.parent.is_dir():
        raise WebEngineError("--workspace must be an absolute nonexistent path")
    workspace.mkdir(mode=0o700)
    (workspace / ".ii-disposable-owner").write_text(
        f"ii-ffmpeg-web-engine:{uuid.uuid4()}\n", encoding="utf-8"
    )
    downloads = workspace / "downloads"
    sources = workspace / "sources"
    downloads.mkdir()
    sources.mkdir()
    roots: dict[str, Path] = {}
    records = []
    for source in lock["sources"]:
        archive = downloads / f"{source['name']}.source"
        fallback_urls = tuple(source.get("fallback_urls", []))
        try:
            download_url = download_exact(
                source["url"],
                source["sha256"],
                archive,
                fallback_urls=fallback_urls,
            )
        except WebEngineError as error:
            raise WebEngineError(
                f"source download failed for {source['name']}: {error}"
            ) from error
        unpacked = sources / source["name"]
        extract_exact(archive, unpacked)
        root = unpacked / source["root"]
        if not root.is_dir():
            raise WebEngineError(f"source root is absent: {source['name']}")
        roots[source["name"]] = root
        license_records = []
        for relative in source.get("license_paths", []):
            license_path = root / relative
            if not license_path.is_file() or root.resolve() not in license_path.resolve().parents:
                raise WebEngineError(f"invalid source license: {source['name']}/{relative}")
            license_records.append({"path": relative, "sha256": sha256(license_path)})
        if not license_records and "license_source" not in source:
            raise WebEngineError(f"source has no license record: {source['name']}")
        records.append(
            {
                "name": source["name"],
                "url": source["url"],
                "fallback_urls": list(fallback_urls),
                "download_url": download_url,
                "archive_sha256": source["sha256"],
                "revision": source["revision"],
                "licenses": license_records,
                **(
                    {"license_source": source["license_source"]}
                    if "license_source" in source
                    else {}
                ),
            }
        )

    toolchain = lock["toolchain"]
    emsdk = workspace / "toolchain" / "emsdk"
    emsdk.parent.mkdir()
    clone_exact(toolchain["repository"], toolchain["revision"], emsdk)
    toolchain_licenses = []
    for relative in toolchain["license_paths"]:
        license_path = emsdk / relative
        if not license_path.is_file():
            raise WebEngineError(f"toolchain license is absent: {relative}")
        toolchain_licenses.append({"path": relative, "sha256": sha256(license_path)})

    ffmpeg = roots["ffmpeg"]
    patch = Path(__file__).with_name("patches") / "ffmpeg-5.1-web.patch"
    run(["patch", "--batch", "--forward", "-p1", "-i", str(patch)], ffmpeg)
    ledger = {
        "schema": 1,
        "engine_version": lock["engine_version"],
        "lock_sha256": sha256(lock_path),
        "patch_sha256": sha256(patch),
        "sources": records,
        "toolchain": {
            "name": toolchain["name"],
            "repository": toolchain["repository"],
            "revision": toolchain["revision"],
            "version": toolchain["version"],
            "licenses": toolchain_licenses,
        },
        "configure_flags": [],
        "artifacts": [],
    }
    artifacts = workspace / "artifacts"
    artifacts.mkdir()
    _write_notices(ledger, roots, emsdk, artifacts / "THIRD_PARTY_NOTICES.txt")
    (artifacts / "source-ledger.json").write_text(
        json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return {"roots": roots, "emsdk": emsdk, "artifacts": artifacts, "ledger": ledger}


def _write_notices(
    ledger: dict[str, Any], roots: dict[str, Path], emsdk: Path, destination: Path
) -> None:
    by_name = {record["name"]: record for record in ledger["sources"]}
    with destination.open("w", encoding="utf-8") as output:
        output.write("II browser FFmpeg engine third-party notices\n\n")
        for record in ledger["sources"]:
            output.write(
                f"== {record['name']} ==\nSource: {record['download_url']}\n"
                f"Revision: {record['revision']}\n\n"
            )
            licensed = by_name.get(record.get("license_source", record["name"]))
            if licensed is None:
                raise WebEngineError(f"unknown license source: {record['name']}")
            root = roots[licensed["name"]]
            for item in licensed["licenses"]:
                output.write(f"--- {licensed['name']}/{item['path']} ---\n")
                output.write((root / item["path"]).read_text(errors="replace"))
                output.write("\n\n")
        toolchain = ledger["toolchain"]
        output.write(
            f"== {toolchain['name']} ==\nSource: {toolchain['repository']}\n"
            f"Revision: {toolchain['revision']}\n\n"
        )
        for item in toolchain["licenses"]:
            output.write(f"--- emsdk/{item['path']} ---\n")
            output.write((emsdk / item["path"]).read_text(errors="replace"))
            output.write("\n\n")


def _make(source: Path, env: dict[str, str], jobs: str) -> None:
    run(["emmake", "make", f"-j{jobs}"], source, env)
    run(["emmake", "make", "install"], source, env)


def _configure_zlib(
    source: Path, prefix: Path, env: dict[str, str], jobs: str
) -> None:
    # zlib's CMake project always declares both zlib and zlibstatic. On a
    # target without shared-library support CMake turns both into static
    # targets named libz.a, so a parallel build can unlink the archive while
    # the other target runs ranlib. zlib's supported configure path emits one
    # static archive and avoids that cross-target output race.
    run(
        ["emconfigure", "./configure", "--static", f"--prefix={prefix}"],
        source,
        env,
    )
    _make(source, env, jobs)


def _configure_deps(roots: dict[str, Path], prefix: Path, env: dict[str, str]) -> None:
    jobs = str(max(1, min(int(os.environ.get("II_FFMPEG_BUILD_JOBS", "4")), 8)))
    common = [f"--prefix={prefix}", "--disable-shared", "--enable-static"]
    _configure_zlib(roots["zlib"], prefix, env, jobs)

    fbuild = prefix.parent / "build-freetype"
    run(
        [
            "emcmake", "cmake", "-S", str(roots["freetype"]), "-B", str(fbuild),
            f"-DCMAKE_INSTALL_PREFIX={prefix}", "-DCMAKE_BUILD_TYPE=Release",
            "-DBUILD_SHARED_LIBS=OFF", "-DFT_DISABLE_BZIP2=TRUE",
            "-DFT_DISABLE_PNG=TRUE", "-DFT_DISABLE_HARFBUZZ=TRUE",
            "-DFT_DISABLE_BROTLI=TRUE", "-DFT_REQUIRE_ZLIB=TRUE",
            f"-DZLIB_LIBRARY={prefix}/lib/libz.a",
            f"-DZLIB_INCLUDE_DIR={prefix}/include",
        ], env=env
    )
    run(["cmake", "--build", str(fbuild), "--target", "install", "-j", jobs], env=env)
    run(
        [
            "emconfigure", "./configure", *common, "--host=wasm32-unknown-emscripten",
            "--disable-deprecated",
        ], roots["fribidi"], env
    )
    _make(roots["fribidi"], env, jobs)

    hbuild = prefix.parent / "build-harfbuzz"
    run(
        [
            "emcmake", "cmake", "-S", str(roots["harfbuzz"]), "-B", str(hbuild),
            f"-DCMAKE_INSTALL_PREFIX={prefix}", "-DCMAKE_BUILD_TYPE=Release",
            "-DBUILD_SHARED_LIBS=OFF", "-DHB_BUILD_UTILS=OFF", "-DHB_BUILD_SUBSET=OFF",
            "-DHB_HAVE_FREETYPE=OFF", "-DHB_HAVE_GLIB=OFF", "-DHB_HAVE_ICU=OFF",
            "-DCMAKE_DISABLE_FIND_PACKAGE_Threads=TRUE",
        ], env=env
    )
    run(["cmake", "--build", str(hbuild), "--target", "install", "-j", jobs], env=env)
    run(
        [
            "emconfigure", "./configure", *common, "--host=wasm32-unknown-emscripten",
            "--disable-asm", "--disable-fontconfig", "--disable-require-system-font-provider",
        ], roots["libass"], env
    )
    _make(roots["libass"], env, jobs)
    vpx_prefix = os.path.relpath(prefix, roots["libvpx"])
    vpx_cflags = f"-O3 -I{vpx_prefix}/include"
    vpx_cxxflags = f"-O3 -DHB_NO_MT -I{vpx_prefix}/include"
    run(
        [
            "emconfigure", "./configure", f"--prefix={vpx_prefix}",
            "--target=generic-gnu",
            "--disable-install-bins", "--disable-examples", "--disable-tools",
            "--disable-docs", "--disable-unit-tests", "--disable-dependency-tracking",
            "--disable-multithread", f"--extra-cflags={vpx_cflags}",
            f"--extra-cxxflags={vpx_cxxflags}",
        ], roots["libvpx"], env
    )
    _make(roots["libvpx"], env, jobs)
    run(
        [
            "emconfigure", "./configure", *common, "--host=wasm32-unknown-emscripten",
            "--disable-asm", "--disable-rtcd", "--disable-intrinsics", "--disable-doc",
            "--disable-extra-programs", "--disable-stack-protector",
        ], roots["opus"], env
    )
    _make(roots["opus"], env, jobs)


def _build_core(state: dict[str, Any], lock: dict[str, Any]) -> None:
    emsdk: Path = state["emsdk"]
    roots: dict[str, Path] = state["roots"]
    artifacts: Path = state["artifacts"]
    run(["./emsdk", "install", lock["toolchain"]["version"]], emsdk)
    run(["./emsdk", "activate", lock["toolchain"]["version"]], emsdk)
    env = activated_emsdk_environment(emsdk)
    version = run(["emcc", "--version"], env=env, capture=True).splitlines()[0]
    if lock["toolchain"]["version"] not in version:
        raise WebEngineError(f"unexpected Emscripten version: {version}")
    prefix = state["emsdk"].parent / "prefix"
    prefix.mkdir()
    env.update(
        {
            "CFLAGS": f"-O3 -I{prefix}/include",
            "CXXFLAGS": f"-O3 -DHB_NO_MT -I{prefix}/include",
            "LDFLAGS": f"-O3 -L{prefix}/lib",
            "PKG_CONFIG_PATH": f"{prefix}/lib/pkgconfig:{prefix}/share/pkgconfig",
            "EM_PKG_CONFIG_PATH": f"{prefix}/lib/pkgconfig:{prefix}/share/pkgconfig",
        }
    )
    _configure_deps(roots, prefix, env)
    ffmpeg = roots["ffmpeg"]
    ffmpeg_prefix = os.path.relpath(prefix, ffmpeg)
    ffmpeg_cflags = f"-O3 -I{ffmpeg_prefix}/include"
    ffmpeg_cxxflags = f"-O3 -DHB_NO_MT -I{ffmpeg_prefix}/include"
    ffmpeg_ldflags = f"-O3 -L{ffmpeg_prefix}/lib"
    flags = list(lock["release_profile"]["required_flags"])
    flags += [
        "--target-os=none", "--arch=x86_32", "--enable-cross-compile", "--disable-asm",
        "--disable-stripping", "--disable-programs", "--disable-doc", "--disable-debug",
        "--disable-runtime-cpudetect", "--disable-autodetect", "--nm=emnm", "--ar=emar",
        "--ranlib=emranlib", "--cc=emcc", "--cxx=em++", "--objcc=emcc", "--dep-cc=emcc",
        f"--extra-cflags={ffmpeg_cflags}",
        f"--extra-cxxflags={ffmpeg_cxxflags}",
        f"--extra-ldflags={ffmpeg_ldflags}",
    ]
    run(["emconfigure", "./configure", *flags], ffmpeg, env)
    jobs = str(max(1, min(int(os.environ.get("II_FFMPEG_BUILD_JOBS", "4")), 8)))
    run(["emmake", "make", f"-j{jobs}"], ffmpeg, env)
    bind = roots["ffmpeg-wasm"] / "src/bind/ffmpeg/bind.js"
    initial = lock["release_profile"]["initial_memory_bytes"]
    maximum = lock["release_profile"]["maximum_memory_bytes"]
    link = [
        "emcc", "-O3", "-msimd128", "-I.", "-Ifftools", f"-I{prefix}/include",
        "-Llibavcodec", "-Llibavdevice", "-Llibavfilter", "-Llibavformat", "-Llibavutil",
        "-Llibswresample", "-Llibswscale", "-lavcodec", "-lavdevice", "-lavfilter",
        "-lavformat", "-lavutil", "-lswresample", "-lswscale",
        f"-L{prefix}/lib", "-lvpx", "-lopus", "-lass", "-lharfbuzz", "-lfribidi",
        "-lfreetype", "-lz", "-lm", "-sENVIRONMENT=worker", "-sWASM_BIGINT",
        "-sMODULARIZE", "-sEXPORT_ES6", "-sEXPORT_NAME=createFFmpegCore",
        f"-sINITIAL_MEMORY={initial}", "-sALLOW_MEMORY_GROWTH",
        f"-sMAXIMUM_MEMORY={maximum}", "-sSTACK_SIZE=5MB", "-sFILESYSTEM=1",
        "-sEXPORTED_FUNCTIONS=_ffmpeg,_abort,_malloc,_ffprobe",
        "-sEXPORTED_RUNTIME_METHODS=FS,setValue,getValue,UTF8ToString,lengthBytesUTF8,stringToUTF8",
        "-lworkerfs.js", "--pre-js", str(bind), "fftools/cmdutils.c", "fftools/ffmpeg.c",
        "fftools/ffmpeg_filter.c", "fftools/ffmpeg_hw.c", "fftools/ffmpeg_mux.c",
        "fftools/ffmpeg_opt.c", "fftools/opt_common.c", "fftools/ffprobe.c",
        "-o", str(artifacts / "ffmpeg-core.js"),
    ]
    run(link, ffmpeg, env)
    client = next(source for source in lock["sources"] if source["name"] == "ffmpeg-client")
    client_asset = roots["ffmpeg-client"] / client["asset"]
    if sha256(client_asset) != client["asset_sha256"]:
        raise WebEngineError("ffmpeg browser client asset checksum mismatch")
    shutil.copy2(client_asset, artifacts / "ffmpeg.js")
    state["ledger"]["configure_flags"] = flags
    state["ledger"]["emcc_version"] = version


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--lock", type=Path, default=Path(__file__).with_name("web_engine_lock.json"))
    args = parser.parse_args()
    try:
        lock_path = args.lock.resolve(strict=True)
        lock = json.loads(lock_path.read_text())
        state = _prepare(args.workspace, lock, lock_path)
        if not args.prepare_only:
            _build_core(state, lock)
            artifacts: Path = state["artifacts"]
            ledger = state["ledger"]
            ledger["artifacts"] = [
                {"path": name, "sha256": sha256(artifacts / name)}
                for name in lock["release_profile"]["artifacts"]
            ]
            ledger_path = artifacts / "source-ledger.json"
            ledger_path.write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n")
            verification = run(
                [sys.executable, str(Path(__file__).with_name("verify_web_engine.py")),
                 "--artifacts", str(artifacts), "--ledger", str(ledger_path),
                 "--lock", str(lock_path)], capture=True
            )
            (artifacts / "verification.json").write_text(verification + "\n")
            attestation = {
                "schema": 1, "engine_version": lock["engine_version"],
                "artifacts": ledger["artifacts"], "source_ledger_sha256": sha256(ledger_path),
                "notices_sha256": sha256(artifacts / "THIRD_PARTY_NOTICES.txt"),
                "verification_sha256": sha256(artifacts / "verification.json"),
            }
            (artifacts / "build-attestation.json").write_text(
                json.dumps(attestation, indent=2, sort_keys=True) + "\n"
            )
        print(json.dumps({"workspace": str(args.workspace), "artifacts": state["ledger"]["artifacts"]}))
        return 0
    except (KeyError, OSError, TypeError, ValueError, WebEngineError) as error:
        print(f"web engine build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
