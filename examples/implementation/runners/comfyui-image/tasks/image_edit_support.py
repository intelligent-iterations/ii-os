"""What the comfyui-image edit tasks share: source images, masks and the run.

Edit requests name their images with `source_asset_id`, `source_asset_id_2`
and `source_asset_id_3`; the claim stages those images, in that order, as
`/work/in/sources/NN.<ext>`. Each staged image is copied into ComfyUI's input
folder as `ii-os-source-NN.<ext>` for the graph's LoadImage nodes.

Inpaint masks are normalised rectangles `[x, y, width, height]` with values in
0..1 measured on the source image as displayed (EXIF orientation applied). The
mask image is drawn at run time from the validated rectangles, white where the
model may change pixels, and the result is composited back over the source so
everything outside the mask is preserved.

Standard library only at import time: PIL and ComfyUI load inside the
functions the container calls.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
import random
import shutil
from typing import Any, Mapping, Sequence

import runner_io

SOURCE_ID_INPUTS = ("source_asset_id", "source_asset_id_2", "source_asset_id_3")
RECT_INPUTS = ("mask_x", "mask_y", "mask_width", "mask_height")
MAX_SEED = 2**53 - 1
MAX_MASK_REGIONS = 32
MAX_MASK_REGIONS_LENGTH = 4096
# Clients round normalised edges; accept a ten-thousandth of overshoot.
EDGE_TOLERANCE = 1.0001
MASK_NAME = "ii-os-mask.png"
OUTPUT_NAME = "image.png"
GENERATION_TIMEOUT_SECONDS = 3600


def image_sources(request: runner_io.Request, *, id_inputs: Sequence[str], maximum: int) -> list[runner_io.Source]:
    """The staged image sources, one per named `source_asset_id*` input, in that order.

    When the staging recorded each source's asset id, it must be the id the
    matching input names; staging without ids is checked by count only.
    """
    runner_io.text(request.inputs, id_inputs[0], max_length=64)
    named = [name for name in id_inputs if runner_io.text(request.inputs, name, max_length=64, required=False)]
    sources = runner_io.sources_of(request, "image", minimum=1, maximum=maximum)
    if len(sources) != len(named):
        raise runner_io.RequestError(
            f"the request names {len(named)} source image(s) but {len(sources)} were staged"
        )
    for name, source in zip(named, sources):
        if source.asset_id and source.asset_id != request.inputs[name].strip():
            raise runner_io.RequestError(f"staged source {source.ordinal} is not the image {name} names")
    return sources


def staged_name(source: runner_io.Source) -> str:
    return f"ii-os-source-{source.ordinal:02d}{source.path.suffix.lower()}"


def seed(inputs: Mapping[str, str]) -> int:
    value = runner_io.integer(inputs, "seed", minimum=0, maximum=MAX_SEED, required=False)
    return value if value is not None else random.randrange(1, 2**48)


def has_mask_input(inputs: Mapping[str, str]) -> bool:
    return any(inputs.get(name, "").strip() for name in (*RECT_INPUTS, "mask_regions"))


def mask_rect(inputs: Mapping[str, str]) -> list[float] | None:
    """The mask_x/mask_y/mask_width/mask_height rectangle, or None when absent."""
    given = [name for name in RECT_INPUTS if inputs.get(name, "").strip()]
    if not given:
        return None
    if len(given) != len(RECT_INPUTS):
        raise runner_io.RequestError("mask_x, mask_y, mask_width and mask_height must be given together")
    values = [runner_io.number(inputs, name, minimum=0, maximum=EDGE_TOLERANCE) for name in RECT_INPUTS]
    return _checked_rect([float(value) for value in values], "mask")  # type: ignore[arg-type]


def mask_regions(inputs: Mapping[str, str]) -> list[list[float]] | None:
    """The mask_regions JSON list of up to 32 rectangles, or None when absent."""
    raw = inputs.get("mask_regions", "").strip()
    if not raw:
        return None
    problem = runner_io.RequestError(
        f"mask_regions must be a JSON list of 1 to {MAX_MASK_REGIONS} [x, y, width, height] rectangles"
    )
    if len(raw) > MAX_MASK_REGIONS_LENGTH:
        raise problem
    try:
        value = json.loads(raw)
    except ValueError:
        raise problem from None
    if not isinstance(value, list) or not 1 <= len(value) <= MAX_MASK_REGIONS:
        raise problem
    regions = []
    for region in value:
        if not isinstance(region, list) or len(region) != 4:
            raise problem
        if any(isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item) for item in region):
            raise runner_io.RequestError("mask_regions values must be finite numbers")
        regions.append(_checked_rect([float(item) for item in region], "mask_regions"))
    return regions


def _checked_rect(rect: list[float], name: str) -> list[float]:
    x, y, width, height = rect
    if min(rect) < 0:
        raise runner_io.RequestError(f"{name} values must not be negative")
    if width <= 0 or height <= 0:
        raise runner_io.RequestError(f"{name} width and height must be greater than 0")
    if x + width > EDGE_TOLERANCE or y + height > EDGE_TOLERANCE:
        raise runner_io.RequestError(f"{name} must fit inside the source image")
    return rect


def mask_boxes(regions: Sequence[Sequence[float]], width: int, height: int) -> list[tuple[int, int, int, int]]:
    """Inclusive pixel boxes for the regions on a width x height image; never empty."""
    boxes = []
    for x, y, region_width, region_height in regions:
        left, top = round(x * width), round(y * height)
        right, bottom = round((x + region_width) * width), round((y + region_height) * height)
        boxes.append((left, top, max(left + 1, right), max(top + 1, bottom)))
    return boxes


def keep_generated_pixel(source: Sequence[int], generated: Sequence[int]) -> bool:
    """Whether a generated pixel inside the mask is a real change.

    Some Z-Image inpaint runs return the whole rectangle with unchanged areas
    filled by low-saturation grey. Those pixels, and pixels the model left
    effectively unchanged, fall back to the source.
    """
    spread = max(generated) - min(generated)
    luma = sum(generated) // 3
    delta = sum(abs(int(a) - int(b)) for a, b in zip(generated, source))
    unchanged = delta < 8
    grey_filler = spread <= 30 and 32 <= luma <= 224 and delta >= 24
    return not (unchanged or grey_filler)


def draw_mask(source_path: Path, regions: Sequence[Sequence[float]], destination: Path) -> None:
    from PIL import Image, ImageDraw, ImageOps

    with Image.open(source_path) as raw:
        size = ImageOps.exif_transpose(raw).size
    mask = Image.new("RGB", size, (0, 0, 0))
    draw = ImageDraw.Draw(mask)
    for box in mask_boxes(regions, *size):
        draw.rectangle(box, fill=(255, 255, 255))
    mask.save(destination, format="PNG")


def composite(source_path: Path, mask_path: Path, generated_path: Path, output_path: Path, *, reject_grey_filler: bool) -> None:
    """Write the generated pixels inside the (softened) mask over the source."""
    from PIL import Image, ImageFilter, ImageOps

    with Image.open(source_path) as source_raw, Image.open(mask_path) as mask_raw, Image.open(generated_path) as generated_raw:
        source = ImageOps.exif_transpose(source_raw).convert("RGB")
        generated = generated_raw.convert("RGB")
        mask = mask_raw.convert("L")
    if source.size != generated.size:
        source = source.resize(generated.size, Image.Resampling.LANCZOS)
    if mask.size != generated.size:
        mask = mask.resize(generated.size, Image.Resampling.NEAREST)
    if reject_grey_filler:
        alphas = [
            alpha if alpha and keep_generated_pixel(before, after) else 0
            for before, after, alpha in zip(source.getdata(), generated.getdata(), mask.getdata())
        ]
        mask = Image.new("L", generated.size)
        mask.putdata(alphas)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=2))
    Image.composite(generated, source, mask).save(output_path, format="PNG")


def generate(
    context: Any,
    graph: Mapping[str, Any],
    sources: Sequence[runner_io.Source],
    *,
    regions: Sequence[Sequence[float]] | None = None,
    reject_grey_filler: bool = False,
) -> runner_io.Artifact:
    """Stage the sources (and mask), run the graph and write out/image.png."""
    from comfyui_runtime import ComfyServer, output_files

    with ComfyServer(models_dir=context.models_dir, scratch_dir=context.scratch_dir / "comfyui") as server:
        for source in sources:
            server.stage_input(source.path, staged_name(source))
        mask = None
        if regions:
            mask = server.input_dir / MASK_NAME
            draw_mask(sources[0].path, regions, mask)
        history = server.run(graph, timeout=GENERATION_TIMEOUT_SECONDS)
        images = output_files(history, server.output_dir, (".png",))
        if not images:
            raise RuntimeError("ComfyUI finished without writing a PNG")
        output = context.output_dir / OUTPUT_NAME
        if mask is None:
            shutil.copyfile(images[0], output)
        else:
            composite(sources[0].path, mask, images[0], output, reject_grey_filler=reject_grey_filler)
    return runner_io.Artifact(OUTPUT_NAME, "image/png")
