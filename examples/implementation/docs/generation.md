# Generation workflows

The ii-os dashboard creates images, video, narration, songs, classifications
and editor exports by dispatching GitHub workflows in the repository you
connect to it. This kit ships those workflows, the runner images they start,
and the scripts that move data between ii-os, your runner and your workspace
bucket. Every host, folder, image and credential is a repository setting you
fill in; nothing in the kit points at anyone else's infrastructure.

## How one request runs

1. **Dispatch.** The dashboard reads `.ii-os/catalog.yaml` from your repository
   and dispatches the workflow an entry names, with only `ii_request_id` (and
   `ii_payload_mode=claim`). Prompts and source ids never appear in the
   dispatch event or the run's metadata.
2. **Claim** (`.github/actions/ii-os-claim`). The job proves its exact run to
   ii-os with `II_OS_TOKEN`; ii-os checks the run against the GitHub API and
   answers with the validated inputs, the workspace upload contract, and
   short-lived signed URLs for any source media. The action writes a private
   run directory under `RUNNER_TEMP`:

   ```text
   ii-os-run-<run id>-<attempt>/      mode 0700, ownership marker for this run
     in/inputs.json                    the claimed inputs (strings)
     in/sources.json                   staged sources in order, with sha256 (no URLs)
     in/sources/NN.<ext>               the source files
     out/                              the only folder the runner can write
   ```

3. **Plan.** `runners/<runner>/entrypoint.py plan` validates the request with
   plain `python3` on the host and names the model profile it needs, before
   any image is pulled or model loaded. Only the profile is logged.
4. **Check the model folder.** `scripts/ii_os_model_folder.py check` confirms
   that `${II_OS_MODEL_ROOT}/<runner>/` holds every file of that profile at the
   size `runners/<runner>/models.json` lists.
5. **Run, isolated** (`scripts/ii_os_run_container.py`). The digest-pinned
   runner image runs with `--network none`, the model folder read-only at
   `/models`, `in/` read-only, `out/` writable, the runner's own uid:gid, every
   capability dropped, no privilege escalation, a process limit and a private
   `/tmp`. It writes its files and `out/result.json`.
6. **Publish** (`.github/actions/ii-os-complete`). The host validates
   `result.json` and every file it names (plain names inside `out/`, regular
   files, a content type the catalog entry declares, bytes that match that
   type, under the catalog's size ceiling). It then mints a short-lived
   credential through the workspace's workload identity federation, uploads
   each file under the request's object prefix with `ifGenerationMatch=0`
   (nothing is ever overwritten) and the `ii-os-sha256` metadata, and reports
   the artifacts to ii-os, which verifies them against the bucket.
7. **Fail closed.** If anything fails, the job reports `failed` (or
   `cancelled`) with a stable error code. A separate `report-terminal-status`
   job covers runs whose GPU job never started or never finished. The
   container and the run directory are removed at the end of every run.

## Adopt the kit

1. Copy everything under `examples/implementation/` to the root of the
   repository your ii-os workspace connects to (or, in a fork of ii-os, move it
   to the root). GitHub only loads workflows from the root `.github/workflows/`;
   the copies under `examples/` never run.
2. Register self-hosted runners for the jobs (see [Runner hosts](#runner-hosts)).
3. Build each runner image you need from `runners/<runner>/Dockerfile`, push it
   to a registry your runner hosts can pull from, and record its digest.
4. Fetch each runner's model files into `${II_OS_MODEL_ROOT}/<runner>/` on the
   GPU host and run `scripts/ii_os_model_folder.py verify` once per profile.
5. Set the repository settings below.
6. In ii-os, connect the repository and enable the catalog entries you serve.
   Delete the entries (and workflows) for runners you do not deploy.

## Settings

Set these under **Settings → Secrets and variables → Actions** of the
repository. A missing or malformed setting stops the job in its first step
with the setting's name; nothing falls back to a default host, folder or image.

| Setting | Kind | Used by | Value |
| --- | --- | --- | --- |
| `II_OS_CONNECTOR_URL` | variable | every workflow | Your ii-os API base, `https://...`, no query string. |
| `II_OS_TOKEN` | secret | every workflow | The workflow token ii-os issued for this repository. |
| `II_OS_GPU_RUNS_ON` | variable | GPU jobs | JSON for `runs-on`, e.g. `["self-hosted","linux","gpu"]`. |
| `II_OS_CPU_RUNS_ON` | variable | render job, terminal-status jobs | JSON for `runs-on`, e.g. `["self-hosted","linux"]`. |
| `II_OS_MODEL_ROOT` | variable | GPU workflows | Absolute folder on the GPU host holding one folder per runner. |
| `II_OS_RUNNER_IMAGE_COMFYUI_IMAGE` | variable | the four image workflows | `registry/.../comfyui-image@sha256:...` |
| `II_OS_RUNNER_IMAGE_LTX_VIDEO` | variable | `ltx-image-to-video.yml` | `registry/.../ltx-video@sha256:...` |
| `II_OS_RUNNER_IMAGE_MINIMAX_H3` | variable | `minimax-h3-text-to-video.yml` | `registry/.../minimax-h3@sha256:...` |
| `II_OS_RUNNER_IMAGE_SEEDVR2_VIDEO` | variable | `seedvr2-video-upscale.yml` | `registry/.../seedvr2-video@sha256:...` |
| `II_OS_RUNNER_IMAGE_CHATTERBOX_NARRATION` | variable | `narration-generation.yml` | `registry/.../chatterbox-narration@sha256:...` |
| `II_OS_RUNNER_IMAGE_ACESTEP_SONG` | variable | `acestep-song-generation.yml` | `registry/.../acestep-song@sha256:...` |
| `II_OS_RUNNER_IMAGE_OPEN_JEV` | variable | `open-jev-classification.yml` | `registry/.../open-jev@sha256:...` |
| `II_OS_RUNNER_IMAGE_MEDIA_RENDER` | variable | `video-editor-render.yml` | `registry/.../media-render@sha256:...` |

You only need the runner image settings for the workflows you keep.

`II_OS_GPU_RUNS_ON` and `II_OS_CPU_RUNS_ON` are read by GitHub before any
step runs; when one is missing GitHub fails the job while evaluating
`runs-on`.

Optional: any variable named `II_OS_OPTION_<NAME>` that you add to a job's
`env` is passed into the runner container, for runner-specific tuning. No
other host environment reaches the container.

## Workflows

| Workflow | Catalog ids | Runner | Runs on | Timeout |
| --- | --- | --- | --- | --- |
| `z-image-turbo-text-to-image.yml` | `image-create`, `image-create-flux2-klein`, `image-create-qwen-2512` | `comfyui-image` | GPU | 90 min |
| `z-image-edit.yml` | `image-edit`, `image-inpaint` | `comfyui-image` | GPU | 90 min |
| `qwen-image-edit.yml` | `image-edit-qwen-2511`, `image-inpaint-qwen`, `image-create-reference-qwen-2511` | `comfyui-image` | GPU | 90 min |
| `flux2-klein-image-edit.yml` | `image-edit-flux2-klein`, `image-create-reference-flux2-klein` | `comfyui-image` | GPU | 90 min |
| `ltx-image-to-video.yml` | `image-to-video` | `ltx-video` | GPU | 120 min |
| `minimax-h3-text-to-video.yml` | `text-to-video-minimax-h3` | `minimax-h3` | GPU | 360 min |
| `seedvr2-video-upscale.yml` | `seedvr2-video-upscale` | `seedvr2-video` | GPU | 120 min |
| `narration-generation.yml` | `narration-create-chatterbox-tts` | `chatterbox-narration` | GPU | 45 min |
| `acestep-song-generation.yml` | `song-create-acestep-xl-sft` | `acestep-song` | GPU | 120 min |
| `open-jev-classification.yml` | `classification-open-jev-9b` | `open-jev` | GPU | 45 min |
| `video-editor-render.yml` | `video-editor-render` | `media-render` | CPU | 90 min |

Each runner's README lists its hardware, model profiles and build command.

Every workflow is `workflow_dispatch` only, has `permissions: {}` at the top
and least privilege per job (`id-token: write` only on the job that uploads),
a timeout on every job, one concurrency group per request, third-party
actions pinned by commit, and no artifact uploads or caches.

The kit also carries the mobile release workflows: `mobile-update-android.yml`
and `mobile-update-ios.yml` (catalog ids `mobile-update-android` and
`mobile-update-ios`), the `release-android.yml` and `release-ios.yml`
workflows they call, and `build-ffmpeg-engines.yml`. They build the app from
the repository they run in, so they need the fork layout; the two release
workflows also accept `workflow_call` from their wrappers. See
`docs/mobile-release.md` in the ii-os source for their settings.

## Runner hosts

- **GPU host:** x86-64 Linux, an NVIDIA GPU (24 GB of VRAM covers every runner
  in this kit), a driver supporting CUDA 13.0 for `comfyui-image`, `ltx-video`,
  `seedvr2-video`, `open-jev` and `minimax-h3` (R580 or newer), Docker with the NVIDIA Container Toolkit, `python3` 3.9 or later,
  and the GitHub Actions runner running as a user that may use Docker. Plan
  for 32 GB of RAM or more: LTX offloads part of its 29 GB checkpoint to system
  memory. Size the disk for the model folders you deploy (about 114 GB for every `comfyui-image` profile,
  43 GB for `ltx-video`, 42-65 GB for `minimax-h3`, 7-11 GB for
  `seedvr2-video`, 39 GB for `acestep-song`, 3 GB for `chatterbox-narration`,
  18 GB for `open-jev`). Keep the `minimax-h3` folder on a fast local NVMe
  disk: ComfyUI streams its weights from it.
- **CPU host:** x86-64 Linux with Docker and `python3`.
- The runner's `RUNNER_TEMP` must be bind-mountable by the Docker daemon
  (runner on the host, or a containerized runner whose work directory has the
  same path on the host).
- Use these runners only for this repository's dispatched workflows. A
  self-hosted runner must never be reachable from a public repository's pull
  requests.

## Model folders

Each runner reads `${II_OS_MODEL_ROOT}/<runner>/` and nothing else. Its
`models.json` lists every file: path inside the folder, size, sha256, a source
URL pinned to an upstream commit, the upstream license, and whether the file
is optional. The kit never downloads weights; you fetch them once.

```bash
python3 scripts/ii_os_model_folder.py list --manifest runners/comfyui-image/models.json
python3 scripts/ii_os_model_folder.py verify --manifest runners/comfyui-image/models.json \
  --model-root "$II_OS_MODEL_ROOT" --profile z-image-turbo
```

Symlinks inside a runner folder are fine; a symlink that points outside it
fails the check, because only the runner folder is mounted in the container.

### Licenses

Read each file's license in `models.json` before you download it, and check it
against your use. Points to decide on deliberately:

| Runner | Note |
| --- | --- |
| `comfyui-image` | The FLUX.2 VAE is listed from the Apache-2.0 FLUX.2 Klein repository. Another copy lives in the `flux2-dev` repository under the non-commercial FLUX.2 [dev] license. The Qwen2.5-VL text encoder is listed from the Apache-2.0 Qwen-Image repack; a byte-identical copy in a HunyuanVideo repack carries a community license that excludes some territories. |
| `ltx-video` | LTX-2.3 weights are under the LTX-2 Community License: a paid commercial license above a revenue threshold, use restrictions you must pass on if you host for others, and export terms. The Gemma text encoder follows the Gemma Terms of Use. The abliterated Gemma LoRA states no license; it is optional and the workflow never needs it. |
| `minimax-h3` | The MiniMax H3 Community License is not granted in the European Union, the United Kingdom, the Republic of Korea or the United States, and forbids use of the model or its outputs there. Above US$20 million yearly revenue a commercial product needs MiniMax's written authorization. Anyone you let generate must be bound to its use restrictions. The Turbo LoRA states Apache-2.0 but is a MiniMax H3 derivative. See [MiniMax H3](#minimax-h3). |
| `seedvr2-video` | Apache-2.0 throughout. The FP8 file is optional and only used as a last out-of-memory fallback. |
| `chatterbox-narration` | MIT. Generated speech carries Resemble's Perth watermark. Chatterbox Turbo speaks English; `language` is recorded, not used to switch voices. |
| `acestep-song` | MIT, including the Qwen3 embedding model the repository redistributes (Apache-2.0 upstream). The image installs the runner-specific hashed runtime and build locks against patched, pinned upstream source. |
| `open-jev` | Apache-2.0 model; the classification engine is vendored under Apache-2.0 (see `runners/open-jev/LICENSE`). |

## Runner dependencies

A runner image that installs Python packages takes them only from two files
in its folder, installed with `pip install --require-hashes --no-deps`:
`requirements.lock.txt` (what the runner imports) and
`requirements-build.lock.txt` (the installer, installed first). Every package
has an exact version and a sha256, and nothing is resolved at build time, so
the image holds exactly what the files list. Dependency scanners such as
`osv-scanner` read `requirements*.txt`, so scanning your copy of the kit
checks what the images install. Each runner README says how to recompile its
files after a pin or a pinned revision changes.

ACE-Step and its vendored nano-vllm are built from patched, pinned source using
hash-locked build tools with `--no-build-isolation`. Its image uses a
system-Python 3.12 virtual environment and does not install a flash-attention
URL wheel.

The lock-file scan does not cover base images, apt packages, pinned source
checkouts, the Flutter SDK in `media-render`, or the OpenCode binary in
`qwen-coder`. Base-image digests, source commits, and binary checksums are
recorded separately in the Dockerfiles and runner manifests. Apt packages
without explicit versions resolve from the selected distribution at build time.

## Error codes

Each workflow reports `<area>_failed` or `<area>_cancelled` to ii-os:
`image_generation_*`, `image_edit_*`, `video_generation_*`, `minimax_h3_workflow_*`,
`video_upscale_*`, `narration_generation_*`, `song_generation_*`,
`classification_workflow_*` and `video_editor_render_*`. A runner may report a
more specific code its workflow allows by writing `out/failure.json`:
`classification_request_rejected` when the model cannot answer the question
shapes, `video_upscale_source_unsupported` when a source video is outside the
upscaler's limits, and `minimax_h3_reference_rejected` when a MiniMax H3
reference clip is outside the model's limits. The classification workflow also
runs its model-folder check with `--work-dir` and `--failure-code
classification_model_missing`, so a GPU runner without the open JEV files is
reported as a missing model rather than a generic failure.

An ii-os deployment with no runner control plane reporting capacity sets the
backend setting `II_OS_RUNNER_CAPACITY_PROVIDER=none` (see the ii-os
`docs/deployment.md`). The dashboard then offers classification without
waiting for a capacity report, and this check is what tells the person when
the model is missing.

Classification results are published at `open-jev/decisions.json` under the
request prefix, the path the dashboard reads; every other artifact is named by
the host.

## MiniMax H3

`minimax-h3-text-to-video.yml` serves the dashboard's MiniMax H3 studio
(catalog id `text-to-video-minimax-h3`, kept for compatibility although it
serves every mode): 4 to 15 seconds of 720p video at 24 fps with the model's
own stereo audio, from text alone, from a first and/or last frame, from up to
12 image, video and audio references, by editing a source video, or by
continuing one. `performance_mode` picks Quality (10-step CAB sampler, the
default) or Turbo (a pinned four-step LoRA, endpoint modes only).

- **License before anything else.** MiniMax H3 is open weights under a
  community license that is not granted in the European Union, the United
  Kingdom, the Republic of Korea or the United States. Do not deploy the runner
  for hosts or people there unless MiniMax has licensed you separately. Read
  [`runners/minimax-h3/README.md`](../runners/minimax-h3/README.md#read-the-license-first)
  for the revenue threshold and the obligations that come with letting others
  generate.
- **The dashboard decides what it shows from the catalog entry.** Reference,
  edit and continuation modes appear only because the entry declares
  `generation_mode` and `reference_manifest`, video editing because it also
  declares `edit_operation` and `identity_replacement_consent`, and the
  Quality/Turbo choice because it declares `performance_mode`. Remove inputs
  to hide modes you do not want to offer.
- **The claim stages every reference.** The workflow claims up to 12 sources
  of any kind, each with its role. The runner checks them against the
  manifest on the host, measures each clip in the container before ComfyUI
  starts, and refuses clips outside the model's limits with
  `minimax_h3_reference_rejected`.
- **Size it for long jobs.** A 15-second Quality render took about 33 minutes
  on a 24 GB GPU, Turbo about 15, and a continuation several times longer, so
  the generate job allows 360 minutes. The runner sets no GPU power or thermal
  limits; set those on your host if your hardware needs them.
- **One image, three model profiles.** The image compiles SageAttention for
  the GPU architectures you pass at build time and installs every Python
  package from a hashed lock. The model folder holds `fl2va`, `fl2va-turbo`
  and `ref2va` profiles (42.5 to 44.4 GB each, 65.4 GB for all three).

## Adding a runner

A runner is a folder under `runners/` with a `Dockerfile` (built from the kit
root so it can copy `runners/common/`), an `entrypoint.py` mapping task names
to modules, task modules with `plan(request)` and `run(plan, request,
context)`, a `models.json`, and a README. `plan` must use only the Python
standard library. The shared actions do not know which model runs: role-aware
sources (for example a multimodal `reference_manifest`) arrive in
`in/sources.json` with their `kind`, `role` and `ordinal`, so a new runner only
adds its folder, a workflow modelled on an existing one, and catalog entries.
