"""The ComfyUI API graph for one MiniMax H3 render, and the server flags.

Node ids:

     1 UNETLoader (FL2VA or Ref2VA transformer)   9 BasicScheduler
     2 CLIPLoader (Qwen3-VL text encoder)        10 SamplerCustomAdvanced
     3 VAELoader (video)  4 VAELoader (audio)    11 VAEDecode  12 VAEDecodeAudio
     5 MiniMaxH3ImageToVideo / ReferenceToVideo  13 CreateVideo  14 SaveVideo
     6 RandomNoise  7 BasicGuider  8 sampler     15 the low-memory patch
    16 Turbo LoRA  17 Turbo sigma shift          20+ loaded references

Every node is a ComfyUI core node at the pinned commit except the two from the
vendored `comfy_nodes/ii_os_minimax_h3` package: the exact low-memory patch
(chunked feed-forward, QKV projection and attention heads, so a 15-second
render fits a 24 GB GPU) and the CAB-2 low-step sampler.
"""

from __future__ import annotations

from typing import Any, Sequence

from minimax_h3 import references
from minimax_h3.profiles import (
    AUDIO_VAE,
    FFN_SEQUENCE_THRESHOLD,
    FPS,
    TEXT_ENCODER,
    VIDEO_VAE,
    InferenceProfile,
    diffusion_model,
)

CUSTOM_NODES = "ii_os_minimax_h3"
LOW_MEMORY = "IiOsMiniMaxH3LowMemory"
CAB_SAMPLER = "IiOsMiniMaxH3CABSampler"


def build(
    *,
    prompt: str,
    profile: InferenceProfile,
    generation_mode: str,
    width: int,
    height: int,
    frames: int,
    seed: int,
    staged: Sequence[tuple[references.Reference, str]] = (),
) -> dict[str, Any]:
    ref2va = generation_mode in references.REF2VA_MODES
    if ref2va and profile.lora_name:
        raise ValueError("Turbo serves the text and endpoint-frame modes only")
    if profile.lora_name:
        low_memory_input, model = ["16", 0], ["17", 0]
    else:
        low_memory_input, model = ["1", 0], ["15", 0]
    if profile.sampler == "cab-2":
        sampler = {"class_type": CAB_SAMPLER, "inputs": {"order": "CAB-2", "theta": 0.2}}
    else:
        sampler = {"class_type": "KSamplerSelect", "inputs": {"sampler_name": profile.sampler}}
    nodes: dict[str, Any] = {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": diffusion_model(ref2va), "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": TEXT_ENCODER, "type": "minimax", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": VIDEO_VAE}},
        "4": {"class_type": "VAELoader", "inputs": {"vae_name": AUDIO_VAE}},
        "5": {
            "class_type": "MiniMaxH3ImageToVideo",
            "inputs": {"clip": ["2", 0], "vae": ["3", 0], "prompt": prompt, "width": width, "height": height, "length": frames},
        },
        "6": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "7": {"class_type": "BasicGuider", "inputs": {"model": model, "conditioning": ["5", 0]}},
        "8": sampler,
        "9": {"class_type": "BasicScheduler", "inputs": {"model": model, "scheduler": "simple", "steps": profile.steps, "denoise": 1.0}},
        "10": {
            "class_type": "SamplerCustomAdvanced",
            "inputs": {"noise": ["6", 0], "guider": ["7", 0], "sampler": ["8", 0], "sigmas": ["9", 0], "latent_image": ["5", 1]},
        },
        "11": {"class_type": "VAEDecode", "inputs": {"samples": ["10", 0], "vae": ["3", 0]}},
        "12": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["10", 0], "vae": ["4", 0]}},
        "13": {"class_type": "CreateVideo", "inputs": {"images": ["11", 0], "audio": ["12", 0], "fps": float(FPS), "bit_depth": 8}},
        "14": {
            "class_type": "SaveVideo",
            "inputs": {
                "video": ["13", 0],
                "filename_prefix": "ii-os/raw",
                "format": "mp4",
                # DynamicCombo inputs use flattened API keys; ComfyUI rebuilds
                # them into the nested codec argument SaveVideo takes.
                "codec": "h264",
                "codec.encoding": "re-encode",
                "codec.encoding.crf": 16.0,
            },
        },
        "15": {
            "class_type": LOW_MEMORY,
            "inputs": {
                "model": low_memory_input,
                "chunks": profile.ffn_chunks,
                "qkv_chunks": profile.qkv_chunks,
                "attention_head_chunks": profile.attention_head_chunks,
                "sequence_threshold": FFN_SEQUENCE_THRESHOLD,
            },
        },
    }
    if profile.lora_name:
        nodes["16"] = {
            "class_type": "LoraLoaderModelOnly",
            "inputs": {"model": ["1", 0], "lora_name": profile.lora_name, "strength_model": profile.lora_strength},
        }
        nodes["17"] = {
            "class_type": "MiniMaxH3SigmaShift",
            "inputs": {"model": ["15", 0], "shift_video": profile.video_shift, "shift_audio": profile.audio_shift},
        }
    references.add_conditioning(nodes, generation_mode, staged)
    return nodes


def comfy_args() -> list[str]:
    """ComfyUI flags beyond the ones the shared runtime sets (listen, folders, reserve).

    Only the vendored node package loads. Weights stream from the model folder
    (dynamic VRAM, fast disk) with smart memory off, so the sampler keeps the
    reserved headroom; nothing is cached between runs; no previews; and the
    raw render carries no prompt metadata.
    """
    return [
        "--disable-all-custom-nodes",
        "--whitelist-custom-nodes", CUSTOM_NODES,
        "--enable-dynamic-vram",
        "--disable-smart-memory",
        "--fast-disk",
        "--cache-none",
        "--preview-method", "none",
        "--use-sage-attention",
        "--disable-metadata",
    ]
