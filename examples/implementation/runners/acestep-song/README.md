# acestep-song runner

Songs with [ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5) at a pinned
commit, through ACE-Step's own REST API server running on loopback inside the
container. The XL Turbo DiT renders every song; the `quality-60` profile adds
the 5Hz LM 4B planner.

| Task | Catalog id | Workflow |
| --- | --- | --- |
| `text-to-song` | `song-create-acestep-xl-sft` | `.github/workflows/acestep-song-generation.yml` |

The catalog id keeps its historical name: neither profile uses the XL SFT
checkpoint, so the model folder does not need it.

## Profiles

The claimed `generation_profile` picks one; it is also the models.json profile.

| Profile | Length | What runs |
| --- | --- | --- |
| `draft-120` (default) | 10 to 120 s, quicker | `acestep-v15-xl-turbo`, 8 steps, shift 3, guidance 1, no planner |
| `quality-60` | 10 to 60 s, slower and cleaner | the same DiT plus `acestep-5Hz-lm-4B` on vLLM with thinking on; blank lyrics let the planner write the song from the description, and `[Verse]`-style section tags turn on its format mode |

## What it does with a request

- `prompt` (up to 4,000 characters) and `lyrics` (up to 30,000) are never
  written to logs, errors or `result.json`. `instrumental: true` renders with
  ACE-Step's `[Instrumental]` marker.
- `duration_seconds` defaults to the profile's cap; `bpm` is 30 to 300;
  `key_scale` is a note and mode such as `F# minor`; `time_signature` is blank
  (the model decides), `2`, `3`, `4` or `6`; `vocal_language` is an ACE-Step
  language code or `unknown`; `seed` is 0 to 2^31-1.
- Every render passes an objective check before it is published: 48 kHz 16-bit
  PCM, the requested length within 3%, not silent, not hard-clipped and not
  noise-like. A request without a seed gets one retry with a new seed; an
  explicit seed is never changed.
- Output: `song.mp3` (320 kbps) and `song.wav`.

## Hardware

An NVIDIA GPU with 24 GB of VRAM (the 4B DiT and, for `quality-60`, the 4B
planner stay on the GPU, with no CPU offload), a driver that supports CUDA
13.0, the NVIDIA Container Toolkit, and about 16 GB of free RAM.

## Build the image

From the kit root (the build needs `runners/common/`):

```bash
docker build -f runners/acestep-song/Dockerfile -t registry.example.com/ii-os/acestep-song:2026-11 .
docker push registry.example.com/ii-os/acestep-song:2026-11
```

Set the repository variable `II_OS_RUNNER_IMAGE_ACESTEP_SONG` to the pushed
image pinned by digest, for example
`registry.example.com/ii-os/acestep-song@sha256:<digest>`. Rebuild and update
the variable whenever anything under `runners/acestep-song/` or
`runners/common/` changes.

The base image is pinned by digest and upstream source by commit
`ca1e85fe9430179831e6bc6be790c332190a3866`. The reviewed
`patches/headless-security.patch` updates dependency metadata and excludes the
unused Gradio UI, including an import-time UI directory creation that is not
used by the API. The image uses Ubuntu 24.04, Python 3.12, PyTorch 2.13,
CUDA 13, Transformers 5, and Diffusers 0.38.

### Python dependencies

The patch replaces diskcache with the runner's JSON-only SQLite cache, preserving expiry and cross-process persistence without deserializing Python objects. Python 3.12 selects nano-vllm's PyTorch SDPA attention path instead of its Python 3.11-only FlashAttention wheel. Validate performance on your target GPU. ACE-Step remains editable so checkpoint model code and private temporary caches retain their existing layout.

`patches/pytorch-wavelets-resources.patch` replaces the wavelet package's
removed `pkg_resources` API with Python's `importlib.resources`. The image
build verifies that its bundled coefficient data still loads.

Every dependency and build tool is installed from `requirements.lock.txt`
and `requirements-build.lock.txt` with `--require-hashes --no-deps`.
The upstream package is then installed from patched pinned source with
`--no-deps --no-build-isolation`; `pip check` verifies package compatibility.
The release dependency scanner reads both locks.

After changing a requirement or revision, delete both locks and regenerate
from the kit root using the commands in `requirements.in`. Keep
`--exclude-newer` at least a week behind the regeneration date. Review the
patch against the new source, rebuild, and validate generation before use.

## How it runs inside the container

ACE-Step writes into its `checkpoints/` folder (it copies its model code next
to the weights) and under `.cache/`, while `/models` is read-only and the
container has no network. The image makes both paths symlinks into the
container's private `/tmp`. Before each run the runner links every folder of
`/models` into that checkpoints folder; for the DiT it links the weights file
by file and copies the model code from the pinned ACE-Step source. It then
starts `acestep.api_server` on 127.0.0.1 with a per-run API key in its
environment and every download path disabled, renders through the API, and
stops the server. The server log stays in `/tmp` because it can echo the
request's text; on failure only error lines are printed, with that text
redacted.

## Model folder

The container reads models only from `${II_OS_MODEL_ROOT}/acestep-song/`,
mounted read-only at `/models`. It never downloads anything. The layout is the
one ACE-Step's own downloader produces:

```text
${II_OS_MODEL_ROOT}/acestep-song/
  acestep-v15-xl-turbo/    ACE-Step/acestep-v15-xl-turbo @ d4a0b288
  vae/                     ACE-Step/Ace-Step1.5 @ 19671f40 (main repository)
  Qwen3-Embedding-0.6B/    ACE-Step/Ace-Step1.5 @ 19671f40
  acestep-v15-turbo/       ACE-Step/Ace-Step1.5 @ 19671f40
  acestep-5Hz-lm-1.7B/     ACE-Step/Ace-Step1.5 @ 19671f40
  acestep-5Hz-lm-4B/       ACE-Step/acestep-5Hz-lm-4B @ 0a3ec94b  (quality-60 only)
```

ACE-Step 1.5 will not start unless every component of its main repository is
present, so `acestep-v15-turbo` and `acestep-5Hz-lm-1.7B` (8.5 GB) are listed
although neither profile renders with them. The `.py` files the Hugging Face
repositories ship are not needed: the runner uses the code of the pinned
ACE-Step commit. List every file with its size, license and pinned source URL,
then verify the folder after you fetch it:

```bash
python3 scripts/ii_os_model_folder.py list --manifest runners/acestep-song/models.json
python3 scripts/ii_os_model_folder.py verify --manifest runners/acestep-song/models.json \
  --model-root "$II_OS_MODEL_ROOT" --profile quality-60
```

| Profile | Files | Size |
| --- | --- | --- |
| `draft-120` | XL Turbo DiT, VAE, Qwen3 embedding text encoder, main-repository turbo DiT and 1.7B LM | 30.0 GB |
| `quality-60` | `draft-120` plus the 5Hz LM 4B planner | 38.5 GB |

## Licenses

ACE-Step 1.5's code and every model repository listed here are MIT-licensed.
`Qwen3-Embedding-0.6B` is redistributed in the ACE-Step repository; Qwen
publishes the original under Apache-2.0.
