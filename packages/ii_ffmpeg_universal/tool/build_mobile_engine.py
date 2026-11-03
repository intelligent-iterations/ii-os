#!/usr/bin/env python3
"""Build a minimal, local-only mobile FFmpeg engine from exact Git commits."""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import uuid
from pathlib import Path
from typing import Any

import attest_apple_build_tools
from mobile_engine_android_bridge import (
    adapt_android_native_bridge,
    adapt_android_wrapper_manifest,
)
from mobile_engine_android_archive import (
    android_toolchain as _android_toolchain,
    build_android_aar,
)
from mobile_engine_common import (
    BuildError,
    capture as _capture,
    clone_exact as _clone_exact,
    deterministic_zip as _deterministic_zip,
    replace_once as _replace_once,
    run as _run,
    sha256 as _sha256,
)
from mobile_engine_host_tools import prepare_host_build_tools as _prepare_host_build_tools
from mobile_engine_diagnostics import (
    BUILD_LOG_TAIL_BYTES,
    CONFIG_LOG_TAIL_BYTES,
    print_bounded_build_log as _print_bounded_build_log,
    print_bounded_config_logs as _print_bounded_config_logs,
)
from mobile_engine_sources import (
    prepare_source_destination as _prepare_source_destination,
    source_record as _source_record,
    write_notices as _write_notices,
)
from mobile_engine_patches import (
    ANDROID_FFPROBE_HEADERS_PATCHED,
    ANDROID_FFPROBE_HEADERS_UPSTREAM,
    ANDROID_HOST_TOOLCHAIN_PATCHED,
    ANDROID_HOST_TOOLCHAIN_UPSTREAM,
    ANDROID_NDK_BUILD_PATCHED,
    ANDROID_NDK_BUILD_UPSTREAM,
    LIBICONV_DEVELOPER_MANPAGES,
    LIBICONV_HTML_INSTALL,
    LIBUUID_CONFIG_INCLUDE_PATCHED,
    LIBUUID_CONFIG_INCLUDE_UPSTREAM,
    OBSOLETE_EMMS_HEADER_INSTALL,
    OBSOLETE_POSTPROC_DISABLE,
    OPTIONAL_EMMS_HEADER_INSTALL,
    X86_64_FFMPEG_CPU_PATCHED,
    X86_64_FFMPEG_CPU_UPSTREAM,
    disable_optional_freetype_brotli as _disable_optional_freetype_brotli,
    enable_meson_cross_pkg_config as _enable_meson_cross_pkg_config,
    guard_disabled_android_protocol_callbacks as _guard_disabled_android_protocol_callbacks,
    include_libuuid_config_header as _include_libuuid_config_header,
    include_android_wrapper_string_header as _include_android_wrapper_string_header,
    make_mobile_cancellation_cooperative as _make_mobile_cancellation_cooperative,
    make_removed_emms_header_optional as _make_removed_emms_header_optional,
    repair_x86_64_ffmpeg_cpu as _repair_x86_64_ffmpeg_cpu,
    support_linux_arm_ndk_build as _support_linux_arm_ndk_build,
    strip_obsolete_postproc_disable as _strip_obsolete_postproc_disable,
    strip_libiconv_developer_manpages as _strip_libiconv_developer_manpages,
    verify_android_wrapper_jni_declarations as _verify_android_wrapper_jni_declarations,
)
from web_engine_common import WebEngineError

BUILD_DATE = "20260617"


def _prepare(
    workspace: Path,
    lock: dict[str, Any],
    lock_sha256: str,
    platform: str,
    external_toolchain: dict[str, str] | None = None,
) -> tuple[Path, Path | None, dict[str, Any], Path]:
    if not workspace.is_absolute() or workspace.exists():
        raise BuildError("--workspace must be an absolute path that does not exist")
    if not workspace.parent.is_dir():
        raise BuildError("--workspace parent must already exist")
    workspace.mkdir(mode=0o700)
    marker = workspace / ".ii-disposable-owner"
    marker.write_text(f"ii-ffmpeg-mobile-engine:{uuid.uuid4()}\n", encoding="utf-8")

    recipe_spec = lock["build_recipe"]
    recipe = workspace / "ffmpeg-kit"
    _clone_exact(recipe_spec["repository"], recipe_spec["revision"], recipe)
    roots: dict[str, Path] = {"ffmpeg-kit": recipe}
    records = [
        _source_record(
            "ffmpeg-kit", recipe_spec["repository"], recipe_spec["revision"], recipe
        )
    ]
    host_build_tools, host_build_tool_sources = _prepare_host_build_tools(
        workspace, lock, platform
    )

    wrapper = None
    if platform == "android":
        wrapper_spec = lock["android_wrapper"]
        wrapper = workspace / "android-wrapper"
        _clone_exact(wrapper_spec["repository"], wrapper_spec["revision"], wrapper)
        roots["android-wrapper"] = wrapper
        records.append(
            _source_record(
                "android-wrapper",
                wrapper_spec["repository"],
                wrapper_spec["revision"],
                wrapper,
            )
        )

    for source in lock["sources"]:
        if platform not in source["platforms"]:
            continue
        name = source["name"]
        destination = _prepare_source_destination(recipe, name)
        _clone_exact(source["repository"], source["revision"], destination)
        if name == "ffmpeg":
            _run(["git", "tag", lock["engine_version"]], destination)
        roots[name] = destination
        records.append(
            _source_record(
                name,
                source["repository"],
                source["revision"],
                destination,
                source.get("license_paths"),
            )
        )

    source_script = recipe / "scripts/source.sh"
    source_text = source_script.read_text(encoding="utf-8")
    for source in lock["sources"]:
        expected_source = (
            f'  {source["name"]})\n'
            f'    SOURCE_REPO_URL="{source["repository"]}"\n'
            f'    SOURCE_ID="{source["recipe_source_id"]}"'
        )
        if source_text.count(expected_source) != 1:
            raise BuildError(
                "FFmpegKitNext source identity changed: "
                f'{source["name"]}'
            )
    engine_platform = "android" if platform == "android" else "apple"
    engine_script = recipe / "scripts" / engine_platform / "ffmpeg.sh"
    _replace_once(
        engine_script,
        "  --disable-autodetect \\\n",
        "  --disable-autodetect \\\n  --disable-network \\\n",
    )
    function_script = recipe / "scripts" / f"function-{platform}.sh"
    _replace_once(
        function_script,
        '$(date +%Y%m%d 2>>"${BASEDIR}"/build.log)',
        BUILD_DATE,
    )
    if platform == "android":
        _replace_once(
            function_script,
            ANDROID_HOST_TOOLCHAIN_UPSTREAM,
            ANDROID_HOST_TOOLCHAIN_PATCHED,
        )
        android_script = _support_linux_arm_ndk_build(
            recipe / "scripts/start-android.sh"
        )

    android_wrapper_inputs: list[Path] = []
    platform_inputs: list[Path] = []
    platform_inputs.extend(_disable_optional_freetype_brotli(recipe, platform))
    platform_inputs.append(
        _make_mobile_cancellation_cooperative(recipe, platform)
    )
    _enable_meson_cross_pkg_config(recipe, platform)
    if platform == "android":
        platform_inputs.extend(
            _strip_libiconv_developer_manpages(roots["libiconv"])
        )
        platform_inputs.append(_include_libuuid_config_header(roots["libuuid"]))
    if wrapper:
        native_source = (
            recipe
            / "android/ffmpeg-kit-next-android-lib/src/main/cpp"
        )
        android_wrapper_inputs.append(
            adapt_android_wrapper_manifest(
                wrapper,
                lock["release_profile"]["android_package"],
            )
        )
        android_wrapper_inputs.extend(
            adapt_android_native_bridge(native_source, wrapper)
        )
        _guard_disabled_android_protocol_callbacks(native_source)
        android_wrapper_inputs.append(
            _include_android_wrapper_string_header(native_source)
        )
        _verify_android_wrapper_jni_declarations(native_source)

    transformed_inputs = [
        source_script,
        engine_script,
        function_script,
        *platform_inputs,
        *android_wrapper_inputs,
    ]
    if platform == "android":
        transformed_inputs.append(android_script)

    artifacts = workspace / "artifacts"
    artifacts.mkdir()
    ledger = {
        "schema": 1,
        "platform": platform,
        "engine_version": lock["engine_version"],
        "build_date": BUILD_DATE,
        "host_build_tools": host_build_tools,
        "host_build_tool_sources": host_build_tool_sources,
        "lock_sha256": lock_sha256,
        "builder_sha256": _sha256(Path(__file__)),
        "builder_helpers": [
            {"path": name, "sha256": _sha256(Path(__file__).with_name(name))}
            for name in (
                "apple_build_tool_tree.py",
                "apple_xcode_toolchain.py",
                "attest_apple_build_tools.py",
                "mobile_engine_android_bridge.py",
                "mobile_engine_android_archive.py",
                "mobile_engine_common.py",
                "mobile_engine_diagnostics.py",
                "mobile_engine_host_tools.py",
                "mobile_engine_patches.py",
                "mobile_engine_sources.py",
                "web_engine_common.py",
            )
        ],
        "verifier_sha256": _sha256(Path(__file__).with_name("verify_mobile_engine.py")),
        "transformed_build_inputs": [
            {
                "path": path.relative_to(workspace).as_posix(),
                "sha256": _sha256(path),
            }
            for path in transformed_inputs
        ],
        "sources": records,
    }
    if external_toolchain is not None:
        ledger["external_toolchain"] = external_toolchain
    ledger_path = artifacts / "source-ledger.json"
    ledger_path.write_text(
        json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    _write_notices(records, roots, artifacts / "THIRD_PARTY_NOTICES.txt")
    return recipe, wrapper, ledger, artifacts


def _build_android(
    recipe: Path,
    wrapper: Path,
    artifacts: Path,
    android_jar: Path,
    java_version: int,
) -> list[Path]:
    _run(
        [
            "./scripts/start-android.sh",
            "--no-archive",
            "--no-ffmpeg-kit-protocols",
            "--enable-libass",
            "--enable-android-zlib",
            "--enable-android-media-codec",
        ],
        recipe,
    )
    jni = wrapper / "android/src/main/jniLibs"
    shutil.rmtree(jni)
    shutil.copytree(recipe / "android/libs", jni)
    raw = wrapper / "android/src/main/res/raw"
    raw.mkdir(parents=True, exist_ok=True)
    shutil.copy2(artifacts / "source-ledger.json", raw / "ii_ffmpeg_source_ledger.json")
    shutil.copy2(
        artifacts / "THIRD_PARTY_NOTICES.txt",
        raw / "license_ii_ffmpeg_third_party_notices.txt",
    )
    output = artifacts / "ii-ffmpeg-mobile-android.aar"
    _build_android_aar(wrapper / "android", output, android_jar, java_version)
    return [output]


def _build_android_aar(
    project: Path, output: Path, android_jar: Path, java_version: int
) -> None:
    build_android_aar(project, output, android_jar, java_version, _run)


def _build_ios(
    recipe: Path,
    artifacts: Path,
    libraries: list[str],
    minimum_version: str,
) -> list[Path]:
    if sys.platform != "darwin" or not shutil.which("xcrun"):
        raise BuildError("iOS builds require a macOS host with Xcode")
    _run(
        [
            "./scripts/start-ios.sh",
            "--xcframework",
            "--no-bitcode",
            "--disable-arm64-mac-catalyst",
            "--disable-x86-64-mac-catalyst",
            f"--target={minimum_version}",
            "--enable-libass",
            "--enable-ios-zlib",
            "--enable-ios-audiotoolbox",
            "--enable-ios-videotoolbox",
            "--enable-ios-avfoundation",
        ],
        recipe,
    )
    outputs = []
    for library in libraries:
        candidates = list((recipe / "prebuilt").rglob(f"{library}.xcframework"))
        if len(candidates) != 1:
            raise BuildError(f"expected one {library}.xcframework, found {len(candidates)}")
        output = artifacts / f"{library}.xcframework.zip"
        _deterministic_zip(candidates[0], output)
        outputs.append(output)
    return outputs


def _verify_outputs(
    platform: str, outputs: list[Path], lock_path: Path, artifacts: Path
) -> dict[str, Any]:
    command = [
        sys.executable,
        str(Path(__file__).with_name("verify_mobile_engine.py")),
        "--lock",
        str(lock_path),
        platform,
    ]
    if platform == "android":
        expected = _sha256(outputs[0])
        command.extend(
            [
                "--archive",
                str(outputs[0]),
                "--release",
                "--expected-sha256",
                expected,
            ]
        )
    else:
        for output in outputs:
            library = output.name.removesuffix(".xcframework.zip")
            command.extend(["--archive", f"{library}={output}"])
        command.append("--release")
    proof = _capture(command)
    (artifacts / "verification.json").write_text(proof + "\n", encoding="utf-8")
    value = json.loads(proof)
    if not isinstance(value, dict):
        raise BuildError("mobile engine verifier returned a non-object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=("android", "ios"))
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument(
        "--lock",
        type=Path,
        default=Path(__file__).with_name("mobile_engine_lock.json"),
    )
    parser.add_argument("--apple-build-tool-attestation", type=Path)
    parser.add_argument("--apple-formula-root", type=Path)
    args = parser.parse_args()
    try:
        lock_path = args.lock.resolve(strict=True)
        lock, lock_sha256 = attest_apple_build_tools.read_lock(lock_path)
        apple_toolchain: dict[str, str] | None = None
        if args.platform == "ios":
            if (
                args.apple_build_tool_attestation is None
                or args.apple_formula_root is None
            ):
                raise BuildError(
                    "iOS builds require an attested Apple build toolchain"
                )
            apple_digest = attest_apple_build_tools.verify_attestation(
                args.apple_build_tool_attestation,
                lock_path,
                args.apple_formula_root,
            )
            apple_toolchain = {"apple_build_tools_sha256": apple_digest}
        elif (
            args.apple_build_tool_attestation is not None
            or args.apple_formula_root is not None
        ):
            raise BuildError("Apple build-tool inputs apply only to iOS builds")
        recipe, wrapper, ledger, artifacts = _prepare(
            args.workspace,
            lock,
            lock_sha256,
            args.platform,
            apple_toolchain,
        )
        outputs: list[Path] = []
        embedded_source_ledger_sha256: str | None = None
        if not args.prepare_only:
            if args.platform == "android":
                assert wrapper is not None
                toolchain, android_jar = _android_toolchain(
                    lock["toolchains"]["android_ndk_revision"],
                    lock["toolchains"]["android_compile_sdk"],
                    lock["toolchains"]["android_java_version"],
                )
                ledger["toolchain"] = toolchain
                (artifacts / "source-ledger.json").write_text(
                    json.dumps(ledger, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                )
                embedded_source_ledger_sha256 = _sha256(
                    artifacts / "source-ledger.json"
                )
                outputs = _build_android(
                    recipe,
                    wrapper,
                    artifacts,
                    android_jar,
                    lock["toolchains"]["android_java_version"],
                )
            else:
                assert args.apple_build_tool_attestation is not None
                assert args.apple_formula_root is not None
                assert apple_toolchain is not None
                before_build = attest_apple_build_tools.verify_attestation(
                    args.apple_build_tool_attestation,
                    lock_path,
                    args.apple_formula_root,
                )
                if before_build != apple_toolchain["apple_build_tools_sha256"]:
                    raise BuildError("Apple build-tool attestation changed before build")
                outputs = _build_ios(
                    recipe,
                    artifacts,
                    lock["release_profile"]["ios_libraries"],
                    lock["toolchains"]["ios_minimum_version"],
                )
                after_build = attest_apple_build_tools.verify_attestation(
                    args.apple_build_tool_attestation,
                    lock_path,
                    args.apple_formula_root,
                )
                if after_build != before_build:
                    raise BuildError("Apple build-tool closure changed during build")
            verification = _verify_outputs(
                args.platform, outputs, lock_path, artifacts
            )
            if (
                args.platform == "android"
                and verification.get("embedded_source_ledger_sha256")
                != embedded_source_ledger_sha256
            ):
                raise BuildError("Android AAR embedded the wrong source ledger")
        ledger["artifacts"] = [
            {"path": path.name, "sha256": _sha256(path)} for path in outputs
        ]
        (artifacts / "source-ledger.json").write_text(
            json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        if outputs:
            attestation = {
                "schema": 1,
                "platform": args.platform,
                "engine_version": lock["engine_version"],
                "build_date": BUILD_DATE,
                "artifacts": ledger["artifacts"],
                "source_ledger_sha256": _sha256(
                    artifacts / "source-ledger.json"
                ),
                "notices_sha256": _sha256(artifacts / "THIRD_PARTY_NOTICES.txt"),
                "verification_sha256": _sha256(artifacts / "verification.json"),
            }
            if embedded_source_ledger_sha256 is not None:
                attestation["embedded_source_ledger_sha256"] = (
                    embedded_source_ledger_sha256
                )
            if apple_toolchain is not None:
                attestation.update(apple_toolchain)
            (artifacts / "build-attestation.json").write_text(
                json.dumps(attestation, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        print(
            json.dumps(
                {"workspace": str(args.workspace), "artifacts": ledger["artifacts"]}
            )
        )
        return 0
    except (
        attest_apple_build_tools.AttestationError,
        BuildError,
        WebEngineError,
        KeyError,
        OSError,
        TypeError,
        ValueError,
    ) as error:
        _print_bounded_build_log(args.workspace)
        _print_bounded_config_logs(args.workspace)
        print(f"mobile engine build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
