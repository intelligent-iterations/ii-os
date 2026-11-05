# minimax-h3 runner

Audiovisual generation with [MiniMax H3](https://huggingface.co/MiniMaxAI/MiniMax-H3)
through a headless [ComfyUI](https://github.com/comfyanonymous/ComfyUI) at a
pinned commit. One request becomes a 4 to 15 second MP4 at 1280x720 or
720x1280, 24 fps, with the model's own stereo soundtrack, published with its
opening frame as a poster.

| Task | Catalog id | Workflow |
| --- | --- | --- |
| `text-to-video` | `text-to-video-minimax-h3` | `.github/workflows/minimax-h3-text-to-video.yml` |

## Read the license first

MiniMax H3 is open weights under the
[MiniMax H3 Community License Agreement](https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/LICENSE),
not an open-source license. In plain terms:

- **It is not licensed in the European Union, the United Kingdom, the
  Republic of Korea or the United States.** The license is granted only
  outside those "Excluded Territories", and it forbids using, reproducing,
  distributing or displaying the model or its outputs inside them. If you, your
  runner hosts or the people you let generate are there, do not deploy this
  runner unless MiniMax has given you a separate license.
- Commercial products or services with more than **US$20 million** in yearly
  revenue need MiniMax's prior written authorization, and a commercial product
  must show "MiniMax H3" in its interface (the dashboard names the model).
- If you let other people generate with it, you must bind them to the
  license's use restrictions (Section V and the Exhibit A Acceptable Use
  Policy), keep safeguards against misuse, offer a way to report violations,
  and act on reports.
- Outputs may not be used to improve any other AI model.

The Turbo adapter states Apache-2.0, but it is a derivative of MiniMax H3, so
the MiniMax terms apply to using it too. H3's text encoder is built on
Qwen3-VL (Apache-2.0) and ships as part of MiniMax H3. Every file's terms are
repeated in [`models.json`](models.json).

The image also contains ComfyUI (GPL-3.0), SageAttention (Apache-2.0, compiled
from source) and the two vendored nodes in
[`comfy_nodes/ii_os_minimax_h3`](comfy_nodes/ii_os_minimax_h3); its CAB
sampler is adapted from an MIT-licensed project, whose notice is in
`LICENSE-cab-sampler`.

## Request

| Input | Accepted values |
| --- | --- |
| `prompt` | the scene, up to 7,000 characters, used verbatim |
| `duration_seconds` | whole seconds from 4 to 15 (default 15); for a continuation, the length of the finished video |
| `orientation` | `landscape` (1280x720) or `portrait` (720x1280) |
| `fps` | `24`, the model's only rate |
| `performance_mode` | `quality` (default) or `turbo` |
| `generation_mode` | one of the modes below (default `text_to_video`) |
| `reference_manifest` | the staged references: asset id, kind, role and ordinal of each, never URLs |
| `edit_operation`, `identity_replacement_consent` | `video_edit` only, and equal to the manifest's values |
| `extension_method` | optional; `single_pass` is the only method this runner implements |

| Mode | References | Transformer |
| --- | --- | --- |
| `text_to_video` | none | FL2VA |
| `first_frame_to_video` | one `first_frame` image | FL2VA |
| `last_frame_to_video` | one `last_frame` image | FL2VA |
| `first_last_frame_to_video` | one `first_frame` and one `last_frame` image | FL2VA |
| `reference_to_video` | at least one image, video or audio reference | Ref2VA |
| `video_edit` | exactly one `source_video`, plus optional references | Ref2VA |
| `video_continue` | exactly one `source_video`, plus optional references | Ref2VA |

At most 9 images, 3 videos, 3 audio clips and 12 references in all. Image
roles are `first_frame`, `last_frame`, `subject`, `style`, `environment`,
`pose_reference` and `effect_reference`; video roles `source_video`,
`motion_reference`, `video_subject`, `video_style`, `video_environment`,
`video_action` and `video_effect`; audio roles `audio_reference` and
`audio_reuse`. Character replacement needs a subject reference and confirmed
permission to use the identity.

Turbo serves the four FL2VA modes only. The runner refuses anything else, and
checks that the claim staged exactly the manifest's references in order,
before any image is pulled or model loaded. Inside the container, before
ComfyUI starts, it measures every video and audio reference with ffprobe:
each must be 2 to 15 seconds, each kind may total 15 seconds, and a
continuation must add at least 2 seconds. A reference outside those limits
fails the run with `minimax_h3_reference_rejected`; anything else that fails is
reported as `minimax_h3_workflow_failed` (or `minimax_h3_workflow_cancelled`).

Each run picks a random seed and reports it, with the mode, profile and each
reference's measured length, in `out/result.json` metadata. The prompt is never
logged or written into the outputs.

## What the runner does

**Prompt structure.** H3 reads endpoint-mode prompts from an
`integrated_multimodal_description:` field, so the runner adds that label when
the prompt does not have it. Reference modes get one line per reference under
`subject_definitions:` naming its tag (`<Picture 1>`, `<Video 1>`,
`<Audio 1>`, numbered per kind) and role. The person's own text follows
unchanged.

**Profiles.**

| `performance_mode` | Profile | Steps | Sampler | Notes |
| --- | --- | --- | --- | --- |
| `quality` | `native-sage-cab10` | 10 | CAB-2 (theta 0.2) | the default |
| `turbo` | `turbo-lightx2v-4step-768p` | 4 | Euler | LightX2V four-step LoRA at strength 1.0, video/audio sigma shifts 6/3 |

Both use SageAttention and render a 1280x736 (or 736x1280) canvas, which the
delivery encode scales and centre-crops to 720p.

**Memory.** The graph wraps the transformer in the vendored exact low-memory
patch, which runs the feed-forward, the fused QKV projection and the attention
heads in bounded chunks: the same arithmetic with shorter tensor lifetimes.
ComfyUI streams weights from the model folder (dynamic VRAM, `--fast-disk`,
smart memory off) and reserves VRAM for the sampler in proportion to frames x
pixels, plus CAB's history in Quality. On sm86 GPUs the patch also routes
SageAttention to its CUDA kernel, because its Triton kernel faults on
anchored continuation sequences.

**Continuations.** H3 cannot continue a clip from prose. The runner allocates
the latent for the finished length and anchors the source video, with its
soundtrack, at frame 0 through `MiniMaxH3AddGuide`, so the model renders the
rest in one pass with one decode and no seam.

**Delivery.** ffmpeg scales and crops the raw render to the delivery canvas,
re-encodes H.264 (yuv420p, CRF 15, faststart) with 48 kHz AAC stereo, trims or
pads to exactly the requested length and drops the render's container
metadata. The result must be exactly that, or the run fails. ComfyUI runs with
`--disable-metadata`, and its error reports have the prompt removed before
they reach the job log.

**Start-up checks.** Right after ComfyUI starts, the runner confirms from its
log that SageAttention is active and that the comfy-kitchen CUDA backend is
enabled, so a mismatched image fails in seconds rather than after a long
render. Set the job variable `II_OS_OPTION_REQUIRE_COMFY_KITCHEN_CUDA=false`
to run without comfy-kitchen's CUDA kernels (slower, and not the measured
profile).

## Hardware

An NVIDIA GPU with 24 GB of VRAM whose compute capability the image was built
for (see `SAGEATTENTION_CUDA_ARCH_LIST` below), a driver that supports CUDA
13.0 (R580 or newer), and the NVIDIA Container Toolkit. Plan for 32 GB of
system RAM or more and keep the model folder on a fast local NVMe disk:
ComfyUI streams the 42 GB of weights from it instead of holding them in memory.

A 15-second render took about 33 minutes in Quality and 15 in Turbo on a
24 GB GPU; continuations take several times longer, since anchoring makes each
step more expensive. The generate job allows 360 minutes and ComfyUI 300 of
them. Replace the catalog's `runtime_estimates` with numbers from your own
runner.

## Build the image

From the kit root (the build needs `runners/common/`):

```bash
docker build -f runners/minimax-h3/Dockerfile \
  --build-arg SAGEATTENTION_CUDA_ARCH_LIST="8.6" \
  -t registry.example.com/ii-os/minimax-h3:2026-11 .
docker push registry.example.com/ii-os/minimax-h3:2026-11
```

Set the repository variable `II_OS_RUNNER_IMAGE_MINIMAX_H3` to the pushed
image pinned by digest, for example
`registry.example.com/ii-os/minimax-h3@sha256:<digest>`. Rebuild and update the
variable whenever anything under `runners/minimax-h3/` or `runners/common/`
changes, because the workflow plans with the checked-out code and runs with the
image.

- The base image is pinned by digest, ComfyUI and SageAttention by commit.
- Every Python package, dependencies included, is pinned by version and
  sha256 and installed from wheels with `--require-hashes --no-deps`: the
  installer (pip, setuptools, wheel) from
  [`requirements-build.lock.txt`](requirements-build.lock.txt) first, then
  [`requirements.lock.txt`](requirements.lock.txt). The locks are generated
  from [`requirements.in`](requirements.in), which carries ComfyUI's own
  requirements at the pinned commit; the build fails if a ComfyUI bump needs a
  package the lock lacks. Delete both locks and regenerate them with the
  commands at the top of `requirements.in`, keeping `--exclude-newer` at least
  a week back.
- PyTorch 2.13.0 on PyPI is the CUDA 13.0 build. The pip CUDA 13.0 toolkit in
  the lock provides `nvcc` for compiling SageAttention at build time; no GPU is
  needed to build. The profile's timings were measured on torch 2.11.0; the
  lock moves to 2.13.0 because 2.11.0 carries a published advisory, and the
  lock names end in `.txt` so dependency scanners read them. Render each profile
  once after building to confirm your image.
- `SAGEATTENTION_CUDA_ARCH_LIST` picks the GPU architectures SageAttention's
  kernels are compiled for. `8.6` (for example the GeForce RTX 30 series) is
  the verified configuration; add your GPU's, such as `8.6;8.9` for an RTX
  40-series card. On a GPU the build does not cover, the run fails at the
  first sampling step.

## Model folder

The container reads models only from `${II_OS_MODEL_ROOT}/minimax-h3/`,
mounted read-only at `/models`. It never downloads anything and has no
network. Lay the folder out exactly as the `path` values in
[`models.json`](models.json):

```text
${II_OS_MODEL_ROOT}/minimax-h3/
  diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors
  diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors
  text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
  vae/minimax_h3_video_vae_fp16.safetensors
  vae/minimax_h3_audio_vae_fp32.safetensors
  loras/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors
```

List every file with its size, license and pinned source URL:

```bash
python3 scripts/ii_os_model_folder.py list --manifest runners/minimax-h3/models.json
```

Fetch them yourself, once, onto the GPU host (each `source` is pinned to an
upstream commit), then verify each profile you serve end to end:

```bash
for profile in fl2va fl2va-turbo ref2va; do
  python3 scripts/ii_os_model_folder.py verify --manifest runners/minimax-h3/models.json \
    --model-root "$II_OS_MODEL_ROOT" --profile "$profile"
done
```

`verify` hashes every file; the workflow's per-run `check` only confirms
presence and size for the profile the request needs. Symlinks are fine as long
as they resolve inside the runner folder.

| Profile | Serves | Files | Approximate size |
| --- | --- | --- | --- |
| `fl2va` | Quality, endpoint modes | FL2VA transformer, text encoder, video and audio VAEs | 42.5 GB |
| `fl2va-turbo` | Turbo, endpoint modes | `fl2va` plus the Turbo LoRA | 44.4 GB |
| `ref2va` | reference, edit and continuation modes | Ref2VA transformer, text encoder, video and audio VAEs | 42.5 GB |
| all | every mode | all six files | 65.4 GB |

## Not included

- Only the `single_pass` continuation method exists; a request for any other
  `extension_method` is refused rather than rendered some other way.
- The two served profiles are the only ones; other step counts, samplers or
  resolutions would need their own measurement.
- The runner does not manage GPU power limits, temperatures or host memory.
  Set those on your runner host if your hardware needs it.
