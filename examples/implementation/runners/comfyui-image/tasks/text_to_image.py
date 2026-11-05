"""Text-to-image with ComfyUI core nodes.

Serves the catalog ids image-create (Z-Image Turbo), image-create-flux2-klein
(FLUX.2 Klein 4B, distilled fp8) and image-create-qwen-2512 (Qwen-Image 2512).
The claimed `model` input selects the graph and the models.json profile.
"""

from __future__ import annotations

import random
import shutil
from typing import Any

import runner_io

INPUTS = {"prompt", "aspect_ratio", "model", "seed"}
MODELS = ("z-image-turbo", "flux2-klein", "qwen-image-2512")
SIZES = {
    "1:1": (1024, 1024),
    "16:9": (1344, 768),
    "9:16": (768, 1344),
    "4:3": (1152, 896),
    "3:4": (896, 1152),
    "3:2": (1152, 768),
    "2:3": (768, 1152),
}
QWEN_SIZES = {
    "1:1": (1328, 1328),
    "16:9": (1664, 928),
    "9:16": (928, 1664),
    "4:3": (1472, 1104),
    "3:4": (1104, 1472),
    "3:2": (1584, 1056),
    "2:3": (1056, 1584),
}
QWEN_NEGATIVE = "low quality, blurry, distorted anatomy, oversaturated, waxy skin, chaotic composition"
MAX_SEED = 2**53 - 1
GENERATION_TIMEOUT_SECONDS = 3600


def plan(request: runner_io.Request) -> dict[str, Any]:
    runner_io.only(request.inputs, INPUTS)
    if request.sources:
        raise runner_io.RequestError("text-to-image reads no source assets")
    model = runner_io.choice(request.inputs, "model", MODELS, default="z-image-turbo")
    aspect = runner_io.choice(request.inputs, "aspect_ratio", tuple(SIZES))
    width, height = (QWEN_SIZES if model == "qwen-image-2512" else SIZES)[aspect]
    seed = runner_io.integer(request.inputs, "seed", minimum=0, maximum=MAX_SEED, required=False)
    return {
        "profile": model,
        "model": model,
        "prompt": runner_io.text(request.inputs, "prompt", max_length=60000),
        "size": [width, height],
        "seed": seed if seed is not None else random.randrange(1, 2**48),
    }


def graph(plan: dict[str, Any]) -> dict[str, Any]:
    return {"z-image-turbo": _z_image, "flux2-klein": _flux2_klein, "qwen-image-2512": _qwen_image}[plan["model"]](plan)


def _z_image(plan: dict[str, Any]) -> dict[str, Any]:
    width, height = plan["size"]
    return {
        "28": {"class_type": "UNETLoader", "inputs": {"unet_name": "z_image_turbo_bf16.safetensors", "weight_dtype": "default"}},
        "30": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "lumina2", "device": "default"}},
        "29": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "27": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["30", 0], "text": plan["prompt"]}},
        "33": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["27", 0]}},
        "13": {"class_type": "EmptySD3LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "11": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["28", 0], "shift": 3}},
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["11", 0], "positive": ["27", 0], "negative": ["33", 0], "latent_image": ["13", 0],
                "seed": plan["seed"], "steps": 8, "cfg": 1, "sampler_name": "res_multistep", "scheduler": "simple", "denoise": 1,
            },
        },
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["29", 0]}},
        "9": {"class_type": "SaveImage", "inputs": {"filename_prefix": "ii-os/image", "images": ["8", 0]}},
    }


def _flux2_klein(plan: dict[str, Any]) -> dict[str, Any]:
    width, height = plan["size"]
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux-2-klein-4b-fp8.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "flux2", "device": "default"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "flux2-vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": plan["prompt"], "clip": ["2", 0]}},
        "5": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["4", 0]}},
        "6": {"class_type": "RandomNoise", "inputs": {"noise_seed": plan["seed"]}},
        "7": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "8": {"class_type": "Flux2Scheduler", "inputs": {"steps": 4, "width": width, "height": height}},
        "9": {"class_type": "CFGGuider", "inputs": {"model": ["1", 0], "positive": ["4", 0], "negative": ["5", 0], "cfg": 1.0}},
        "10": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "11": {
            "class_type": "SamplerCustomAdvanced",
            "inputs": {"noise": ["6", 0], "guider": ["9", 0], "sampler": ["7", 0], "sigmas": ["8", 0], "latent_image": ["10", 0]},
        },
        "12": {"class_type": "VAEDecode", "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
        "13": {"class_type": "SaveImage", "inputs": {"images": ["12", 0], "filename_prefix": "ii-os/image"}},
    }


def _qwen_image(plan: dict[str, Any]) -> dict[str, Any]:
    width, height = plan["size"]
    return {
        "1": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_2.5_vl_7b_fp8_scaled.safetensors", "type": "qwen_image", "device": "default"}},
        "2": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_vae.safetensors"}},
        "3": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_2512_fp8_e4m3fn.safetensors", "weight_dtype": "default"}},
        "5": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["3", 0], "shift": 3.1}},
        "6": {"class_type": "CLIPTextEncode", "inputs": {"text": plan["prompt"], "clip": ["1", 0]}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": QWEN_NEGATIVE, "clip": ["1", 0]}},
        "8": {"class_type": "EmptySD3LatentImage", "inputs": {"width": width, "height": height, "batch_size": 1}},
        "9": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["5", 0], "positive": ["6", 0], "negative": ["7", 0], "latent_image": ["8", 0],
                "seed": plan["seed"], "steps": 50, "cfg": 4.0, "sampler_name": "euler", "scheduler": "simple", "denoise": 1,
            },
        },
        "10": {"class_type": "VAEDecode", "inputs": {"samples": ["9", 0], "vae": ["2", 0]}},
        "11": {"class_type": "SaveImage", "inputs": {"images": ["10", 0], "filename_prefix": "ii-os/image"}},
    }


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    from comfyui_runtime import ComfyServer, output_files

    with ComfyServer(models_dir=context.models_dir, scratch_dir=context.scratch_dir / "comfyui") as server:
        history = server.run(graph(plan), timeout=GENERATION_TIMEOUT_SECONDS)
        images = output_files(history, server.output_dir, (".png",))
        if not images:
            raise RuntimeError("ComfyUI finished without writing a PNG")
        shutil.copyfile(images[0], context.output_dir / "image.png")
    width, height = plan["size"]
    return [runner_io.Artifact("image.png", "image/png")], {"model": plan["model"], "width": width, "height": height, "seed": plan["seed"]}
