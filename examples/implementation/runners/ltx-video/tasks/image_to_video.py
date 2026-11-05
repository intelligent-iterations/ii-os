"""Image-to-video with LTX-2.3 22B (fp8) through ComfyUI core nodes.

Serves the catalog id image-to-video. One staged source image becomes a
720p clip with generated audio: a half-resolution first pass, a 2x latent
upscale, and a distilled-LoRA refinement pass (graphs/image_to_video.json).
The opening frame is published beside the video as its poster.

The graph is ComfyUI's LTX-2.3 image-to-video template. Its built-in LLM
prompt enhancer stays switched off: ii-os passes the user's creative text
verbatim, and only a person may ask for a rewrite, in the ii-os UI. The
optional abliterated Gemma LoRA only feeds that enhancer branch, so the graph
names it only when the model folder holds it (ComfyUI rejects a graph that
names a missing file).
"""

from __future__ import annotations

import json
from pathlib import Path
import random
import shutil
import subprocess
from typing import Any

import runner_io

INPUTS = {"source_asset_id", "prompt", "duration_seconds", "orientation", "fps"}
SIZES = {"landscape": (1280, 720), "portrait": (720, 1280)}
SOURCE_SUFFIXES = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}
PROFILE = "ltx-2.3"
MODEL = "LTX-2.3 22B dev fp8"
ABLITERATED_LORA = "loras/gemma-3-12b-it-abliterated_lora_rank64_bf16.safetensors"
GRAPH_FILE = Path(__file__).resolve().parent.parent / "graphs" / "image_to_video.json"
# The generate job has 120 minutes; leave room for the image pull, ComfyUI
# start-up, model loading and publishing.
GENERATION_TIMEOUT_SECONDS = 90 * 60
POSTER_TIMEOUT_SECONDS = 120
POSTER_MAX_BYTES = 8 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# Node ids in graphs/image_to_video.json.
LOAD_IMAGE = "269"
SAVE_VIDEO = "75"
WIDTH, HEIGHT, DURATION, FPS = "320:312", "320:299", "320:301", "320:300"
PROMPT = "320:319"
ENHANCE_SWITCH = "320:328"
FIRST_PASS_NOISE, SECOND_PASS_NOISE = "320:277", "320:276"
TEXT_ENCODER = "320:317"
LORA_NODE = "320:324"
PROMPT_ENHANCER = "320:325"


def plan(request: runner_io.Request) -> dict[str, Any]:
    runner_io.only(request.inputs, INPUTS)
    runner_io.text(request.inputs, "source_asset_id", max_length=64, required=False)
    sources = runner_io.sources_of(request, "image", minimum=1, maximum=1)
    suffix = SOURCE_SUFFIXES.get(sources[0].content_type)
    if suffix is None:
        raise runner_io.RequestError("the source image must be PNG, JPEG or WebP")
    orientation = runner_io.choice(request.inputs, "orientation", tuple(SIZES))
    width, height = SIZES[orientation]
    return {
        "profile": PROFILE,
        "prompt": runner_io.text(request.inputs, "prompt", max_length=8000),
        "orientation": orientation,
        "size": [width, height],
        "duration_seconds": runner_io.integer(request.inputs, "duration_seconds", minimum=2, maximum=20, default=5),
        "fps": runner_io.integer(request.inputs, "fps", minimum=12, maximum=60),
        "seed": random.randrange(1, 2**48),
        "source_suffix": suffix,
    }


def graph(plan: dict[str, Any], *, image: str, abliterated_lora: bool) -> dict[str, Any]:
    nodes = json.loads(GRAPH_FILE.read_text(encoding="utf-8"))
    width, height = plan["size"]
    values = {WIDTH: width, HEIGHT: height, DURATION: plan["duration_seconds"], FPS: plan["fps"], PROMPT: plan["prompt"]}
    for node_id, value in values.items():
        nodes[node_id]["inputs"]["value"] = value
    nodes[ENHANCE_SWITCH]["inputs"]["value"] = False
    nodes[LOAD_IMAGE]["inputs"]["image"] = image
    nodes[FIRST_PASS_NOISE]["inputs"]["noise_seed"] = plan["seed"]
    nodes[SECOND_PASS_NOISE]["inputs"]["noise_seed"] = plan["seed"] + 1
    nodes[SAVE_VIDEO]["inputs"]["filename_prefix"] = "ii-os/video"
    if not abliterated_lora:
        del nodes[LORA_NODE]
        nodes[PROMPT_ENHANCER]["inputs"]["clip"] = [TEXT_ENCODER, 0]
    return nodes


def redact(message: str, prompt: str) -> str:
    """Remove the prompt from a ComfyUI diagnostic.

    ComfyUI reports a failed node with its inputs, and the shared runtime
    truncates long reports, so the prompt can appear whole, JSON-escaped, or
    cut short at the very end.
    """
    for form in (json.dumps(prompt)[1:-1], prompt):
        message = message.replace(form, "[prompt]")
        cut = next((size for size in range(min(len(form), len(message)), 0, -1) if message.endswith(form[:size])), 0)
        if cut:
            message = message[:-cut] + "[prompt]"
    return message


def write_poster(video: Path, poster: Path) -> bool:
    """Save the opening frame as a PNG. Any failure means no poster, never a failed run."""
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", str(video), "-map", "0:v:0", "-frames:v", "1", "-c:v", "png", str(poster),
    ]
    try:
        finished = subprocess.run(command, check=False, timeout=POSTER_TIMEOUT_SECONDS)
        made = finished.returncode == 0 and _is_png(poster) and poster.stat().st_size <= POSTER_MAX_BYTES
    except (OSError, subprocess.SubprocessError):
        made = False
    if not made:
        poster.unlink(missing_ok=True)
        print("image-to-video: no poster frame could be extracted; publishing the video alone")
    return made


def _is_png(path: Path) -> bool:
    if not path.is_file():
        return False
    with path.open("rb") as handle:
        return handle.read(len(PNG_SIGNATURE)) == PNG_SIGNATURE


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    from comfyui_runtime import ComfyServer, output_files

    lora = (context.models_dir / ABLITERATED_LORA).is_file()
    video = context.output_dir / "video.mp4"
    # --disable-metadata: ComfyUI would otherwise embed the whole graph,
    # prompt included, in the MP4's metadata.
    with ComfyServer(
        models_dir=context.models_dir, scratch_dir=context.scratch_dir / "comfyui", extra_args=("--disable-metadata",)
    ) as server:
        image = server.stage_input(request.sources[0].path, "source" + plan["source_suffix"])
        try:
            history = server.run(graph(plan, image=image, abliterated_lora=lora), timeout=GENERATION_TIMEOUT_SECONDS)
        except RuntimeError as error:
            raise RuntimeError(redact(str(error), plan["prompt"])) from None
        videos = output_files(history, server.output_dir, (".mp4",))
        if not videos:
            raise RuntimeError("ComfyUI finished without writing an MP4")
        shutil.copyfile(videos[0], video)
    artifacts = [runner_io.Artifact("video.mp4", "video/mp4")]
    if write_poster(video, context.output_dir / "poster.png"):
        artifacts.append(runner_io.Artifact("poster.png", "image/png", poster_for="video.mp4"))
    metadata = {
        "model": MODEL,
        "orientation": plan["orientation"],
        "duration_seconds": plan["duration_seconds"],
        "fps": plan["fps"],
        "seed": plan["seed"],
    }
    return artifacts, metadata
