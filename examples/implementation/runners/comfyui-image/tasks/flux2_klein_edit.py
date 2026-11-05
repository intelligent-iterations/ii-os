"""Image edit with FLUX.2 Klein 4B base (fp8) and the FLUX.2 small decoder.

Serves the catalog ids image-edit-flux2-klein and
image-create-reference-flux2-klein (mode=edit, one or two images). This is
ComfyUI's FLUX.2 Klein 4B base image-edit template: each image is scaled to
about one megapixel and VAE-encoded as a reference latent on both the prompt
and the empty negative conditioning; the output takes the first image's
scaled size. The base model samples 20 steps at CFG 5.
"""

from __future__ import annotations

from typing import Any

import runner_io

if __package__:  # imported as tasks.flux2_klein_edit by entrypoint.py
    from . import image_edit_support as support
else:  # loaded by file path, as the unit tests do
    import image_edit_support as support

SOURCE_IDS = support.SOURCE_ID_INPUTS[:2]
# control_strength is declared because the dashboard's storyboard sends it to
# every image-edit template; this model has no control input, so it is only
# validated, never used.
INPUTS = {"mode", "prompt", "seed", "control_strength", *SOURCE_IDS}
PROFILE = "flux2-klein-base-edit"
MEGAPIXELS = 1.0
STEPS = 20
CFG = 5.0


def plan(request: runner_io.Request) -> dict[str, Any]:
    inputs = request.inputs
    runner_io.only(inputs, INPUTS)
    mode = runner_io.choice(inputs, "mode", ("edit",))
    runner_io.number(inputs, "control_strength", minimum=-10, maximum=10, required=False)
    sources = support.image_sources(request, id_inputs=SOURCE_IDS, maximum=len(SOURCE_IDS))
    return {
        "profile": PROFILE,
        "mode": mode,
        "prompt": runner_io.text(inputs, "prompt", max_length=30000),
        "seed": support.seed(inputs),
        "images": [support.staged_name(source) for source in sources],
    }


def graph(plan: dict[str, Any]) -> dict[str, Any]:
    nodes: dict[str, Any] = {
        "1": {"class_type": "LoadImage", "inputs": {"image": plan["images"][0]}},
        "2": {"class_type": "ImageScaleToTotalPixels", "inputs": _scale(["1", 0])},
        "3": {"class_type": "GetImageSize", "inputs": {"image": ["2", 0]}},
        "4": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux-2-klein-base-4b-fp8.safetensors", "weight_dtype": "default"}},
        "5": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "flux2", "device": "default"}},
        "6": {"class_type": "VAELoader", "inputs": {"vae_name": "full_encoder_small_decoder.safetensors"}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"text": plan["prompt"], "clip": ["5", 0]}},
        "8": {"class_type": "CLIPTextEncode", "inputs": {"text": "", "clip": ["5", 0]}},
        "9": {"class_type": "VAEEncode", "inputs": {"pixels": ["2", 0], "vae": ["6", 0]}},
        "10": {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["7", 0], "latent": ["9", 0]}},
        "11": {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["8", 0], "latent": ["9", 0]}},
        "12": {"class_type": "RandomNoise", "inputs": {"noise_seed": plan["seed"]}},
        "13": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "14": {"class_type": "Flux2Scheduler", "inputs": {"steps": STEPS, "width": ["3", 0], "height": ["3", 1]}},
        "15": {"class_type": "CFGGuider", "inputs": {"model": ["4", 0], "positive": ["10", 0], "negative": ["11", 0], "cfg": CFG}},
        "16": {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": ["3", 0], "height": ["3", 1], "batch_size": 1}},
        "17": {
            "class_type": "SamplerCustomAdvanced",
            "inputs": {"noise": ["12", 0], "guider": ["15", 0], "sampler": ["13", 0], "sigmas": ["14", 0], "latent_image": ["16", 0]},
        },
        "18": {"class_type": "VAEDecode", "inputs": {"samples": ["17", 0], "vae": ["6", 0]}},
        "19": {"class_type": "SaveImage", "inputs": {"images": ["18", 0], "filename_prefix": "ii-os/image"}},
    }
    if len(plan["images"]) > 1:
        nodes["20"] = {"class_type": "LoadImage", "inputs": {"image": plan["images"][1]}}
        nodes["21"] = {"class_type": "ImageScaleToTotalPixels", "inputs": _scale(["20", 0])}
        nodes["22"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["21", 0], "vae": ["6", 0]}}
        nodes["23"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["10", 0], "latent": ["22", 0]}}
        nodes["24"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": ["11", 0], "latent": ["22", 0]}}
        nodes["15"]["inputs"].update(positive=["23", 0], negative=["24", 0])
    return nodes


def _scale(image: list) -> dict[str, Any]:
    return {"image": image, "upscale_method": "nearest-exact", "megapixels": MEGAPIXELS, "resolution_steps": 1}


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    artifact = support.generate(context, graph(plan), request.sources)
    return [artifact], {"model": "flux2-klein-base-4b", "mode": plan["mode"], "seed": plan["seed"], "images": len(plan["images"])}
