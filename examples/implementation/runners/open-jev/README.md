# open-jev runner

Typed text classification with the open-weights
[`autotrust/JEV-9B`](https://huggingface.co/autotrust/JEV-9B) decision model.
The dashboard sends one text (the *state*) and up to eight typed questions; the
model answers each question with a calibrated probability distribution in one
prefill pass. It never generates text.

| Task | Catalog id | Workflow |
| --- | --- | --- |
| `classify` | `classification-open-jev-9b` | `.github/workflows/open-jev-classification.yml` |

## The engine is vendored

`open_jev/` is the decision engine of the open-jev package 0.1.0, vendored
under the Apache License 2.0 (full text in [`LICENSE`](LICENSE)). Only what a
one-shot decision needs is included: the System One request contract
(`contract.py`), answer shapes (`answers.py`), the service (`service.py`) and
the PyTorch engine (`engine.py`). Each file starts with a notice saying whether
it was changed. The package's HTTP server, command line and weight downloader
are not included; the kit's `models.json` and `scripts/ii_os_model_folder.py`
take the downloader's place.

The System One framing and the `noul`, `choice` and `score` primitives
originate with TypeSafe AI's Jev. The model is an independent distillation and
is not affiliated with TypeSafe AI.

## Request and result

Inputs, delivered through the ii-os claim:

- `state`: the text to classify, 1 to 8,000 characters.
- `questions`: a JSON-encoded TypeSafe System One `questions` object with 1 to
  8 entries, for example:

  ```json
  {
    "billing": {"type": "noul", "instructions": "Is this message about billing?"},
    "tone": {"type": "choice", "instructions": "What is the tone?",
             "criteria": {"angry": "An upset message", "calm": null}},
    "urgency": {"type": "score", "instructions": "How urgent is this message?",
                "criteria": ["None", "Very low", "Low", "Moderate", "High", "Very high"]}
  }
  ```

The runner writes one `application/json` artifact, `decisions.json`:

```json
{
  "schema_version": 1,
  "response": {"model": "autotrust/JEV-9B", "answers": {"...": "..."},
               "usage": {"input_tokens": 120, "output_tokens": 0}},
  "run": {"model": "autotrust/JEV-9B", "model_revision": "7ac669b8...",
          "template_version": "bare-v1", "render_version": "render-v1",
          "questions": 3, "state_tokens": 18, "state_truncated": false,
          "decide_seconds": 0.4, "load_seconds": 40.0, "device": "...",
          "peak_vram_mib": 16100, "torch": "...", "cuda": "...", "package_version": "0.1.0"}
}
```

`response` is the TypeSafe System One response body. Each answer has the
TypeSafe shape:

- `noul`: `noul`, the probability of yes.
- `choice`: `choice`, `confidence`, and `probabilities` for every option.
- `score`: `score` (the expected level), `confidence`, `legend`, and
  `probabilities` for levels `0` to `5`.

Confidence is `(k * p_max - 1) / (k - 1)` over `k` options. `output_tokens` is
always 0, because nothing is decoded.

### What the model cannot answer

The model was trained on a fixed set of question shapes and refuses others
instead of approximating them:

| | Accepted |
| --- | --- |
| `choice` options | 1 to 16 |
| `score` levels | exactly 6 (a 0 to 5 scale) |
| `box` questions, images | refused (text only) |
| Long state | truncated to 1,024 tokens (60 % head, 40 % tail); `run.state_truncated` says so |

Such a request is refused inside the container before the model loads, and
the run fails with `classification_request_rejected`, which the dashboard
turns into "check the question types and choices". The log names the field and
the kind of problem, never the text or the question names.

| Error code | When |
| --- | --- |
| `classification_request_rejected` | The questions are malformed or ask for a shape the model cannot answer. |
| `classification_model_missing` | The model folder check found a file of the profile missing or the wrong size. |
| `classification_workflow_failed` | Anything else stopped the run (GPU failure, upload). |
| `classification_workflow_cancelled` | The run was cancelled. |

## Hardware

An NVIDIA GPU with at least 20 GiB of free memory (a 24 GB card), a driver
that supports CUDA 13.0 (R580 or newer), the NVIDIA Container Toolkit, about
8 GB of free RAM, and disk for the 16.85 GiB model folder plus the image. The
model loads in bf16 at about 16 GiB; its vocabulary head is released after
loading because decisions never use it.

## Build the image

From the kit root (the build needs `runners/common/`):

```bash
docker build -f runners/open-jev/Dockerfile -t registry.example.com/ii-os/open-jev:2026-11 .
docker push registry.example.com/ii-os/open-jev:2026-11
```

Set the repository variable `II_OS_RUNNER_IMAGE_OPEN_JEV` to the pushed image
pinned by digest, for example
`registry.example.com/ii-os/open-jev@sha256:<digest>`. Rebuild and update the
variable whenever anything under `runners/open-jev/` or `runners/common/`
changes, because the workflow plans with the checked-out code and runs with
the image.

The base image is pinned by digest, and every Python package (PyTorch 2.13.0
for CUDA 13.0, transformers 5.16.1, peft 0.21.0, flash-linear-attention 0.5.2
and their dependencies) is pinned to an exact version and sha256 and installed
without dependency resolution.

### Python dependencies

The Dockerfile installs every Python package with
`pip install --require-hashes --no-deps` from two files in this folder, each
pinning an exact version and sha256 per package:

- `requirements.lock.txt`: exactly the set the engine was validated with, listed in `requirements.in` and compiled with `--no-deps` for CPython 3.12 (Ubuntu 24.04's Python) on x86-64 Linux, from PyPI. `pip check` in the build proves the set is complete.
- `requirements-build.lock.txt`: pip 26.2.2, installed first.

The release dependency scan (osv-scanner) reads both files, so it checks what
the image installs. After changing a pin in `requirements.in` or a revision in
the Dockerfile, delete both files and recompile them from the kit root with
[uv](https://docs.astral.sh/uv/), using the commands at the top of
`requirements.in` (runtime lock first: it constrains the build lock), then
rebuild the image. Keep `--exclude-newer` at least a week back, so no release
younger than that enters a lock.

## Model folder

The container reads the model only from `${II_OS_MODEL_ROOT}/open-jev/`,
mounted read-only at `/models`, and loads it with Hugging Face offline mode on.
Keep the upstream snapshot layout under `jev-9b/`, exactly as the `path`
values in [`models.json`](models.json):

```text
${II_OS_MODEL_ROOT}/open-jev/jev-9b/
  config.json
  model.safetensors.index.json
  model-00001-of-00005.safetensors ... model-00005-of-00005.safetensors
  adapter/adapter_config.json
  adapter/adapter_model.safetensors
  head.safetensors
  judge_config.json
  calibration.json
  tokenizer.json
  tokenizer_config.json
```

Every file comes from the `autotrust/JEV-9B` repository at commit
`7ac669b8fb476ba926491e3d1c39f9330d68dbed`. Fetch them yourself, once, on the
GPU host, for example with the Hugging Face CLI:

```bash
hf download autotrust/JEV-9B --revision 7ac669b8fb476ba926491e3d1c39f9330d68dbed \
  --local-dir "$II_OS_MODEL_ROOT/open-jev/jev-9b" \
  config.json model.safetensors.index.json \
  model-00001-of-00005.safetensors model-00002-of-00005.safetensors model-00003-of-00005.safetensors \
  model-00004-of-00005.safetensors model-00005-of-00005.safetensors \
  adapter/adapter_config.json adapter/adapter_model.safetensors \
  head.safetensors judge_config.json calibration.json tokenizer.json tokenizer_config.json
```

The repository also holds evaluation reports, videos, vLLM adapters and
vision files; the runner reads none of them. Then verify the folder end to
end (this hashes every file):

```bash
python3 scripts/ii_os_model_folder.py verify --manifest runners/open-jev/models.json \
  --model-root "$II_OS_MODEL_ROOT" --profile jev-9b
```

The workflow's per-run `check` only confirms presence and size.

| Profile | Files | Size |
| --- | --- | --- |
| `jev-9b` | Backbone (5 shards), System One LoRA adapter, decision head, calibration, tokenizer | 16.85 GiB |

## Licenses

- Engine code in `open_jev/`: Apache-2.0, see [`LICENSE`](LICENSE).
- Model weights: `autotrust/JEV-9B`, Apache-2.0, built on `Qwen/Qwen3.5-9B`
  (Apache-2.0). Check the model card against your use before you download.
