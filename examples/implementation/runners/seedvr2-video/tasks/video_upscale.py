"""SeedVR2 video upscale to a 1080-pixel short edge through ComfyUI.

Serves the catalog id seedvr2-video-upscale. The host stages one MP4 or WebM
source at /work/in/sources/00.<ext>. Inside the container the run:

1. probes the source with ffprobe and refuses anything outside the envelope
   (30 s, 1,800 frames, 60 FPS, 4,096-pixel edge, no wider than 16:9);
2. checks each weight it is about to load against the sha256 in models.json
   and records it in the node's validation cache, so the node neither re-hashes
   nor tries to download;
3. runs the API graph in seedvr2-video-upscale.api.json, retrying in a fresh
   ComfyUI process with the next memory-saving preset only when the GPU ran out
   of memory. Resolution never drops; the last preset (FP8 weights) lowers
   quality and is used only when its optional file is present;
4. remuxes the source audio when asked, verifies frames, FPS and geometry,
   and publishes video.mp4 plus an opening-frame poster.png.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time
from typing import Any, Iterable

import runner_io

RUNNER_DIR = Path(__file__).resolve().parent.parent
GRAPH_TEMPLATE = RUNNER_DIR / "seedvr2-video-upscale.api.json"
MODELS_MANIFEST = RUNNER_DIR / "models.json"
PROFILE = "seedvr2-3b"
MODEL_FOLDER = "SEEDVR2"
# The image links the node's default model folder, /opt/ComfyUI/models/SEEDVR2,
# here (see the Dockerfile). The node keeps `.validation_cache.json` in that
# folder; the weights themselves are found through /models/SEEDVR2.
NODE_CACHE_DIR = Path("/tmp/ii-os-seedvr2-cache")
VAE_MODEL = "ema_vae_fp16.safetensors"
INPUTS = {"source_asset_id", "target_resolution", "quality_preset", "preserve_audio", "seed"}
QUALITY_PRESETS = ("quality",)
SOURCE_TYPES = {"video/mp4": ".mp4", "video/webm": ".webm"}
MAX_SOURCE_BYTES = 512 * 1024**2
MAX_SEED = 2**32 - 1
TARGET_RESOLUTION = 1080
MAX_RESOLUTION = 1920
# Every attempt shares one budget that ends before the 120-minute job timeout.
RUN_BUDGET_SECONDS = 100 * 60
LOG_TAIL_CHARS = 200_000
REQUIRED_NODE_CLASSES = {
    "LoadVideo",
    "GetVideoComponents",
    "SeedVR2LoadDiTModel",
    "SeedVR2LoadVAEModel",
    "SeedVR2VideoUpscaler",
    "CreateVideo",
    "SaveVideo",
}


@dataclass(frozen=True)
class Preset:
    name: str
    model: str = "seedvr2_ema_3b_fp16.safetensors"
    vae_tiled: bool = False
    cpu_offload: bool = False
    blocks_to_swap: int = 0
    quality_changed: bool = False


PRESETS = (
    Preset("quality"),
    Preset("vae_tiled", vae_tiled=True),
    Preset("cpu_blockswap", vae_tiled=True, cpu_offload=True, blocks_to_swap=16),
    Preset(
        "fp8_memory_saver",
        model="seedvr2_ema_3b_fp8_e4m3fn.safetensors",
        vae_tiled=True,
        cpu_offload=True,
        blocks_to_swap=16,
        quality_changed=True,
    ),
)


def plan(request: runner_io.Request) -> dict[str, Any]:
    runner_io.only(request.inputs, INPUTS)
    runner_io.text(request.inputs, "source_asset_id", max_length=64, required=False)
    target = runner_io.integer(
        request.inputs, "target_resolution", minimum=TARGET_RESOLUTION, maximum=TARGET_RESOLUTION, default=TARGET_RESOLUTION
    )
    runner_io.choice(request.inputs, "quality_preset", QUALITY_PRESETS, default="quality")
    preserve_audio = runner_io.boolean(request.inputs, "preserve_audio", default=True)
    seed = runner_io.integer(request.inputs, "seed", minimum=0, maximum=MAX_SEED, default=42)
    (video,) = runner_io.sources_of(request, "video", minimum=1, maximum=1)
    suffix = SOURCE_TYPES.get(video.content_type)
    if suffix is None or video.path.suffix.lower() != suffix:
        raise runner_io.RequestError("the source must be MP4 or WebM")
    if video.size_bytes > MAX_SOURCE_BYTES:
        raise runner_io.RequestError("the source video must be at most 512 MiB")
    return {
        "profile": PROFILE,
        "target_resolution": target,
        "preserve_audio": preserve_audio,
        "seed": seed,
        "source": str(video.path),
    }


def graph(plan: dict[str, Any], input_name: str, preset: Preset) -> dict[str, Any]:
    prompt = json.loads(GRAPH_TEMPLATE.read_text(encoding="utf-8"))
    offload = "cpu" if preset.cpu_offload else "none"
    prompt["1"]["inputs"]["file"] = input_name
    prompt["3"]["inputs"].update(
        model=preset.model, blocks_to_swap=preset.blocks_to_swap, swap_io_components=preset.cpu_offload, offload_device=offload
    )
    prompt["4"]["inputs"].update(encode_tiled=preset.vae_tiled, decode_tiled=preset.vae_tiled, offload_device=offload)
    prompt["5"]["inputs"].update(
        seed=plan["seed"], resolution=plan["target_resolution"], max_resolution=MAX_RESOLUTION, offload_device=offload
    )
    return prompt


def presets_available(models_dir: Path) -> list[Preset]:
    """Every preset on the default weights, plus FP8 only when its optional file is there."""
    default = PRESETS[0].model
    return [p for p in PRESETS if p.model == default or (models_dir / MODEL_FOLDER / p.model).is_file()]


def verify_models(models_dir: Path, filenames: Iterable[str], *, manifest_path: Path = MODELS_MANIFEST) -> dict[str, dict[str, Any]]:
    """Hash each weight against models.json; returns the node's validation-cache entries."""
    listed = json.loads(manifest_path.read_text(encoding="utf-8")).get("files", [])
    expected = {item["path"]: item for item in listed}
    entries: dict[str, dict[str, Any]] = {}
    for name in filenames:
        relative = f"{MODEL_FOLDER}/{name}"
        item = expected.get(relative)
        if item is None or not item.get("sha256"):
            raise RuntimeError(f"{relative} has no sha256 in models.json")
        path = models_dir / relative
        if not path.is_file():
            raise RuntimeError(f"{relative} is missing from the model folder; the runner never downloads weights")
        size = path.stat().st_size
        if item.get("size_bytes") is not None and size != item["size_bytes"]:
            raise RuntimeError(f"{relative} is {size} bytes; models.json expects {item['size_bytes']}")
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != item["sha256"]:
            raise RuntimeError(f"{relative} sha256 does not match models.json")
        entries[name] = {"size": size, "mtime": os.path.getmtime(path), "hash": item["sha256"]}
    return entries


def write_validation_cache(cache_dir: Path, entries: dict[str, dict[str, Any]]) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    path = cache_dir / ".validation_cache.json"
    path.write_text(json.dumps(entries, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def is_cuda_oom(text: str) -> bool:
    lowered = text.lower()
    return "out of memory" in lowered or "outofmemoryerror" in lowered or "cuda error: memory allocation" in lowered


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    import seedvr2_media as media

    started = time.monotonic()
    source = Path(plan["source"])
    source_probe = media.probe_source(source)
    media.check_source(source_probe)
    rendered, preset = _upscale(plan, source, context, deadline=started + RUN_BUDGET_SECONDS)

    output = context.output_dir / "video.mp4"
    keep_audio = bool(plan["preserve_audio"] and source_probe["has_audio"])
    remuxed = media.remux(rendered, source, output, keep_audio=keep_audio)
    audio_mode = remuxed if keep_audio else ("none" if plan["preserve_audio"] else "disabled")
    output_probe = media.probe(output)
    media.check_output(source_probe, output_probe, target=plan["target_resolution"])
    if keep_audio and not output_probe["has_audio"]:
        raise RuntimeError("the upscaled video lost the source audio")
    artifacts = [runner_io.Artifact("video.mp4", "video/mp4")]
    if media.extract_poster(output, context.output_dir / "poster.png"):
        artifacts.append(runner_io.Artifact("poster.png", "image/png", poster_for="video.mp4"))
    print(
        f"seedvr2: {source_probe['frames']} frames {source_probe['width']}x{source_probe['height']} -> "
        f"{output_probe['width']}x{output_probe['height']} with {preset.name}, audio {audio_mode}",
        flush=True,
    )
    metadata = {
        "model": preset.model,
        "vae": VAE_MODEL,
        "fallback_preset": preset.name,
        "quality_changed": preset.quality_changed,
        "target_resolution": plan["target_resolution"],
        "seed": plan["seed"],
        "audio_mode": audio_mode,
        "input": source_probe,
        "output": output_probe,
        "elapsed_seconds": round(time.monotonic() - started, 3),
    }
    return artifacts, metadata


def _upscale(plan: dict[str, Any], source: Path, context: Any, *, deadline: float) -> tuple[Path, Preset]:
    presets = presets_available(context.models_dir)
    verified: dict[str, dict[str, Any]] = {}
    for index, preset in enumerate(presets):
        missing = [name for name in (preset.model, VAE_MODEL) if name not in verified]
        verified.update(verify_models(context.models_dir, missing))
        write_validation_cache(NODE_CACHE_DIR, verified)
        scratch = context.scratch_dir / f"comfyui-{preset.name}"
        print(f"seedvr2: upscaling with the {preset.name} preset", flush=True)
        try:
            return _render(plan, preset, source, context.models_dir, scratch, deadline), preset
        except Exception as error:  # noqa: BLE001 - decide between fallback and failure
            log = _log_text(scratch)
            if index == len(presets) - 1 or not is_cuda_oom(f"{error}\n{log}"):
                print(log[-20_000:], file=sys.stderr)
                raise
            print(f"seedvr2: {preset.name} ran out of GPU memory; retrying with {presets[index + 1].name}", flush=True)
            shutil.rmtree(scratch, ignore_errors=True)
    raise RuntimeError("no SeedVR2 preset is available")


def _render(plan: dict[str, Any], preset: Preset, source: Path, models_dir: Path, scratch: Path, deadline: float) -> Path:
    from comfyui_runtime import ComfyServer, output_files

    remaining = int(deadline - time.monotonic())
    if remaining <= 60:
        raise TimeoutError("the upscale used up its time budget")
    with ComfyServer(models_dir=models_dir, scratch_dir=scratch) as server:
        name = "seedvr2-input" + source.suffix.lower()
        shutil.copyfile(source, server.input_dir / name)
        history = server.run(graph(plan, name, preset), timeout=remaining)
        videos = output_files(history, server.output_dir, (".mp4", ".webm", ".mov"))
        if not videos:
            raise RuntimeError("ComfyUI finished without writing a video")
        return videos[0]


def _log_text(scratch: Path) -> str:
    path = scratch / "comfyui.log"
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")[-LOG_TAIL_CHARS:]
