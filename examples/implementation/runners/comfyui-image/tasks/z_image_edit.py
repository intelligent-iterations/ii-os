"""Image edit and inpaint with Z-Image Turbo and the Fun ControlNet Union 2.1 patch.

Serves the catalog ids image-edit (mode=edit) and image-inpaint (mode=inpaint)
from one source image. The source is scaled to at most 1024 px on its longer
side and its Canny edges condition the ControlNet patch. Edit samples a fresh
latent at that size; inpaint encodes the source with the mask (grown by 6 px),
composites the decoded result over the scaled source inside ComfyUI, and then
over the original source at the scaled size, dropping unchanged and neutral
grey filler pixels.
"""

from __future__ import annotations

from typing import Any

import runner_io

if __package__:  # imported as tasks.z_image_edit by entrypoint.py
    from . import image_edit_support as support
else:  # loaded by file path, as the unit tests do
    import image_edit_support as support

INPUTS = {"mode", "source_asset_id", "prompt", "control_strength", "seed", *support.RECT_INPUTS}
PROFILE = "z-image-turbo-controlnet"
PROMPT_LIMITS = {"edit": 30000, "inpaint": 4000}
MODEL_PATCH = "Z-Image-Turbo-Fun-Controlnet-Union-2.1.safetensors"
MAX_SIZE = 1024
STEPS = 9
CFG = 1.0
SHIFT = 3.0
CANNY = (0.1, 0.32)
MASK_GROW = 6


def plan(request: runner_io.Request) -> dict[str, Any]:
    inputs = request.inputs
    runner_io.only(inputs, INPUTS)
    mode = runner_io.choice(inputs, "mode", tuple(PROMPT_LIMITS))
    sources = support.image_sources(request, id_inputs=("source_asset_id",), maximum=1)
    if mode == "edit" and support.has_mask_input(inputs):
        raise runner_io.RequestError("edit mode does not accept a mask; use mode inpaint")
    mask = support.mask_rect(inputs)
    if mode == "inpaint" and mask is None:
        raise runner_io.RequestError("inpaint mode needs mask_x, mask_y, mask_width and mask_height")
    return {
        "profile": PROFILE,
        "mode": mode,
        "prompt": runner_io.text(inputs, "prompt", max_length=PROMPT_LIMITS[mode]),
        "control_strength": runner_io.number(inputs, "control_strength", minimum=-10, maximum=10),
        "seed": support.seed(inputs),
        "images": [support.staged_name(source) for source in sources],
        "mask": mask,
    }


def graph(plan: dict[str, Any]) -> dict[str, Any]:
    control: dict[str, Any] = {
        "model": ["5", 0], "model_patch": ["7", 0], "vae": ["6", 0], "image": ["3", 0], "strength": plan["control_strength"],
    }
    nodes: dict[str, Any] = {
        "1": {"class_type": "LoadImage", "inputs": {"image": plan["images"][0]}},
        "2": {"class_type": "ImageScaleToMaxDimension", "inputs": {"image": ["1", 0], "upscale_method": "lanczos", "largest_size": MAX_SIZE}},
        "3": {"class_type": "Canny", "inputs": {"image": ["2", 0], "low_threshold": CANNY[0], "high_threshold": CANNY[1]}},
        "4": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "lumina2", "device": "default"}},
        "5": {"class_type": "UNETLoader", "inputs": {"unet_name": "z_image_turbo_bf16.safetensors", "weight_dtype": "default"}},
        "6": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "7": {"class_type": "ModelPatchLoader", "inputs": {"name": MODEL_PATCH}},
        "8": {"class_type": "QwenImageDiffsynthControlnet", "inputs": control},
        "11": {"class_type": "CLIPTextEncode", "inputs": {"text": plan["prompt"], "clip": ["4", 0]}},
        "12": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["11", 0]}},
        "13": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["8", 0], "shift": SHIFT}},
        "14": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["13", 0], "positive": ["11", 0], "negative": ["12", 0], "latent_image": ["10", 0],
                "seed": plan["seed"], "steps": STEPS, "cfg": CFG, "sampler_name": "res_multistep", "scheduler": "simple", "denoise": 1.0,
            },
        },
        "18": {"class_type": "VAEDecode", "inputs": {"samples": ["14", 0], "vae": ["6", 0]}},
        "19": {"class_type": "SaveImage", "inputs": {"images": ["18", 0], "filename_prefix": "ii-os/image"}},
    }
    if plan["mode"] == "edit":
        nodes["9"] = {"class_type": "GetImageSize", "inputs": {"image": ["2", 0]}}
        nodes["10"] = {"class_type": "EmptySD3LatentImage", "inputs": {"width": ["9", 0], "height": ["9", 1], "batch_size": 1}}
        return nodes
    nodes["15"] = {"class_type": "LoadImage", "inputs": {"image": support.MASK_NAME}}
    nodes["16"] = {"class_type": "ImageScaleToMaxDimension", "inputs": {"image": ["15", 0], "upscale_method": "nearest-exact", "largest_size": MAX_SIZE}}
    nodes["17"] = {"class_type": "ImageToMask", "inputs": {"image": ["16", 0], "channel": "red"}}
    nodes["21"] = {"class_type": "VAEEncodeForInpaint", "inputs": {"pixels": ["2", 0], "vae": ["6", 0], "mask": ["17", 0], "grow_mask_by": MASK_GROW}}
    nodes["20"] = {
        "class_type": "ImageCompositeMasked",
        "inputs": {"destination": ["2", 0], "source": ["18", 0], "x": 0, "y": 0, "resize_source": True, "mask": ["17", 0]},
    }
    control["mask"] = ["17", 0]
    nodes["14"]["inputs"]["latent_image"] = ["21", 0]
    nodes["19"]["inputs"]["images"] = ["20", 0]
    return nodes


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    regions = [plan["mask"]] if plan["mask"] else None
    artifact = support.generate(context, graph(plan), request.sources, regions=regions, reject_grey_filler=True)
    return [artifact], {"model": "z-image-turbo-controlnet-union-2.1", "mode": plan["mode"], "seed": plan["seed"]}
