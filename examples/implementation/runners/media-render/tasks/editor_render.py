"""Render one video-editor export on a CPU runner.

The dashboard's editor compiles a timeline into a single FFmpeg invocation
before it dispatches anything (`render_manifest`), so nothing here knows what
a timeline is. The task checks that the manifest describes something this
runner will execute, puts every staged source under the exact name the
invocation uses, and runs ii-os's own `tool/render_editor_manifest.dart`
(the same renderer and safety allowlist the browser uses) from the ii-os
source tree baked into the image.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
from typing import Any

import runner_io

MAX_MANIFEST_CHARACTERS = 60_000
MAX_RENDER_INPUTS = 12
MAX_OUTPUT_BYTES = 512 * 1024**2
INPUT_NAME = re.compile(r"^input-[0-9]{1,2}\.[a-z0-9]{1,10}$")
OUTPUT_NAME = re.compile(r"^output\.[a-z0-9]{1,10}$")
# Only the types ii-os stores as workflow artifacts.
OUTPUT_TYPES = {"video/mp4": "mp4", "video/webm": "webm"}
SOURCE_ROOT = Path(os.environ.get("II_OS_SOURCE_ROOT", "/opt/ii-os"))
RENDER_TOOL = "tool/render_editor_manifest.dart"
RENDER_TIMEOUT_SECONDS = 40 * 60


def plan(request: runner_io.Request) -> dict[str, Any]:
    runner_io.only(request.inputs, {"render_manifest"})
    raw = runner_io.text(request.inputs, "render_manifest", max_length=MAX_MANIFEST_CHARACTERS)
    try:
        manifest = json.loads(raw or "")
    except json.JSONDecodeError:
        raise runner_io.RequestError("render_manifest is not JSON") from None
    _validate(manifest)
    return {
        "profile": "ffmpeg",
        "manifest": manifest,
        "output_name": manifest["outputName"],
        "media_type": manifest["mediaType"],
        "inputs": _match_sources(manifest["inputs"], request.sources),
    }


def _validate(manifest: Any) -> None:
    if not isinstance(manifest, dict) or manifest.get("version") != 1:
        raise runner_io.RequestError("render_manifest was described by another version")
    arguments = manifest.get("arguments")
    if not isinstance(arguments, list) or not arguments or any(not isinstance(item, str) for item in arguments):
        raise runner_io.RequestError("render_manifest carries no text arguments")
    output_name, media_type = manifest.get("outputName"), manifest.get("mediaType")
    if not isinstance(output_name, str) or not OUTPUT_NAME.fullmatch(output_name):
        raise runner_io.RequestError("render_manifest does not name its output")
    if media_type not in OUTPUT_TYPES or OUTPUT_TYPES[media_type] != output_name.rsplit(".", 1)[1]:
        raise runner_io.RequestError("render_manifest output type is not one ii-os stores, or disagrees with its name")
    bound = manifest.get("maxOutputBytes")
    if isinstance(bound, bool) or not isinstance(bound, int) or not 0 < bound <= MAX_OUTPUT_BYTES:
        raise runner_io.RequestError("render_manifest output bound is out of range")
    inputs = manifest.get("inputs")
    if not isinstance(inputs, list) or not 1 <= len(inputs) <= MAX_RENDER_INPUTS:
        raise runner_io.RequestError(f"a render reads 1 to {MAX_RENDER_INPUTS} files")


def _match_sources(entries: list[Any], sources: list[runner_io.Source]) -> list[dict[str, str]]:
    if len(sources) != len(entries):
        raise runner_io.RequestError("the staged sources do not match the files the render reads")
    matched = []
    seen: set[str] = set()
    for ordinal, (entry, source) in enumerate(zip(entries, sources)):
        name = entry.get("name") if isinstance(entry, dict) else None
        if not isinstance(name, str) or not INPUT_NAME.fullmatch(name) or name in seen:
            raise runner_io.RequestError(f"render input {ordinal} is not a unique input-N name")
        seen.add(name)
        declared = entry.get("byteLength")
        if (
            source.ordinal != ordinal
            or source.role != name
            or source.asset_id != entry.get("assetId")
            or (isinstance(declared, int) and declared != source.size_bytes)
        ):
            raise runner_io.RequestError(f"{name} was not staged as the asset the render was built against")
        matched.append({"name": name, "source": str(source.path)})
    return matched


def prepare_inputs(plan: dict[str, Any], scratch_dir: Path) -> Path:
    """Expose each staged source under the name the FFmpeg arguments use."""
    directory = scratch_dir / "render-inputs"
    directory.mkdir(parents=True, exist_ok=False)
    for item in plan["inputs"]:
        (directory / item["name"]).symlink_to(item["source"])
    return directory


def render_command(plan: dict[str, Any], *, manifest_file: Path, input_dir: Path, output: Path) -> tuple[list[str], dict[str, str]]:
    env = dict(os.environ)
    env.update(
        II_RENDER_MANIFEST=str(manifest_file),
        II_RENDER_INPUT_DIR=str(input_dir),
        II_RENDER_OUTPUT=str(output),
        FLUTTER_SUPPRESS_ANALYTICS="true",
        PUB_ENVIRONMENT="ii-os-kit",
        CI="true",
    )
    return ["flutter", "--suppress-analytics", "test", "--no-pub", "--reporter", "expanded", RENDER_TOOL], env


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    input_dir = prepare_inputs(plan, context.scratch_dir)
    manifest_file = context.scratch_dir / "render.json"
    manifest_file.write_text(json.dumps(plan["manifest"]), encoding="utf-8")
    output = context.output_dir / plan["output_name"]
    command, env = render_command(plan, manifest_file=manifest_file, input_dir=input_dir, output=output)
    subprocess.run(command, cwd=SOURCE_ROOT, env=env, check=True, timeout=RENDER_TIMEOUT_SECONDS)
    if not output.is_file() or output.stat().st_size == 0:
        raise RuntimeError("the renderer finished without writing the export")
    if output.stat().st_size > plan["manifest"]["maxOutputBytes"]:
        raise RuntimeError("the export is larger than the render allowed")
    return [runner_io.Artifact(plan["output_name"], plan["media_type"])], {"inputs": len(plan["inputs"])}
