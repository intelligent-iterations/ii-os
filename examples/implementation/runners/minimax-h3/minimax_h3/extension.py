"""Continuing a MiniMax H3 video by anchoring the source inside the render.

H3 cannot continue a clip on its own: the output length comes from the latent
allocation alone and the sampler runs at full denoise, so asking in prose for a
continuation returns a fresh clip that restarts from the source's opening.

ComfyUI's `MiniMaxH3AddGuide` anchors an image batch and its soundtrack at a
chosen frame of the target video. That is the whole mechanism: allocate the
latent for the *finished* length, anchor the source at frame 0, and the model
generates the remainder continuing from it. The delivered video is one render
and one decode, so there is no seam between separately decoded segments.

`duration_seconds` is therefore the length of the finished video, source
included. Standard library only.
"""

from __future__ import annotations

from typing import Any

from minimax_h3.profiles import FPS, aligned_frame_count

MIN_EXTENSION_SECONDS = 2
# Only one method is implemented. A dispatch that asks for another is refused
# rather than silently rendered this way.
EXTENSION_METHODS = ("single_pass",)

__all__ = ["aligned_frame_count", "anchored_guide_frames", "validate_extension", "add_guide_graph"]


def anchored_guide_frames(source_frames: int) -> int:
    """How many source frames `MiniMaxH3AddGuide` actually anchors.

    The node crops a multi-frame batch down to the latent's grid and treats
    anything under five frames as a single image, so a source that short would
    silently become a still.
    """
    if source_frames < 5:
        return 1
    frames = source_frames
    while frames % 17 != 5:
        frames -= 1
    return frames


def validate_extension(source_seconds: float, total_seconds: float, fps: int = FPS) -> int:
    """Check a continuation and return the render length in frames."""
    if total_seconds - source_seconds < MIN_EXTENSION_SECONDS:
        raise ValueError(
            f"a {source_seconds:.3f}s source cannot be continued to {total_seconds:.3f}s: "
            f"a continuation adds at least {MIN_EXTENSION_SECONDS} seconds"
        )
    if anchored_guide_frames(round(source_seconds * fps)) < 5:
        raise ValueError(f"a {source_seconds:.3f}s source is too short to anchor as a clip")
    return aligned_frame_count(total_seconds, fps)


def add_guide_graph(graph: dict[str, Any], guide_name: str, length: int, next_node: int, frame_idx: int = 0) -> int:
    """Anchor `guide_name` at `frame_idx` of the render; returns the next free node id.

    The guider is repointed at the anchored conditioning (left on the bare
    conditioning, a continuation restarts instead of continuing), and the
    source soundtrack rides with the anchor so the sound carries on too.
    """
    load_node, components_node, guide_node = str(next_node), str(next_node + 1), str(next_node + 2)
    graph[load_node] = {"class_type": "LoadVideo", "inputs": {"file": guide_name}}
    graph[components_node] = {"class_type": "GetVideoComponents", "inputs": {"video": [load_node, 0]}}
    graph[guide_node] = {
        "class_type": "MiniMaxH3AddGuide",
        "inputs": {
            "positive": ["5", 0],
            "latent": ["5", 1],
            "vae": ["3", 0],
            "audio_vae": ["4", 0],
            "image": [components_node, 0],
            "audio": [components_node, 1],
            "frame_idx": frame_idx,
        },
    }
    graph["7"]["inputs"]["conditioning"] = [guide_node, 0]
    graph["5"]["inputs"]["length"] = length
    return next_node + 3
