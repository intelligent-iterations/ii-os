"""Qwen Image Edit 2511 and Qwen Image InstantX inpainting.

Serves the catalog ids image-edit-qwen-2511 and image-create-reference-qwen-2511
(mode=edit, one to three images; the first is the one edited, the others are
references) and image-inpaint-qwen (mode=inpaint, one image, a mask given as
`mask_regions` and/or the mask_x/mask_y/mask_width/mask_height rectangle;
`mask_regions` wins when both are sent).

Edit follows ComfyUI's Qwen Image Edit Plus template with the 4-step Lightning
LoRA. Inpaint follows the InstantX ControlNet inpainting template with the
Qwen-Image 4-step Lightning LoRA, a grown and blurred mask on the latent, and
a composite back over the source.
"""

from __future__ import annotations

from typing import Any

import runner_io

if __package__:  # imported as tasks.qwen_image_edit by entrypoint.py
    from . import image_edit_support as support
else:  # loaded by file path, as the unit tests do
    import image_edit_support as support

INPUTS = {"mode", "prompt", "control_strength", "seed", "mask_regions", *support.SOURCE_ID_INPUTS, *support.RECT_INPUTS}
PROFILES = {"edit": "qwen-image-edit-2511", "inpaint": "qwen-image-inpaint"}
PROMPT_LIMITS = {"edit": 30000, "inpaint": 4000}
MAX_IMAGES = {"edit": 3, "inpaint": 1}
TEXT_ENCODER = "qwen_2.5_vl_7b_fp8_scaled.safetensors"
VAE = "qwen_image_vae.safetensors"
STEPS = 4
CFG = 1.0
SHIFT = 3.1
MASK_GROW = 2
MASK_BLUR = 2


def plan(request: runner_io.Request) -> dict[str, Any]:
    inputs = request.inputs
    runner_io.only(inputs, INPUTS)
    mode = runner_io.choice(inputs, "mode", tuple(PROFILES))
    if mode == "inpaint" and any(inputs.get(name, "").strip() for name in support.SOURCE_ID_INPUTS[1:]):
        raise runner_io.RequestError("inpaint mode reads one source image; send reference images in edit mode")
    sources = support.image_sources(request, id_inputs=support.SOURCE_ID_INPUTS, maximum=MAX_IMAGES[mode])
    regions = None
    if mode == "edit" and support.has_mask_input(inputs):
        raise runner_io.RequestError("edit mode does not accept a mask; use mode inpaint")
    if mode == "inpaint":
        rect = support.mask_rect(inputs)
        regions = support.mask_regions(inputs) or ([rect] if rect else None)
        if not regions:
            raise runner_io.RequestError("inpaint mode needs mask_regions or the mask_x, mask_y, mask_width and mask_height rectangle")
    return {
        "profile": PROFILES[mode],
        "mode": mode,
        "prompt": runner_io.text(inputs, "prompt", max_length=PROMPT_LIMITS[mode]),
        # ControlNetInpaintingAliMamaApply accepts 0..10. Edit mode has no
        # ControlNet and ignores the value, as the catalog's edit ids never send it.
        "control_strength": runner_io.number(inputs, "control_strength", minimum=0, maximum=10, required=False, default=1.0),
        "seed": support.seed(inputs),
        "images": [support.staged_name(source) for source in sources],
        "mask_regions": regions,
    }


def graph(plan: dict[str, Any]) -> dict[str, Any]:
    return _edit(plan) if plan["mode"] == "edit" else _inpaint(plan)


def _edit(plan: dict[str, Any]) -> dict[str, Any]:
    negative: dict[str, Any] = {"clip": ["5", 0], "vae": ["3", 0], "image1": ["2", 0], "prompt": ""}
    positive: dict[str, Any] = {"clip": ["5", 0], "vae": ["3", 0], "image1": ["2", 0], "prompt": plan["prompt"]}
    nodes: dict[str, Any] = {
        "1": {"class_type": "LoadImage", "inputs": {"image": plan["images"][0]}},
        "2": {"class_type": "FluxKontextImageScale", "inputs": {"image": ["1", 0]}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
        "4": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_edit_2511_fp8mixed.safetensors", "weight_dtype": "default"}},
        "5": {"class_type": "CLIPLoader", "inputs": {"clip_name": TEXT_ENCODER, "type": "qwen_image", "device": "default"}},
        "6": {"class_type": "TextEncodeQwenImageEditPlus", "inputs": negative},
        "7": {"class_type": "TextEncodeQwenImageEditPlus", "inputs": positive},
        "8": {"class_type": "FluxKontextMultiReferenceLatentMethod", "inputs": {"conditioning": ["6", 0], "reference_latents_method": "index_timestep_zero"}},
        "9": {"class_type": "FluxKontextMultiReferenceLatentMethod", "inputs": {"conditioning": ["7", 0], "reference_latents_method": "index_timestep_zero"}},
        "10": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["4", 0], "shift": SHIFT}},
        "11": {"class_type": "CFGNorm", "inputs": {"model": ["10", 0], "strength": 1.0}},
        "12": {
            "class_type": "LoraLoaderModelOnly",
            "inputs": {"model": ["11", 0], "lora_name": "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors", "strength_model": 1.0},
        },
        "13": {"class_type": "VAEEncode", "inputs": {"pixels": ["2", 0], "vae": ["3", 0]}},
        "14": {"class_type": "KSampler", "inputs": _sampler(plan, model="12", positive=["9", 0], negative=["8", 0], latent="13")},
        "15": {"class_type": "VAEDecode", "inputs": {"samples": ["14", 0], "vae": ["3", 0]}},
        "16": {"class_type": "SaveImage", "inputs": {"images": ["15", 0], "filename_prefix": "ii-os/image"}},
    }
    for index, name in enumerate(plan["images"][1:], start=2):
        node_id = str(15 + index)
        nodes[node_id] = {"class_type": "LoadImage", "inputs": {"image": name}}
        negative[f"image{index}"] = [node_id, 0]
        positive[f"image{index}"] = [node_id, 0]
    return nodes


def _inpaint(plan: dict[str, Any]) -> dict[str, Any]:
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": plan["images"][0]}},
        "2": {"class_type": "LoadImage", "inputs": {"image": support.MASK_NAME}},
        "3": {"class_type": "ImageToMask", "inputs": {"image": ["2", 0], "channel": "red"}},
        "4": {"class_type": "GrowMask", "inputs": {"mask": ["3", 0], "expand": MASK_GROW, "tapered_corners": True}},
        "5": {"class_type": "MaskToImage", "inputs": {"mask": ["4", 0]}},
        "6": {"class_type": "ImageBlur", "inputs": {"image": ["5", 0], "blur_radius": MASK_BLUR, "sigma": 1.0}},
        "7": {"class_type": "ImageToMask", "inputs": {"image": ["6", 0], "channel": "red"}},
        "8": {"class_type": "FluxKontextImageScale", "inputs": {"image": ["1", 0]}},
        "9": {"class_type": "CLIPLoader", "inputs": {"clip_name": TEXT_ENCODER, "type": "qwen_image", "device": "default"}},
        "10": {"class_type": "UNETLoader", "inputs": {"unet_name": "qwen_image_fp8_e4m3fn.safetensors", "weight_dtype": "default"}},
        "11": {
            "class_type": "LoraLoaderModelOnly",
            "inputs": {"model": ["10", 0], "lora_name": "Qwen-Image-Lightning-4steps-V1.0.safetensors", "strength_model": 1.0},
        },
        "12": {"class_type": "VAELoader", "inputs": {"vae_name": VAE}},
        "13": {"class_type": "CLIPTextEncode", "inputs": {"text": plan["prompt"], "clip": ["9", 0]}},
        "14": {"class_type": "CLIPTextEncode", "inputs": {"text": " ", "clip": ["9", 0]}},
        "15": {"class_type": "ControlNetLoader", "inputs": {"control_net_name": "Qwen-Image-InstantX-ControlNet-Inpainting.safetensors"}},
        "16": {
            "class_type": "ControlNetInpaintingAliMamaApply",
            "inputs": {
                "positive": ["13", 0], "negative": ["14", 0], "control_net": ["15", 0], "vae": ["12", 0], "image": ["8", 0],
                "mask": ["7", 0], "strength": plan["control_strength"], "start_percent": 0.0, "end_percent": 1.0,
            },
        },
        "17": {"class_type": "VAEEncode", "inputs": {"pixels": ["8", 0], "vae": ["12", 0]}},
        "18": {"class_type": "SetLatentNoiseMask", "inputs": {"samples": ["17", 0], "mask": ["7", 0]}},
        "19": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["11", 0], "shift": SHIFT}},
        "20": {"class_type": "KSampler", "inputs": _sampler(plan, model="19", positive=["16", 0], negative=["16", 1], latent="18")},
        "21": {"class_type": "VAEDecode", "inputs": {"samples": ["20", 0], "vae": ["12", 0]}},
        "22": {
            "class_type": "ImageCompositeMasked",
            "inputs": {"destination": ["8", 0], "source": ["21", 0], "x": 0, "y": 0, "resize_source": True, "mask": ["7", 0]},
        },
        "23": {"class_type": "SaveImage", "inputs": {"images": ["22", 0], "filename_prefix": "ii-os/image"}},
    }


def _sampler(plan: dict[str, Any], *, model: str, positive: list, negative: list, latent: str) -> dict[str, Any]:
    return {
        "model": [model, 0], "positive": positive, "negative": negative, "latent_image": [latent, 0],
        "seed": plan["seed"], "steps": STEPS, "cfg": CFG, "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0,
    }


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    artifact = support.generate(context, graph(plan), request.sources, regions=plan["mask_regions"])
    metadata: dict[str, Any] = {"model": plan["profile"], "mode": plan["mode"], "seed": plan["seed"], "images": len(plan["images"])}
    if plan["mask_regions"]:
        metadata["mask_regions"] = len(plan["mask_regions"])
    return [artifact], metadata
