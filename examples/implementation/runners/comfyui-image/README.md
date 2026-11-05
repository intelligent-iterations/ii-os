# comfyui-image runner

Image generation and editing through a headless [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
at a pinned commit. One image serves several catalog entries; the workflow
passes `--task` and the claimed request picks the model profile.

| Task | Catalog ids | Workflow |
| --- | --- | --- |
| `text-to-image` | `image-create`, `image-create-flux2-klein`, `image-create-qwen-2512` | `.github/workflows/z-image-turbo-text-to-image.yml` |
| `z-image-edit` | `image-edit`, `image-inpaint` | `.github/workflows/z-image-edit.yml` |
| `qwen-image-edit` | `image-edit-qwen-2511`, `image-create-reference-qwen-2511`, `image-inpaint-qwen` | `.github/workflows/qwen-image-edit.yml` |
| `flux2-klein-edit` | `image-edit-flux2-klein`, `image-create-reference-flux2-klein` | `.github/workflows/flux2-klein-image-edit.yml` |

The edit tasks read their source images from the claim (`source_asset_id`,
then `source_asset_id_2` and `source_asset_id_3`, in that order) and write one
PNG. `mode` is `edit` or `inpaint`:

- `z-image-edit` reads one image. Edit conditions Z-Image Turbo on the
  image's Canny edges through the Fun ControlNet Union 2.1 patch at
  `control_strength` (-10 to 10). Inpaint also needs the normalised rectangle
  `mask_x`, `mask_y`, `mask_width`, `mask_height` (0 to 1, measured on the
  image as displayed).
- `qwen-image-edit` edits the first of up to three images with Qwen Image
  Edit 2511; the others are references. Inpaint reads exactly one image and a
  mask given as `mask_regions`, a JSON list of up to 32 `[x, y, width, height]`
  rectangles, and/or the single `mask_*` rectangle; `mask_regions` wins when
  both are sent. `control_strength` (0 to 10, default 1) drives the InstantX
  inpainting ControlNet.
- `flux2-klein-edit` edits the first of up to two images with FLUX.2 Klein 4B
  base; the second is a reference. `mode` must be `edit`.

Inpaint results are composited back over the source, so pixels outside the
mask are unchanged; the output is at the size the model worked at (about one
megapixel, or 1024 px on the longer side for Z-Image).

## Hardware

An NVIDIA GPU with 24 GB of VRAM, a driver that supports CUDA 13.0, the
NVIDIA Container Toolkit, and about 32 GB of free RAM for the larger Qwen
models (the Qwen edit and inpaint profiles load a 20 GB diffusion model and a
9.4 GB text encoder). The container's `/tmp` is a RAM-backed scratch area.

## Build the image

From the kit root (the build needs `runners/common/`):

```bash
docker build -f runners/comfyui-image/Dockerfile -t registry.example.com/ii-os/comfyui-image:2026-11 .
docker push registry.example.com/ii-os/comfyui-image:2026-11
```

Set the repository variable `II_OS_RUNNER_IMAGE_COMFYUI_IMAGE` to the pushed
image pinned by digest, for example
`registry.example.com/ii-os/comfyui-image@sha256:<digest>`. Rebuild and update
the variable whenever anything under `runners/comfyui-image/` or
`runners/common/` changes, because the workflow plans with the checked-out
code and runs with the image.

The base image is pinned by digest, ComfyUI by commit, and every Python
package by version and sha256: PyTorch's CUDA 13.0 builds from PyPI and ComfyUI's requirements at that commit included.

### Python dependencies

The Dockerfile installs every Python package with
`pip install --require-hashes --no-deps` from two files in this folder, each
pinning an exact version and sha256 per package:

- `requirements.lock.txt`: everything the runner imports, compiled from `requirements.in` (PyTorch, then ComfyUI's `requirements.txt` at `COMFYUI_REVISION`) for CPython 3.12 (Ubuntu 24.04's Python) on x86-64 Linux, from PyPI.
- `requirements-build.lock.txt`: pip, setuptools and wheel, installed first.

The release dependency scan (osv-scanner) reads both files, so it checks what
the image installs. After changing a pin in `requirements.in` or a revision in
the Dockerfile, delete both files and recompile them from the kit root with
[uv](https://docs.astral.sh/uv/), using the commands at the top of
`requirements.in` (runtime lock first: it constrains the build lock), then
rebuild the image. Keep `--exclude-newer` at least a week back, so no release
younger than that enters a lock.

## Model folder

The container reads models only from `${II_OS_MODEL_ROOT}/comfyui-image/`,
mounted read-only at `/models`. It never downloads anything and has no network.
Lay the folder out exactly as the `path` values in [`models.json`](models.json):

```text
${II_OS_MODEL_ROOT}/comfyui-image/
  diffusion_models/z_image_turbo_bf16.safetensors
  text_encoders/qwen_3_4b.safetensors
  vae/ae.safetensors
  ...
```

List every file with its size, license and pinned source URL:

```bash
python3 scripts/ii_os_model_folder.py list --manifest runners/comfyui-image/models.json
```

Fetch them yourself, once, onto the GPU host (each `source` is pinned to an
upstream commit), then verify a profile end to end:

```bash
python3 scripts/ii_os_model_folder.py verify --manifest runners/comfyui-image/models.json \
  --model-root "$II_OS_MODEL_ROOT" --profile z-image-turbo
```

`verify` hashes every file that has a `sha256`; the workflow's per-run `check`
only confirms presence and size. Symlinks are fine as long as they resolve
inside the runner folder, because nothing outside it is mounted.

| Profile | Files | Approximate size |
| --- | --- | --- |
| `z-image-turbo` | Z-Image Turbo bf16, Qwen3 4B text encoder, VAE | 20.7 GB |
| `flux2-klein` | FLUX.2 Klein 4B fp8, Qwen3 4B text encoder, FLUX.2 VAE | 12.5 GB |
| `qwen-image-2512` | Qwen-Image 2512 fp8, Qwen2.5-VL 7B fp8 text encoder, VAE | 30.1 GB |
| `z-image-turbo-controlnet` | the `z-image-turbo` files plus the Z-Image Turbo Fun ControlNet Union 2.1 patch | 27.4 GB |
| `qwen-image-edit-2511` | Qwen Image Edit 2511 fp8 (mixed), its 4-step Lightning LoRA, Qwen2.5-VL 7B fp8 text encoder, VAE | 31.0 GB |
| `qwen-image-inpaint` | Qwen-Image fp8, InstantX inpainting ControlNet, Qwen-Image 4-step Lightning LoRA, Qwen2.5-VL 7B fp8 text encoder, VAE | 36.0 GB |
| `flux2-klein-base-edit` | FLUX.2 Klein 4B base fp8, Qwen3 4B text encoder, FLUX.2 small decoder | 12.4 GB |

Profiles share files (the text encoders and VAEs), so every profile together
is about 114 GB on disk.

## Licenses

Every file's upstream license is in `models.json`; check it against your use
before you download. Notes worth reading first:

- The FLUX.2 VAE is listed from the Apache-2.0 FLUX.2 Klein repository. A
  copy in the `flux2-dev` repository falls under the non-commercial
  FLUX.2 [dev] license; do not substitute it for commercial use.
- The Qwen-Image 2512 Lightning LoRA is not needed: the graph samples the
  base model directly.
- The Qwen2.5-VL 7B text encoder is listed from the Apache-2.0
  `Comfy-Org/Qwen-Image_ComfyUI` repository. A byte-identical copy is also
  published in `Comfy-Org/HunyuanVideo_1.5_repackaged`, whose repository
  license is the Tencent Hunyuan community license, which does not apply in
  the European Union, the United Kingdom or South Korea; fetch the Apache-2.0
  copy.
- Every file the edit profiles add (the Z-Image Fun ControlNet patch, Qwen
  Image Edit 2511, the Lightning LoRAs, the InstantX inpainting ControlNet,
  FLUX.2 Klein 4B base and the FLUX.2 small decoder) is published under
  Apache-2.0 at the pinned revision.

The image uses Python 3.12, PyTorch 2.13 and CUDA 13.0. The GPU host must
support CUDA 13.0. Rebuild after updating these locks and verify each required
profile on the target GPU before deployment; dependency resolution and static
scans do not prove rendering compatibility.
