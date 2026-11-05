# chatterbox-narration runner

Text-to-speech with [Chatterbox Turbo](https://huggingface.co/ResembleAI/chatterbox-turbo)
through the `chatterbox-tts` package at a pinned version. It narrates the
request's text in the model's built-in voice, or in the voice of one audio
reference the requester has confirmed they have permission to use.

| Task | Catalog id | Workflow |
| --- | --- | --- |
| `text-to-speech` | `narration-create-chatterbox-tts` | `.github/workflows/narration-generation.yml` |

## What it does with a request

- `text` (1 to 6,000 characters) is spoken; it is never written to logs,
  errors or `result.json`.
- `voice_model` must be `chatterbox-turbo` (the default) and names the model
  profile. `language` is a label of up to 32 characters (default `English`).
  Chatterbox Turbo speaks English.
- `seed` makes a take repeatable; without one the runner picks a seed and
  records it in `result.json` metadata.
- `voice_reference_asset_id` and `voice_clone_consent`: ii-os stages the
  referenced audio at `in/sources/00.<ext>`. The runner refuses the request
  unless `voice_clone_consent` is `true`, the staged audio is the named asset,
  and it is 50 MB or smaller. It converts the reference to its first 30
  seconds of 24 kHz mono and refuses it if that is 5 seconds or shorter.
- Output: `narration.mp3` (LAME VBR quality 2) and `narration.wav` (16-bit PCM,
  24 kHz). Chatterbox embeds Resemble AI's Perth imperceptible watermark in
  everything it generates.

## Hardware

An NVIDIA GPU with a driver that supports CUDA 12.4 or newer, and the NVIDIA
Container Toolkit. Chatterbox Turbo is a 350M-parameter model and fits on
small GPUs; the catalog runtime estimate was measured on a 24 GB card.

## Build the image

From the kit root (the build needs `runners/common/`):

```bash
docker build -f runners/chatterbox-narration/Dockerfile -t registry.example.com/ii-os/chatterbox-narration:2026-11 .
docker push registry.example.com/ii-os/chatterbox-narration:2026-11
```

Set the repository variable `II_OS_RUNNER_IMAGE_CHATTERBOX_NARRATION` to the
pushed image pinned by digest, for example
`registry.example.com/ii-os/chatterbox-narration@sha256:<digest>`. Rebuild and
update the variable whenever anything under `runners/chatterbox-narration/` or
`runners/common/` changes.

The base image is pinned by digest and upstream source by commit
`ab55923c27757c90cfcc407baa57dc25a7d25217`. The reviewed
`patches/headless-security.patch` updates dependency metadata and excludes the
unused Gradio UI. The image uses Ubuntu 24.04, Python 3.12, PyTorch 2.13,
CUDA 13, Transformers 5, and Diffusers 0.38.

### Python dependencies

The headless patch pins Perth and updates dependency metadata; the narration
model code is unchanged. `patches/perth-resources.patch` replaces Perth's
removed `pkg_resources` API with `importlib.resources`, preserving its bundled
watermark model. The image build initializes the watermarker to verify this.

Every dependency and build tool is installed from `requirements.lock.txt`
and `requirements-build.lock.txt` with `--require-hashes --no-deps`.
The upstream package is then installed from patched pinned source with
`--no-deps --no-build-isolation`; `pip check` verifies package compatibility.
The release dependency scanner reads both locks.

After changing a requirement or revision, delete both locks and regenerate
from the kit root using the commands in `requirements.in`. Keep
`--exclude-newer` at least a week behind the regeneration date. Review the
patch against the new source, rebuild, and validate generation before use.

## Model folder

The container reads models only from `${II_OS_MODEL_ROOT}/chatterbox-narration/`,
mounted read-only at `/models`. It never downloads anything and has no network.
Put the files of `ResembleAI/chatterbox-turbo` at revision
`749d1c1a46eb10492095d68fbcf55691ccf137cd` in a `chatterbox-turbo/` folder:

```text
${II_OS_MODEL_ROOT}/chatterbox-narration/
  chatterbox-turbo/ve.safetensors
  chatterbox-turbo/t3_turbo_v1.safetensors
  chatterbox-turbo/s3gen_meanflow.safetensors
  chatterbox-turbo/conds.pt
  chatterbox-turbo/added_tokens.json, merges.txt, special_tokens_map.json,
                   tokenizer_config.json, vocab.json
```

Those are the files `ChatterboxTurboTTS.from_local` reads. The repository's
`s3gen.safetensors` (the non-distilled decoder) and `t3_turbo_v1.yaml` are not
needed. List every file with its size, license and pinned source URL, then
verify the folder after you fetch it:

```bash
python3 scripts/ii_os_model_folder.py list --manifest runners/chatterbox-narration/models.json
python3 scripts/ii_os_model_folder.py verify --manifest runners/chatterbox-narration/models.json \
  --model-root "$II_OS_MODEL_ROOT" --profile chatterbox-turbo
```

| Profile | Files | Size |
| --- | --- | --- |
| `chatterbox-turbo` | voice encoder, T3 Turbo, distilled S3Gen decoder, built-in voice, GPT-2 tokenizer | 3.0 GB |

## Licenses

The model weights and the `chatterbox-tts` package are MIT-licensed. Voice
cloning is gated on the requester's consent flag; whoever operates the
workflow remains responsible for how reference voices are obtained and used.
