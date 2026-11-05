"""MiniMax H3 audiovisual generation: video with native stereo audio, 4-15 s, 720p.

Serves the catalog id text-to-video-minimax-h3 (the id predates the reference
modes; it serves all seven). Inputs, from the claim:

    prompt                         the scene, up to 7,000 characters, kept verbatim
    duration_seconds               whole seconds, 4 to 15 (default 15); for a
                                   continuation, the finished length
    orientation                    landscape (1280x720) or portrait (720x1280)
    fps                            24, the model's only rate
    performance_mode               quality (default) or turbo (endpoint modes only)
    generation_mode                text_to_video (default), first_frame_to_video,
                                   last_frame_to_video, first_last_frame_to_video,
                                   reference_to_video, video_edit, video_continue
    reference_manifest             asset ids, kinds, roles and ordinals of the
                                   staged references (see minimax_h3/references.py)
    edit_operation                 video_edit only; must match the manifest
    identity_replacement_consent   video_edit only; must match the manifest
    extension_method               optional; single_pass is the only method

Writes out/video.mp4 and its opening frame as out/poster.png. Reference media
outside the model's limits (each clip 2-15 s, each kind 15 s in total, a
continuation that adds under 2 s) is refused with RequestError code
`minimax_h3_reference_rejected` before ComfyUI starts.
"""

from __future__ import annotations

import importlib.metadata
import json
import random
import shutil
from typing import Any

import runner_io

from minimax_h3 import extension, graph, media, profiles, references

INPUTS = {
    "prompt", "duration_seconds", "orientation", "fps", "performance_mode", "generation_mode",
    "reference_manifest", "edit_operation", "identity_replacement_consent", "extension_method",
}
MODEL = "MiniMax H3"
# Must match COMFYUI_REVISION in the Dockerfile: the graph's core nodes are
# verified against this ComfyUI commit.
COMFYUI_REVISION = "e01fb4c56b7a88149d469b99cbbfe3223d715054"
REFERENCE_REJECTED = "minimax_h3_reference_rejected"
# The generate job allows 360 minutes; leave room for the image pull, ComfyUI
# start-up, the delivery encode and publishing. A 15-second Quality render
# measured about 33 minutes on a 24 GB GPU, and a continuation several times that.
GENERATION_TIMEOUT_SECONDS = 300 * 60
SAGE_CONFIRMED = "Using sage attention"
KITCHEN_CUDA_ENABLED = "Found comfy_kitchen backend cuda: {'available': True, 'disabled': False"


def plan(request: runner_io.Request) -> dict[str, Any]:
    inputs = request.inputs
    runner_io.only(inputs, INPUTS)
    prompt = runner_io.text(inputs, "prompt", max_length=7000)
    duration = runner_io.integer(
        inputs, "duration_seconds", minimum=profiles.MIN_DURATION_SECONDS, maximum=profiles.MAX_DURATION_SECONDS, default=15
    )
    orientation = runner_io.choice(inputs, "orientation", tuple(profiles.CANVASES))
    fps = runner_io.integer(inputs, "fps", minimum=profiles.FPS, maximum=profiles.FPS, default=profiles.FPS)
    performance = runner_io.choice(inputs, "performance_mode", tuple(profiles.PERFORMANCE_PROFILES), default="quality")
    mode = runner_io.choice(inputs, "generation_mode", references.GENERATION_MODES, default="text_to_video")
    runner_io.choice(inputs, "extension_method", extension.EXTENSION_METHODS, default="single_pass")
    profile = profiles.PERFORMANCE_PROFILES[performance]
    ref2va = mode in references.REF2VA_MODES
    if ref2va and profile.lora_name:
        raise runner_io.RequestError("Turbo serves the text and endpoint-frame modes only; use Quality for references, edits and continuations")
    try:
        manifest = references.parse_manifest(inputs.get("reference_manifest"), mode)
        references.check_declared(
            manifest, edit_operation=inputs.get("edit_operation"), consent=inputs.get("identity_replacement_consent")
        )
        references.match_sources(manifest, request.sources)
    except references.ManifestError as error:
        raise runner_io.RequestError(str(error), code=REFERENCE_REJECTED) from None
    canvas = profiles.CANVASES[orientation]
    return {
        "profile": profiles.model_profile(ref2va, profile),
        "performance_mode": performance,
        "inference_profile": profile.name,
        "generation_mode": mode,
        "orientation": orientation,
        "source_size": canvas.source,
        "delivery_size": canvas.delivery,
        "duration_seconds": duration,
        "frames": profiles.aligned_frame_count(duration, fps),
        "fps": fps,
        "seed": random.randrange(1, 2**48),
        "prompt": references.prepare_prompt(prompt, mode, manifest.references),
        "references": manifest.references,
        "edit_operation": manifest.edit_operation,
    }


def installed_version(name: str) -> str | None:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return None


def check_backends(log_text: str, *, require_kitchen: bool) -> dict[str, bool]:
    """ComfyUI logs both at start-up; check them before a long render, not after."""
    if SAGE_CONFIRMED not in log_text:
        raise RuntimeError("ComfyUI did not enable SageAttention; the image's SageAttention build does not fit this GPU")
    kitchen = KITCHEN_CUDA_ENABLED in log_text
    if require_kitchen and not kitchen:
        raise RuntimeError(
            "ComfyUI did not enable the comfy-kitchen CUDA backend the verified profile uses "
            "(set II_OS_OPTION_REQUIRE_COMFY_KITCHEN_CUDA=false to run without it)"
        )
    return {"sage_attention": True, "comfy_kitchen_cuda": kitchen}


def redact(message: str, *prompts: str) -> str:
    """Remove each prompt (whole, JSON-escaped, or cut short at the end) from a diagnostic.

    Pass both the text the person wrote and the prepared prompt the graph
    carries: an error may quote either.
    """
    for prompt in sorted({item for item in prompts if item}, key=len, reverse=True):
        for form in (json.dumps(prompt)[1:-1], prompt):
            message = message.replace(form, "[prompt]")
            cut = next((size for size in range(min(len(form), len(message)), 0, -1) if message.endswith(form[:size])), 0)
            if cut:
                message = message[:-cut] + "[prompt]"
    return message


def _measure(request: runner_io.Request, plan: dict[str, Any]) -> list[dict[str, Any]]:
    """Probe every clip and refuse what the model cannot take, before ComfyUI starts."""
    measured, durations = [], []
    for reference, source in zip(plan["references"], request.sources):
        entry: dict[str, Any] = {"kind": reference.kind, "role": reference.role, "ordinal": reference.ordinal}
        if reference.kind != "image":
            try:
                seconds, has_audio = media.media_facts(media.probe(source.path))
            except ValueError as error:
                raise runner_io.RequestError(f"reference {reference.ordinal}: {error}", code=REFERENCE_REJECTED) from None
            durations.append((reference, seconds))
            entry.update(duration_seconds=round(seconds, 3), has_audio=has_audio)
        measured.append(entry)
    try:
        references.check_durations(durations)
        if plan["generation_mode"] == "video_continue":
            source_seconds = next(seconds for reference, seconds in durations if reference.role == "source_video")
            extension.validate_extension(source_seconds, plan["duration_seconds"], plan["fps"])
    except ValueError as error:
        raise runner_io.RequestError(str(error), code=REFERENCE_REJECTED) from None
    return measured


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    from comfyui_runtime import ComfyServer, output_files

    measured = _measure(request, plan)
    sage = installed_version("sageattention")
    if sage != profiles.SAGEATTENTION_VERSION:
        raise RuntimeError(f"the image must carry SageAttention {profiles.SAGEATTENTION_VERSION}; found {sage or 'none'}")
    profile = profiles.PERFORMANCE_PROFILES[plan["performance_mode"]]
    width, height = plan["source_size"]
    require_kitchen = context.options.get("require_comfy_kitchen_cuda", "true").strip().lower() != "false"
    raw = context.scratch_dir / "raw.mp4"
    with ComfyServer(
        models_dir=context.models_dir,
        scratch_dir=context.scratch_dir / "comfyui",
        reserve_vram_gb=profiles.reserved_vram_gb(profile, plan["frames"], width, height),
        extra_args=graph.comfy_args(),
    ) as server:
        log = server.scratch / "comfyui.log"
        backends = check_backends(log.read_text(encoding="utf-8", errors="replace"), require_kitchen=require_kitchen)
        staged = [
            (reference, server.stage_input(source.path, f"ref-{reference.ordinal:02d}{source.path.suffix.lower()}"))
            for reference, source in zip(plan["references"], request.sources)
        ]
        nodes = graph.build(
            prompt=plan["prompt"], profile=profile, generation_mode=plan["generation_mode"],
            width=width, height=height, frames=plan["frames"], seed=plan["seed"], staged=staged,
        )
        if plan["generation_mode"] == "video_continue":
            source_name = next(name for reference, name in staged if reference.role == "source_video")
            extension.add_guide_graph(nodes, source_name, plan["frames"], max(int(key) for key in nodes) + 1)
        try:
            history = server.run(nodes, timeout=GENERATION_TIMEOUT_SECONDS)
        except (RuntimeError, TimeoutError) as error:
            raise RuntimeError(redact(str(error), plan["prompt"], request.inputs.get("prompt", "").strip())) from None
        videos = output_files(history, server.output_dir, (".mp4",))
        if not videos:
            raise RuntimeError("ComfyUI finished without writing an MP4")
        shutil.copyfile(videos[0], raw)
    final_width, final_height = plan["delivery_size"]
    video = context.output_dir / "video.mp4"
    media.finish_video(raw, video, width=final_width, height=final_height, fps=plan["fps"], duration=plan["duration_seconds"])
    raw.unlink(missing_ok=True)
    artifacts = [runner_io.Artifact("video.mp4", "video/mp4")]
    if media.write_poster(video, context.output_dir / "poster.png"):
        artifacts.append(runner_io.Artifact("poster.png", "image/png", poster_for="video.mp4"))
    metadata = {
        "model": MODEL,
        "generation_mode": plan["generation_mode"],
        "performance_mode": plan["performance_mode"],
        "inference_profile": plan["inference_profile"],
        "steps": profile.steps,
        "orientation": plan["orientation"],
        "width": final_width,
        "height": final_height,
        "duration_seconds": plan["duration_seconds"],
        "fps": plan["fps"],
        "seed": plan["seed"],
        "edit_operation": plan["edit_operation"],
        "references": measured,
        "comfyui_revision": COMFYUI_REVISION,
        "sageattention": sage,
        **backends,
    }
    if profile.lora_name:
        metadata["acceleration_adapter"] = {"file": profile.lora_name, "strength": profile.lora_strength}
    return artifacts, metadata

