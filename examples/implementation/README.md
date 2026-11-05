# ii-os workflow kit

The ii-os dashboard does not run models or agents itself. When someone presses
**Generate**, **Deploy** or **Update**, ii-os dispatches a named GitHub
workflow in a repository you connect to your workspace. That workflow does the
work on runners you own and reports the result back to ii-os.

This folder is a ready-made version of that connected repository. Agent runs
use the public
[II Agent Runtime](https://github.com/intelligent-iterations/ii-agent-runtime).
The kit contains no model weights and no credentials, and it points at no
host, registry or bucket: every runner, folder, image and credential is a
setting you fill in.

GitHub runs workflows only from a repository's root `.github/workflows/`
folder, so nothing in this folder runs inside the ii-os repository.

## What is in this folder

| Path | What it holds |
| --- | --- |
| `.ii-os/catalog.yaml` | One entry per dashboard action: its inputs, outputs, runtime estimate and the workflow it dispatches. |
| `.ii-os/runtimes/`, `.ii-os/agent-controller.json` | Agent configuration: the worker image, limits, credential references and the controller version. |
| `.github/workflows/` | The workflows ii-os dispatches, and the reviewed bodies and release workflows they call. |
| `.github/actions/ii-os-claim/` | Fetches a request's checked inputs and source files from ii-os. |
| `.github/actions/ii-os-complete/` | Uploads the results to your workspace storage and reports the final status. |
| `runners/<runner>/` | A runner image: its `Dockerfile`, task code, README and, for model runners, `models.json` (the model files it expects). |
| `scripts/` | Helpers the workflows call: settings checks, the isolated container run, model-folder checks, publishing and the agent controller. |
| `tests/` | Offline tests for the scripts, the runners and the workflow rules. |
| `docs/` | The detailed guides for [generation](docs/generation.md) and [agents](docs/agents.md). |

## How a generation request runs

1. **Dispatch.** ii-os dispatches the workflow with a request id only. Prompts
   and file ids never appear in the dispatch or the run's metadata.
2. **Claim.** The job proves its run to ii-os and receives the checked inputs
   and short-lived links to any source files.
3. **Run.** The runner image runs in a locked-down container with no network.
4. **Publish.** The host checks every output file, uploads it to your
   workspace storage and reports the result. A failure is reported with a
   stable error code, and the container and run folder are removed either way.

[docs/generation.md](docs/generation.md) covers each step. Agent and mobile
release workflows have their own flows, described in
[docs/agents.md](docs/agents.md) and in
[Mobile releases and FFmpeg engines](../../docs/mobile-release.md) in the
ii-os source.

## Adopt the kit

1. **Pick a layout.**
   - *Connected repository:* copy everything in this folder to the root of the
     repository your ii-os workspace connects to.
   - *Fork:* in a fork of ii-os, move everything in this folder to the root.
     The mobile release workflows need this layout, because they build the app
     from the repository they run in.

   Then delete the catalog entries, workflows and runner folders you will not
   serve. This README and `tests/test_readme_settings.py` go together: the
   test checks the Settings section of the root `README.md`. If your
   repository keeps its own README, move the Settings section into it or
   delete the test.
2. **Register runners** for the job kinds you serve (see
   [Features](#features)). Each `*_RUNS_ON` setting selects runners by label,
   so give them labels no other workflow uses.
3. **Build the runner images.** Build each runner you need as its README
   shows, push it to a registry your runners can pull from, and note its
   digest. Settings take a digest (`name@sha256:...`), never a tag.
4. **Place the model files.** Download the files each runner's `models.json`
   lists into `${II_OS_MODEL_ROOT}/<runner>/` on the GPU host. Read their
   licenses first (see [Licensing](#licensing)). Then check each profile you
   serve:

   ```bash
   python3 scripts/ii_os_model_folder.py verify --manifest runners/comfyui-image/models.json \
     --model-root "$II_OS_MODEL_ROOT" --profile z-image-turbo
   ```

5. **Fill in the settings** from the [Settings](#settings) tables.
6. **Connect it in ii-os.** Connect the repository to your workspace and
   enable the workflows you serve. Agents and mobile updates need more set-up:
   follow [docs/agents.md](docs/agents.md#adopt) and
   [Mobile releases and FFmpeg engines](../../docs/mobile-release.md).

## Features

"GPU" means one NVIDIA GPU with the NVIDIA Container Toolkit; a 24 GB card
covers every runner in the kit. Each runner's README gives its full hardware
needs, and [docs/generation.md](docs/generation.md#runner-hosts) gives disk
sizes.

| Dashboard feature | Catalog id | Workflow | Runner | Hardware |
| --- | --- | --- | --- | --- |
| Images: create | `image-create`, `image-create-flux2-klein`, `image-create-qwen-2512` | `z-image-turbo-text-to-image.yml` | [`comfyui-image`](runners/comfyui-image/README.md) | GPU, 24 GB VRAM, 32 GB RAM |
| Images: create from references | `image-create-reference-qwen-2511`, `image-create-reference-flux2-klein` | `qwen-image-edit.yml`, `flux2-klein-image-edit.yml` | `comfyui-image` | GPU, 24 GB VRAM, 32 GB RAM |
| Image edit and area edit (Z-Image) | `image-edit`, `image-inpaint` | `z-image-edit.yml` | `comfyui-image` | GPU, 24 GB VRAM |
| Image edit and area edit (Qwen) | `image-edit-qwen-2511`, `image-inpaint-qwen` | `qwen-image-edit.yml` | `comfyui-image` | GPU, 24 GB VRAM, 32 GB RAM |
| Image edit (FLUX.2 Klein) | `image-edit-flux2-klein` | `flux2-klein-image-edit.yml` | `comfyui-image` | GPU, 24 GB VRAM |
| Characters and storyboards | the image entries above, plus `image-to-video` to animate a storyboard panel | as above | as above | as above |
| Video: image to video | `image-to-video` | `ltx-image-to-video.yml` | [`ltx-video`](runners/ltx-video/README.md) | GPU, 24 GB VRAM, RAM for about 42 GB of weights |
| Video: MiniMax H3 studio | `text-to-video-minimax-h3` | `minimax-h3-text-to-video.yml` | [`minimax-h3`](runners/minimax-h3/README.md) | GPU, 24 GB VRAM, CUDA 13.0 driver (R580 or newer), model folder on a fast local NVMe disk |
| Video: upscale | `seedvr2-video-upscale` | `seedvr2-video-upscale.yml` | [`seedvr2-video`](runners/seedvr2-video/README.md) | GPU, 24 GB VRAM, 16 GB RAM |
| Video editor: export | `video-editor-render` | `video-editor-render.yml` | [`media-render`](runners/media-render/README.md) | CPU only: 4 cores, 8 GB RAM, 20 GB disk |
| Songs | `song-create-acestep-xl-sft` | `acestep-song-generation.yml` | [`acestep-song`](runners/acestep-song/README.md) | GPU, 24 GB VRAM, 16 GB RAM |
| Narration | `narration-create-chatterbox-tts` | `narration-generation.yml` | [`chatterbox-narration`](runners/chatterbox-narration/README.md) | A small GPU with a CUDA 12.4 driver or newer |
| Playground: classification | `classification-open-jev-9b` | `open-jev-classification.yml` | [`open-jev`](runners/open-jev/README.md) | GPU, 24 GB VRAM, CUDA 13.0 driver (R580 or newer), 8 GB RAM |
| Software Workshop: Deploy a ticket | none | `ii-os-agent-task.yml` → `ii-os-agent-work-ticket.yml` | [`agent-controller`](runners/agent-controller/README.md) host, [`agent-worker`](runners/agent-worker/README.md) image | A dedicated Linux x86-64 host with Docker and AppArmor; no GPU |
| Connect Codex | none | `ii-os-agent-task.yml` → `ii-os-codex-auth.yml`, `ii-os-codex-auth-finalize.yml` | `agent-controller` host, `agent-worker` image | The agent host |
| Agent permissions | none | `ii-os-agent-permissions.yml` → `ii-os-agent-permissions-impl.yml` | `agent-controller` host (no agent or model) | The agent host |
| Mobile app: Update (Android) | `mobile-update-android` | `mobile-update-android.yml` → `release-android.yml` | none: the job builds the app | A disposable Linux x86-64 runner |
| Mobile app: Update (iOS) | `mobile-update-ios` | `mobile-update-ios.yml` → `release-ios.yml` | none: the job builds the app | A disposable Apple Silicon Mac with Xcode |
| FFmpeg engines for mobile releases (you dispatch it) | none | `build-ffmpeg-engines.yml` | `ffmpeg-engines` | Linux x86-64 with Docker; a build takes hours |

The agent workflows have no catalog entry. In ii-os you enable
`ii-os-agent-task.yml` and `ii-os-agent-permissions.yml` for the repository
instead.

Two features are not served by this kit:

- **The local Qwen agent engine** (`qwen38-local`). The
  [`qwen-coder`](runners/qwen-coder/README.md) runner is included, but these
  workflows do not run it yet. See [Engines](docs/agents.md#engines).
- **Terminal sessions.** They use a session relay and a runner control plane,
  not workflows. See `docs/interactive-sessions.md` in the ii-os source.

Every other dashboard page runs in ii-os itself and needs no workflow.

## Settings

Set these under **Settings → Secrets and variables → Actions** in the
repository that runs the workflows. You only need the rows for the workflows
you keep.

A missing or malformed setting stops the job in its first step and names the
setting. Nothing falls back to a default host, folder, image or credential.
The `*_RUNS_ON` settings are read by GitHub before any step runs, so a missing
one fails the job as it starts.

### Shared

| Setting | Kind | Used by | Value |
| --- | --- | --- | --- |
| `II_OS_CONNECTOR_URL` | variable | generation and agent workflows | Your ii-os API base, `https://...`, with no query string. |
| `II_OS_TOKEN` | secret | generation workflows | The workflow token ii-os issued for this repository. |
| `II_OS_GPU_RUNS_ON` | variable | GPU generation jobs | JSON for `runs-on`, for example `["self-hosted","linux","gpu"]`. |
| `II_OS_CPU_RUNS_ON` | variable | render and status jobs, engine build, Android release | JSON for `runs-on`, for example `["self-hosted","linux"]`. |
| `II_OS_MACOS_RUNS_ON` | variable | iOS release | JSON for `runs-on`, for example `["self-hosted","macOS","ARM64"]`. |
| `II_OS_AGENT_RUNS_ON` | variable | every agent job | JSON for `runs-on` that selects only the dedicated agent host. |

### Generation

| Setting | Kind | Used by | Value |
| --- | --- | --- | --- |
| `II_OS_MODEL_ROOT` | variable | GPU generation workflows | Absolute folder on the GPU host with one folder per runner. Each runner reads only its own folder, read-only. |
| `II_OS_RUNNER_IMAGE_COMFYUI_IMAGE` | variable | the four image workflows | `registry.example.com/.../comfyui-image@sha256:...` |
| `II_OS_RUNNER_IMAGE_LTX_VIDEO` | variable | `ltx-image-to-video.yml` | `registry.example.com/.../ltx-video@sha256:...` |
| `II_OS_RUNNER_IMAGE_MINIMAX_H3` | variable | `minimax-h3-text-to-video.yml` | `registry.example.com/.../minimax-h3@sha256:...` |
| `II_OS_RUNNER_IMAGE_SEEDVR2_VIDEO` | variable | `seedvr2-video-upscale.yml` | `registry.example.com/.../seedvr2-video@sha256:...` |
| `II_OS_RUNNER_IMAGE_CHATTERBOX_NARRATION` | variable | `narration-generation.yml` | `registry.example.com/.../chatterbox-narration@sha256:...` |
| `II_OS_RUNNER_IMAGE_ACESTEP_SONG` | variable | `acestep-song-generation.yml` | `registry.example.com/.../acestep-song@sha256:...` |
| `II_OS_RUNNER_IMAGE_OPEN_JEV` | variable | `open-jev-classification.yml` | `registry.example.com/.../open-jev@sha256:...` |
| `II_OS_RUNNER_IMAGE_MEDIA_RENDER` | variable | `video-editor-render.yml` | `registry.example.com/.../media-render@sha256:...` |

### Agents

Put the secrets in the repository or in the `ii-os-agent-maintainer` and
`ii-os-agent-bootstrap` environments.
[docs/agents.md](docs/agents.md#adopt) explains those environments and the
protected tags ii-os checks before it allows a run.

| Setting | Kind | Used by | Value |
| --- | --- | --- | --- |
| `II_OS_AGENT_HOST_ID` | variable | every agent job | The identity the agent host declares in `/etc/ii-os/agent-host-id`. The job stops on any other host. |
| `II_OS_AGENT_STATE_DIR` | variable | every agent job | Absolute, private, persistent folder on the agent host for run history and results. |
| `II_OS_AGENT_ALLOCATION` | variable | work ticket, Connect Codex | JSON for the capacity these jobs may use on that host: `{"allocationId","monthlyLimit","capacity":{"cpu","memoryMiB","diskGiB"}}`. |
| `II_OS_GITHUB_APP_ID` | variable | every agent job | Numeric id of the GitHub App your ii-os deployment uses. |
| `II_OS_GITHUB_APP_SLUG` | variable | every agent job | That App's slug. Tokens from any other App are refused. |
| `II_OS_GITHUB_APP_PRIVATE_KEY` | secret | work ticket, permission installer | That App's private key. |
| `II_OS_AGENT_USAGE_API_KEY` | secret | work ticket | The workspace usage-reporting key from ii-os. Every run reports its usage, failed runs too. |
| `CODEX_AUTH_JSON` | secret | work ticket, Connect Codex | Written by Connect Codex. Never set it by hand; API keys are refused. |

### Mobile release and FFmpeg engines

Put the secrets in protected environments named `mobile-release-android` and
`mobile-release-ios`, limited to your release branch.

| Setting | Kind | Used by | Value |
| --- | --- | --- | --- |
| `II_OS_WORKFLOW_REPOSITORY` | variable | release and engine workflows | `owner/name` of your fork. The tools refuse to run anywhere else. |
| `II_OS_WORKFLOW_BRANCH` | variable | release and engine workflows | Your release branch. Releases run only from its reviewed head. |
| `II_OS_FFMPEG_ENGINE_STORE` | variable | engine build, Android release | Absolute folder on your Linux runners that stores engines, one folder per source commit. |
| `II_OS_RELEASE_EVIDENCE_DIR` | variable | Android release | Absolute folder on the Android runner that keeps each App Bundle and its engine evidence. |
| `II_OS_MOBILE_BUILD_NAME` | variable | Android and iOS release | Marketing version, such as `1.0.0`. |
| `II_OS_ANDROID_APPLICATION_ID` | variable | Android release | Your Android application id. |
| `II_OS_FIREBASE_EXPECTED_PROJECT_ID` | variable | Android release | The Firebase project your Android configuration must belong to. |
| `II_OS_WEB_ORIGIN` | variable | Android release | HTTPS origin of your ii-os deployment; the app calls `<origin>/api`. |
| `II_OS_GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER` | variable | Android release | Full resource name of the Workload Identity provider for Play uploads. |
| `II_OS_GOOGLE_PLAY_SERVICE_ACCOUNT` | variable | Android release | The service account allowed to upload to Google Play. |
| `II_OS_IOS_BUNDLE_ID` | variable | iOS release | Your iOS bundle id. |
| `II_OS_APPLE_TEAM_ID` | variable | iOS release | Your Apple team id. |
| `II_OS_CONTROL_API_BASE_URL` | variable | iOS release | HTTPS base URL of your ii-os API. |
| `II_OS_FIREBASE_AUTH_DOMAIN` | variable | iOS release | Your Firebase Auth domain. |
| `II_OS_ANDROID_UPLOAD_KEYSTORE_BASE64` | secret | Android release | Base64 of your Play upload keystore. |
| `II_OS_ANDROID_KEY_PROPERTIES` | secret | Android release | Three lines: `keyAlias`, `keyPassword`, `storePassword`. |
| `II_OS_ANDROID_GOOGLE_SERVICES_JSON` | secret | Android release | Your `google-services.json`, with exactly one client for your application id. |
| `II_OS_APP_STORE_CONNECT_API_KEY` | secret | iOS release | App Store Connect API private key (`.p8` text or its base64). |
| `II_OS_APP_STORE_CONNECT_API_KEY_ID` | secret | iOS release | Its key id. |
| `II_OS_APP_STORE_CONNECT_ISSUER_ID` | secret | iOS release | Its issuer id. |
| `II_OS_IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | secret | iOS release | Base64 of your Apple Distribution certificate (`.p12`). |
| `II_OS_IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | secret | iOS release | Its export password. |
| `II_OS_IOS_PROVISIONING_PROFILE_BASE64` | secret | iOS release | Base64 of your App Store provisioning profile. |
| `II_OS_IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64` | secret | iOS release | Base64 of your `GoogleService-Info.plist`. |

### In your ii-os deployment

These are ii-os settings, not repository settings, but the kit needs them:

- agents: `II_OS_AGENT_COORDINATOR_REPOSITORY`,
  `II_OS_AGENT_TRUSTED_SOURCE_MANIFEST_BASE64`, optionally
  `II_OS_AGENT_PUBLICATION_TARGETS`, and the app build define
  `II_OS_DEFAULT_AGENT_RUNTIME_REFERENCES`;
- mobile updates: `II_OS_MOBILE_UPDATE_REPOSITORY`. When it is empty, the
  Update button is hidden.

`docs/deployment.md` in the ii-os source describes them.

## Security model

- **Isolation.** Each model runs in a container with no network, the model
  folder and inputs mounted read-only, one writable output folder, every Linux
  capability dropped, no privilege escalation and a process limit. Each agent
  runs in its own worker container whose network is sealed after setup. The
  worker gets no Docker access, host network or credentials.
- **Least privilege.** Every workflow starts with `permissions: {}`, and each
  job asks only for what it needs. `id-token: write` appears only on jobs that
  prove their identity to ii-os or to a cloud provider. Checkouts keep no
  credentials, and third-party actions are pinned by commit.
- **No downloads at run time.** Model jobs never download weights. You place
  them once, and the host checks them against `models.json` before each run.
  Runner images are pinned by digest. Mobile releases use only FFmpeg engines
  you built, reviewed and pinned.
- **Credentials as files.** Credentials stay on the host side of a run and
  never enter a model container. Agent credentials are staged as private files
  (mode 0600) that only the trusted controller reads. Mobile signing material
  lives in run-owned folders that are deleted when the run ends.
- **Publication after cleanup.** An agent's change is pushed only after the
  runtime's cleanup and the removal of its credential files are both proven.
  ii-os then issues a short-lived writer for that one branch. Generated files
  are uploaded without overwriting anything, and ii-os checks them against
  your storage.
- **Dedicated runners.** Use these runners only for this repository's
  dispatched workflows. A self-hosted runner must never be reachable from a
  public repository's pull requests.

[docs/agents.md](docs/agents.md#security-model) maps each agent property to
the test that proves it.

## Licensing

The kit's own code is under the ii-os license (Apache-2.0). A few vendored
files carry their own notice, such as `runners/open-jev/LICENSE` and
`runners/minimax-h3/comfy_nodes/ii_os_minimax_h3/LICENSE-cab-sampler`.
Runner images install third-party software when you build them, such as
ComfyUI (GPL-3.0). If you distribute an image, you distribute that software
on its terms.

**The models are your responsibility.** The kit ships no weights. You choose
which models to download, and you must check each license against your use,
your users and where you run. Each runner's `models.json` lists every file
with its upstream source and license:

| Runner | Model files | Read before you download |
| --- | --- | --- |
| `comfyui-image` | [`models.json`](runners/comfyui-image/models.json) | Several upstream licenses; take each file from the source `models.json` names, because some copies elsewhere carry stricter terms. |
| `ltx-video` | [`models.json`](runners/ltx-video/models.json) | LTX-2 Community License: a paid license above a revenue threshold, and use restrictions you pass on to your users. |
| `minimax-h3` | [`models.json`](runners/minimax-h3/models.json) | Not licensed in the European Union, the United Kingdom, the Republic of Korea or the United States. Read [its license notes](runners/minimax-h3/README.md#read-the-license-first). |
| `seedvr2-video` | [`models.json`](runners/seedvr2-video/models.json) | Apache-2.0. |
| `chatterbox-narration` | [`models.json`](runners/chatterbox-narration/models.json) | MIT. Generated speech carries a watermark. |
| `acestep-song` | [`models.json`](runners/acestep-song/models.json) | MIT. |
| `open-jev` | [`models.json`](runners/open-jev/models.json) | Apache-2.0. |
| `qwen-coder` | [`models.json`](runners/qwen-coder/models.json) | Apache-2.0. |

[docs/generation.md](docs/generation.md#licenses) explains the choices for
each generation runner. The mobile apps you build embed FFmpeg under the LGPL;
read the
[licensing obligations](../../docs/mobile-release.md#licensing-obligations)
before you distribute one.

## Costs

The kit adds no GitHub-hosted runners, artifact storage or caches. If you
point a `*_RUNS_ON` setting at GitHub-hosted runners, a private repository
pays for those minutes. Models run on your own hardware. Agent runs use your
Codex subscription and report their usage to ii-os.

## Tests

Run the offline tests from the kit root:

```bash
python3 -m unittest discover -s . -t . -p 'test_*.py'
python3 -m unittest discover -s tests/agent -p 'test_*.py'
```

`tests/test_readme_settings.py` fails when a workflow or action reads a
setting that the Settings tables above do not list.

## More detail

- [docs/generation.md](docs/generation.md): the generation request flow,
  runner hosts, model folders, error codes and how to add a runner.
- [docs/agents.md](docs/agents.md): the Software Workshop, Connect Codex,
  agent permissions, and the GitHub environments and tags they need.
- [Mobile releases and FFmpeg engines](../../docs/mobile-release.md), in the
  ii-os source: the release workflows, their accounts and the engines they
  embed.
- Each runner's README: its hardware, model profiles and build command.
