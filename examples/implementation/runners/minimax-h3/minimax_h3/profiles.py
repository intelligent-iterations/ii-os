"""MiniMax H3 inference profiles, model files, canvases and VRAM sizing.

Two profiles are served, chosen by the request's `performance_mode`:

    quality  native-sage-cab10: 10 steps of the CAB-2 sampler with
             SageAttention, the default
    turbo    turbo-lightx2v-4step-768p: the pinned LightX2V four-step LoRA,
             Euler, video/audio sigma shifts 6/3; endpoint modes only, because
             the adapter is trained for the FL2VA transformer

Both render a 1280x736 (or 736x1280) canvas at 24 fps, which the delivery
encode crops to 1280x720 (or 720x1280). Standard library only.
"""

from __future__ import annotations

from dataclasses import dataclass
import math

FPS = 24
MIN_DURATION_SECONDS = 4
MAX_DURATION_SECONDS = 15
SAGEATTENTION_VERSION = "2.2.0"
FFN_SEQUENCE_THRESHOLD = 4096

# File names inside the model folder (see models.json).
FL2VA_MODEL = "minimax_h3_fl2va_pruned_int8_convrot.safetensors"
REF2VA_MODEL = "minimax_h3_ref2va_pruned_int8_convrot.safetensors"
TEXT_ENCODER = "qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
VIDEO_VAE = "minimax_h3_video_vae_fp16.safetensors"
AUDIO_VAE = "minimax_h3_audio_vae_fp32.safetensors"
TURBO_LORA = "minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors"

# The sampler's activation allocation was measured at 10.71 GB for a 362-frame
# 1280x736 render on a 24 GB GPU; it scales with frames x pixels. CAB keeps the
# previous denoising state on the GPU, measured at 4.25 GB for the same render.
_REFERENCE_FRAMES = 362
_REFERENCE_PIXELS = 1280 * 736
_REFERENCE_ALLOCATION_GB = 10.71
_CAB_HISTORY_GB = 4.25
_WORKING_MARGIN_GB = 1.5
_MIN_RESERVED_GB = 4.0
_RESERVE_STEP_GB = 0.25


@dataclass(frozen=True)
class Canvas:
    source: tuple[int, int]
    delivery: tuple[int, int]


CANVASES = {
    "landscape": Canvas((1280, 736), (1280, 720)),
    "portrait": Canvas((736, 1280), (720, 1280)),
}


@dataclass(frozen=True)
class InferenceProfile:
    name: str
    steps: int
    sampler: str  # "cab-2" (the vendored CAB sampler) or a ComfyUI sampler name
    ffn_chunks: int
    qkv_chunks: int
    attention_head_chunks: int
    lora_name: str | None = None
    lora_strength: float | None = None
    video_shift: float | None = None
    audio_shift: float | None = None


PERFORMANCE_PROFILES = {
    "quality": InferenceProfile("native-sage-cab10", 10, "cab-2", 4, 8, 4),
    "turbo": InferenceProfile(
        "turbo-lightx2v-4step-768p", 4, "euler", 4, 8, 4,
        lora_name=TURBO_LORA, lora_strength=1.0, video_shift=6.0, audio_shift=3.0,
    ),
}


def aligned_frame_count(seconds: float, fps: int = FPS) -> int:
    """Round a duration up onto H3's `17k + 5` latent frame grid."""
    frames = max(5, round(seconds * fps))
    return frames + (5 - frames % 17) % 17


def reserved_vram_gb(profile: InferenceProfile, frames: int, width: int, height: int) -> float:
    """VRAM ComfyUI keeps free for the sampler, so streamed weights cannot take it."""
    if frames <= 0 or width <= 0 or height <= 0:
        raise ValueError("frame count and canvas dimensions must be positive")
    scale = frames * width * height / _REFERENCE_FRAMES / _REFERENCE_PIXELS
    reserved = _round_up(max(_MIN_RESERVED_GB, scale * _REFERENCE_ALLOCATION_GB + _WORKING_MARGIN_GB))
    if profile.sampler == "cab-2":
        reserved = _round_up(reserved + scale * _CAB_HISTORY_GB)
    return reserved


def _round_up(value: float) -> float:
    return math.ceil(value / _RESERVE_STEP_GB) * _RESERVE_STEP_GB


def model_profile(ref2va: bool, profile: InferenceProfile) -> str:
    """The models.json profile a render reads."""
    if ref2va and profile.lora_name:
        raise ValueError("Turbo serves the text and endpoint-frame modes only")
    if ref2va:
        return "ref2va"
    return "fl2va-turbo" if profile.lora_name else "fl2va"


def diffusion_model(ref2va: bool) -> str:
    return REF2VA_MODEL if ref2va else FL2VA_MODEL
