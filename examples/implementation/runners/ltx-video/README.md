# ltx-video runner

Image-to-video with [LTX-2.3](https://huggingface.co/Lightricks/LTX-2.3) 22B
(fp8) through a headless [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
at a pinned commit. One staged source image becomes a 720p MP4 with generated
audio, published with its opening frame as a poster.

| Task | Catalog id | Workflow |
| --- | --- | --- |
| `image-to-video` | `image-to-video` | `.github/workflows/ltx-image-to-video.yml` |

## Request

| Input | Accepted values |
| --- | --- |
| `prompt` | the motion description, up to 8000 characters, used verbatim |
| `orientation` | `landscape` (1280x720) or `portrait` (720x1280) |
| `duration_seconds` | whole seconds from 2 to 20 (default 5) |
| `fps` | whole frames per second from 12 to 60 |
| `source_asset_id` | the source image; the claim stages exactly one PNG, JPEG or WebP |

Each run picks a random seed and reports it in `out/result.json` metadata.
The runner refuses any other input, a missing or second source, and a source
that is not an image, before any image is pulled or model loaded.

## What the graph does

[`graphs/image_to_video.json`](graphs/image_to_video.json) is ComfyUI's
LTX-2.3 image-to-video template in API form, with every request value blanked
and filled in at run time. It samples at half resolution, upscales the latent
2x with the spatial upscaler, refines with the distilled LoRA, then decodes
video and audio and saves an H.264 MP4. Every node in it is a ComfyUI core
node at the pinned commit.

Three deliberate departures from the template:

- **Prompt enhancement is always off.** The template can rewrite the prompt
  with the Gemma text encoder before encoding it. ii-os passes the user's
  creative text verbatim and only a person may ask for a rewrite, in the
  ii-os UI, so this runner never switches that branch on.
- **No prompt in outputs.** The template's text preview node is removed, and
  ComfyUI runs with `--disable-metadata`, so the MP4 does not embed the graph
  (and the prompt) in its metadata. ComfyUI error reports echo node inputs;
  the runner removes the prompt from them before they reach the job log.
- **The abliterated Gemma LoRA is optional.** It only feeds the enhancer
  branch, so the graph names it only when the model folder holds it.

The poster is the first frame, extracted with ffmpeg as a PNG of at most
8 MiB. If it cannot be made, the video is published alone.

## Hardware

An NVIDIA GPU with 24 GB of VRAM, a driver that supports CUDA 13.0, and the
NVIDIA Container Toolkit. The fp8 checkpoint alone is about 29 GB, larger
than the GPU, so ComfyUI keeps part of the weights in system RAM: size RAM
for roughly 42 GB of weights on top of the operating system. Generation time
grows with duration and frame rate; the generate job allows 120 minutes and
ComfyUI 90 of them. The container's `/tmp` is a RAM-backed scratch area.

## Build the image

From the kit root (the build needs `runners/common/`):

```bash
docker build -f runners/ltx-video/Dockerfile -t registry.example.com/ii-os/ltx-video:2026-11 .
docker push registry.example.com/ii-os/ltx-video:2026-11
```

Set the repository variable `II_OS_RUNNER_IMAGE_LTX_VIDEO` to the pushed
image pinned by digest, for example
`registry.example.com/ii-os/ltx-video@sha256:<digest>`. Rebuild and update
the variable whenever anything under `runners/ltx-video/` or `runners/common/`
changes, because the workflow plans with the checked-out code and runs with
the image.

The base image is pinned by digest, ComfyUI and each custom node pack by
commit, and every Python package by version and sha256: PyTorch's CUDA 13.0
builds and the `requirements.txt` of ComfyUI and each node pack at those
commits included.

The image also installs ComfyUI-LTXVideo, ComfyUI-KJNodes and
ComfyUI-VideoHelperSuite at the commits the graph was verified alongside.
The graph does not use them at this ComfyUI commit; for a smaller image,
remove that build step and their lines in `requirements.in`, then recompile
the locks.

### Python dependencies

The Dockerfile installs every Python package with
`pip install --require-hashes --no-deps` from two files in this folder, each
pinning an exact version and sha256 per package:

- `requirements.lock.txt`: everything the runner imports, compiled from `requirements.in` (PyTorch, ComfyUI's and the three node packs' requirements at their revisions, kornia held at 0.8.2) for CPython 3.12 (Ubuntu 24.04's Python) on x86-64 Linux, from PyPI.
- `requirements-build.lock.txt`: pip, setuptools and wheel, installed first.

The release dependency scan (osv-scanner) reads both files, so it checks what
the image installs. After changing a pin in `requirements.in` or a revision in
the Dockerfile, delete both files and recompile them from the kit root with
[uv](https://docs.astral.sh/uv/), using the commands at the top of
`requirements.in` (runtime lock first: it constrains the build lock), then
rebuild the image. Keep `--exclude-newer` at least a week back, so no release
younger than that enters a lock.

## Model folder

The container reads models only from `${II_OS_MODEL_ROOT}/ltx-video/`,
mounted read-only at `/models`. It never downloads anything and has no
network. Lay the folder out exactly as the `path` values in
[`models.json`](models.json):

```text
${II_OS_MODEL_ROOT}/ltx-video/
  checkpoints/ltx-2.3-22b-dev-fp8.safetensors
  text_encoders/gemma_3_12B_it_fp4_mixed.safetensors
  latent_upscale_models/ltx-2.3-spatial-upscaler-x2-1.1.safetensors
  loras/ltx_2.3_22b_distilled_1.1_lora_dynamic_fro09_avg_rank_111_bf16.safetensors
```

List every file with its size, license and pinned source URL:

```bash
python3 scripts/ii_os_model_folder.py list --manifest runners/ltx-video/models.json
```

Fetch them yourself, once, onto the GPU host (each `source` is pinned to an
upstream commit), then verify the profile end to end:

```bash
python3 scripts/ii_os_model_folder.py verify --manifest runners/ltx-video/models.json \
  --model-root "$II_OS_MODEL_ROOT" --profile ltx-2.3
```

`verify` hashes every file that has a `sha256`; the workflow's per-run
`check` only confirms presence and size, and reports the optional LoRA as a
notice when it is absent. Symlinks are fine as long as they resolve inside
the runner folder, because nothing outside it is mounted.

| Profile | Files | Approximate size |
| --- | --- | --- |
| `ltx-2.3` | LTX-2.3 22B dev fp8, Gemma 3 12B fp4 text encoder, x2 spatial upscaler, distilled 1.1 LoRA | 42.3 GB |
| `ltx-2.3` (optional) | abliterated Gemma 3 12B LoRA | 0.6 GB |

## Licenses

Every file's upstream license is in `models.json`; read it against your use
before you download. These weights are open, not open source:

- **LTX-2 Community License Agreement** (the checkpoint, upscaler and
  distilled LoRA; [text](https://github.com/Lightricks/LTX-2/blob/main/LICENSE-2)).
  An entity whose annual revenue, counted with its affiliates, is US$10
  million or more needs a paid commercial license from Lightricks.
  Attachment A restricts how the model and its outputs may be used, and if
  you host it for others your terms must pass those restrictions on. They
  include labelling machine-generated content, no impersonation without
  consent, no circumventing the model's safety features, and no product that
  competes with Lightricks without a commercial license. Export-control and
  sanctions terms also apply.
- **Gemma Terms of Use** (the text encoder, a repack of
  `google/gemma-3-12b-it`; [terms](https://ai.google.dev/gemma/terms)),
  including Google's Prohibited Use Policy.
- **The abliterated Gemma LoRA has no stated license.** It removes the text
  encoder's refusal behaviour, and the runner never uses it because prompt
  enhancement stays off. Leave it out unless you have a reason and have
  checked its terms yourself.

The image uses Python 3.12, PyTorch 2.13 and CUDA 13.0. The GPU host must
support CUDA 13.0. Rebuild after updating these locks and verify each required
profile on the target GPU before deployment; dependency resolution and static
scans do not prove rendering compatibility.
