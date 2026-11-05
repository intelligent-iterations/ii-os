# seedvr2-video runner

Video upscaling with [SeedVR2](https://huggingface.co/ByteDance-Seed/SeedVR2-3B)
3B through a headless [ComfyUI](https://github.com/comfyanonymous/ComfyUI) and the
[ComfyUI-SeedVR2_VideoUpscaler](https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler)
custom node, both at pinned commits. FFmpeg, inside the same container, probes
the source, puts its audio back and cuts the poster.

| Task | Catalog id | Workflow |
| --- | --- | --- |
| `video-upscale` | `seedvr2-video-upscale` | `.github/workflows/seedvr2-video-upscale.yml` |

## What a run does

The host stages one source video at `/work/in/sources/00.mp4` (or `.webm`).
The container then:

1. probes it and refuses, with the error code
   `video_upscale_source_unsupported`, a source that is unreadable, longer
   than 30 seconds, over 1,800 frames, above 60 FPS, over 4,096 pixels on its
   long edge, or wider than 16:9 (it could not reach a 1080-pixel short edge
   inside the 1,920-pixel long-edge cap). The host already refused anything
   that is not MP4 or WebM, or is larger than 512 MiB;
2. hashes each weight it is about to load against `models.json` before the
   first use, and records it in the node's validation cache so the node never
   re-hashes or tries to download;
3. runs [`seedvr2-video-upscale.api.json`](seedvr2-video-upscale.api.json) at
   a 1080-pixel short edge. If the GPU runs out of memory it restarts ComfyUI
   with the next preset, in this order, and never lowers the resolution:

   | Preset | Change | Quality |
   | --- | --- | --- |
   | `quality` | FP16 DiT and VAE, no tiling | reference |
   | `vae_tiled` | VAE encode/decode tiles of 1024 with 128 overlap | same |
   | `cpu_blockswap` | tiling, CPU offload, 16 swapped blocks | same, slower |
   | `fp8_memory_saver` | as above with FP8 DiT weights | lower; only if the optional FP8 file is present |

4. remuxes the source's first audio stream when `preserve_audio` is true
   (stream copy, or AAC when the codec cannot live in MP4), checks the result
   kept every frame, the frame rate and the aspect ratio, and writes
   `video.mp4` plus the opening frame as `poster.png`. A poster that cannot
   be cut is skipped, never fatal.

`out/result.json` metadata records the preset used, `quality_changed`, the
audio handling and the source and output probes.

## Hardware

An NVIDIA GPU with 24 GB of VRAM, a driver that supports CUDA 13.0 and the
NVIDIA Container Toolkit. Plan for at least 16 GB of free RAM; decoded frames
are held in memory, so long, high-frame-rate clips need more, as does the
`cpu_blockswap` preset. The container's `/tmp` is a RAM-backed scratch area
holding a copy of the source and the upscaled video until it is remuxed.
Baseline: about 135 seconds for a 3-second, 36-frame clip on a 24 GB GPU.

## Build the image

From the kit root (the build needs `runners/common/`):

```bash
docker build -f runners/seedvr2-video/Dockerfile -t registry.example.com/ii-os/seedvr2-video:2026-11 .
docker push registry.example.com/ii-os/seedvr2-video:2026-11
```

Set the repository variable `II_OS_RUNNER_IMAGE_SEEDVR2_VIDEO` to the pushed
image pinned by digest, for example
`registry.example.com/ii-os/seedvr2-video@sha256:<digest>`. Rebuild and update
the variable whenever anything under `runners/seedvr2-video/` or
`runners/common/` changes, because the workflow plans with the checked-out
code and runs with the image.

The base image is pinned by digest, ComfyUI and the custom node by commit
(each checked with `git rev-parse`), and every Python package by version and
sha256 (see [Python dependencies](#python-dependencies)). The node gets one
small patch,
[`seedvr2-transformers-5-flash-attn.patch`](seedvr2-transformers-5-flash-attn.patch),
which the build verifies by sha256: unpatched, the node plants a stub
`flash_attn` module when flash-attn is not installed, and newer
transformers/diffusers then try to use it.

### Python dependencies

The Dockerfile installs every Python package with
`pip install --require-hashes --no-deps` from two files in this folder, each
pinning an exact version and sha256 per package:

- `requirements.lock.txt`: everything the runner imports, compiled from `requirements.in` (PyTorch, ComfyUI's `requirements.txt` at `COMFYUI_REVISION`, and the node's dependencies with transformers and huggingface-hub, pinned to a set known to work together) for CPython 3.12 (Ubuntu 24.04's Python) on x86-64 Linux, from PyPI.
- `requirements-build.lock.txt`: pip, setuptools and wheel, installed first. `antlr4-python3-runtime` (needed by omegaconf) is published only as source; it builds with this setuptools, never with one fetched for the build.

The release dependency scan (osv-scanner) reads both files, so it checks what
the image installs. After changing a pin in `requirements.in` or a revision in
the Dockerfile, delete both files and recompile them from the kit root with
[uv](https://docs.astral.sh/uv/), using the commands at the top of
`requirements.in` (runtime lock first: it constrains the build lock), then
rebuild the image. Keep `--exclude-newer` at least a week back, so no release
younger than that enters a lock.

## Model folder

The container reads models only from `${II_OS_MODEL_ROOT}/seedvr2-video/`,
mounted read-only at `/models`. It never downloads anything and has no network.
The folder name `SEEDVR2` is the one the custom node looks for:

```text
${II_OS_MODEL_ROOT}/seedvr2-video/
  SEEDVR2/seedvr2_ema_3b_fp16.safetensors        6.8 GB
  SEEDVR2/ema_vae_fp16.safetensors               0.5 GB
  SEEDVR2/seedvr2_ema_3b_fp8_e4m3fn.safetensors  3.4 GB, optional
```

List every file with its size, license and pinned source URL:

```bash
python3 scripts/ii_os_model_folder.py list --manifest runners/seedvr2-video/models.json
```

Fetch them yourself, once, onto the GPU host (each `source` is pinned to an
upstream commit), then verify the profile end to end:

```bash
python3 scripts/ii_os_model_folder.py verify --manifest runners/seedvr2-video/models.json \
  --model-root "$II_OS_MODEL_ROOT" --profile seedvr2-3b
```

The workflow's per-run `check` confirms presence and size; the runner itself
hashes each file it loads before the first use. Symlinks are fine as long as
they resolve inside the runner folder, because nothing outside it is mounted.

| Profile | Files | Approximate size |
| --- | --- | --- |
| `seedvr2-3b` | SeedVR2 3B FP16, FP16 VAE, optional FP8 fallback | 7.3 GB required, 10.7 GB with the fallback |

## Licenses

The weights come from `numz/SeedVR2_comfyUI`, a repack of ByteDance-Seed's
SeedVR2 released under Apache-2.0. The custom node is Apache-2.0. Check each
license against your use before you download.

The image uses Python 3.12, PyTorch 2.13 and CUDA 13.0. The GPU host must
support CUDA 13.0. Rebuild after updating these locks and verify each required
profile on the target GPU before deployment; dependency resolution and static
scans do not prove rendering compatibility.
