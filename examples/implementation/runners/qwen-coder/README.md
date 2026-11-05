# qwen-coder runner

The container behind the Software Workshop's local Qwen agent engine
(`qwen38-local`). It runs Qwen3.8 27B (Q4_K_M GGUF) through Ollama 0.32.15 and
the OpenCode 1.18.21 coding agent on one NVIDIA GPU, inside a Bubblewrap
sandbox with no network path. It is an ephemeral, one-task runtime, not a model
service: start it for one ticket, collect its outputs, remove it.

| File | Purpose |
| --- | --- |
| `Dockerfile` | Ollama base image pinned by digest, OpenCode pinned by SHA-256, the sandbox tools, and the two scripts below. |
| `opencode.json` | OpenCode configuration: the local model only, a default-deny tool policy, no web access. |
| `models.json` | The one weight file the runner expects: path, size, SHA-256, upstream source, and license. Informational; nothing downloads it. |
| `prepare-model.sh` | One-time step that verifies your weight file against `models.json` and imports it into an Ollama store. |
| `run-agent.sh` | Runs one coding task in the sandbox and writes usage and runtime proof. |

## Requirements

- An x86-64 Linux host with Docker and the NVIDIA Container Toolkit.
- One NVIDIA GPU with at least 24 GB of memory. The run refuses to start
  unless the whole model and its 64,000-token context are resident on the GPU.
- About 40 GB of disk for the model folder: the weight file plus Ollama's copy
  of it.

## 1. Build and pin the image

```bash
docker build --build-arg TARGETARCH=amd64 -t registry.example.com/acme-co/qwen-coder:1 .
docker push registry.example.com/acme-co/qwen-coder:1
docker inspect --format '{{index .RepoDigests 0}}' registry.example.com/acme-co/qwen-coder:1
```

Use the printed `name@sha256:...` reference, never a tag, both in the
`II_OS_RUNNER_IMAGE_QWEN_CODER` repository variable and in the permission
profile's `fleet.image`. ii-os refuses a profile whose image is not pinned by
digest.

## 2. Fetch the model yourself

Workflows never download weights. Put the file listed in `models.json` under
your model root, then check it:

```bash
mkdir -p "$II_OS_MODEL_ROOT/qwen-coder/sources"
curl --fail --location \
  --output "$II_OS_MODEL_ROOT/qwen-coder/sources/Qwen3.8-27B-Q4_K_M.gguf" \
  "https://huggingface.co/ggml-org/Qwen3.8-27B-GGUF/resolve/0669b98607d47046c7c2b3f801011d54a08cfccf/Qwen3.8-27B-Q4_K_M.gguf"
sha256sum "$II_OS_MODEL_ROOT/qwen-coder/sources/Qwen3.8-27B-Q4_K_M.gguf"
# 31629f53165ab6a7dad8c9847dcfd1fdf55829dac1e6e748f4a68581b0033d34
```

The weights are Apache-2.0 licensed; read the upstream model card before you
use them.

## 3. Prepare the Ollama store once

Mount the model folder read-write for this one step only, with no network:

```bash
docker run --rm --network none \
  --mount type=bind,source="$II_OS_MODEL_ROOT/qwen-coder",target=/models \
  registry.example.com/acme-co/qwen-coder@sha256:<digest> \
  /usr/local/bin/qwen-coder-prepare-model
```

It verifies the file's size and SHA-256, imports it into
`$II_OS_MODEL_ROOT/qwen-coder/ollama`, and writes `model-manifest.json` next to
it. It refuses to touch an existing Ollama store it did not create. Every agent
run afterwards mounts the folder read-only.

## 4. Run contract

This is what your agent workflow does for one ticket. The workflow, not this
container, owns checkout, credentials, publication, and cleanup.

1. Stage the repository at the approved commit in a run-scoped directory owned
   by UID 10001, with its `.git` directory present, and write the ticket prompt
   to a file inside it.
2. Write the GitHub token and the usage-reporting key to root-owned mode-0600
   files. The run fails if the agent user can read either one; the agent never
   needs them.
3. Start the container from the digest in the approved permission profile:
   - `--gpus` with exactly one device, `--cpus` and `--memory` from the
     profile's `resources`, and `--network none`;
   - the model folder mounted read-only at `/models`;
   - the workspace at `/workspace` and a run-scoped proof directory, both
     writable;
   - a seccomp and AppArmor policy that lets Bubblewrap create user
     namespaces (Docker's defaults do not);
   - `QWEN_CODER_VRAM_LIMIT_MB` set to the profile's `resources.vram_mb`.
4. Run `/usr/local/bin/qwen-coder-run-agent /workspace /workspace/TASK.md
   /proof/opencode.jsonl /proof`. Its exit status is OpenCode's.
5. After the container exits, a trusted step outside it validates the diff and
   publishes it. Every Git metadata directory was read-only inside the sandbox.
6. Report usage from `/proof/opencode-usage.jsonl` under the model name
   `qwen3.8-27b-q4_k_m`, on success and on failure, then remove the workspace,
   proof directory, and credential files.

The proof directory receives:

| Output | Contents |
| --- | --- |
| `opencode.jsonl` | The full OpenCode event stream, including prompts and tool calls. Keep it on your own storage. |
| `opencode-usage.jsonl` | Only the `step_finish` events, which carry token counts and no prompt text. |
| `runtime-proof.json` | Model, context length, GPU residency, network isolation, GPU memory used, and versions. |
| `ollama-ps.json`, `nvidia-smi.csv`, `ollama.log` | The evidence `runtime-proof.json` summarises. |

## Security model

The script starts as root and re-enters itself as UID 10001 inside a Bubblewrap
user, PID, mount, and network namespace in which only loopback is up. OpenCode
reaches Ollama on `127.0.0.1` and nothing else; the run fails if
`https://example.com` is reachable. The root filesystem, `/models`, and every
Git metadata directory are read-only. OpenCode may read, edit, search, and run
shell commands in the workspace; web access, subagents, questions, skills, and
paths outside the workspace are denied. Before the task starts, the run proves
that exactly one model is loaded at the full 64,000-token context, that none of
it is offloaded to system memory, and that GPU memory use is within
`QWEN_CODER_VRAM_LIMIT_MB`.

## 5. Offer the engine in ii-os

ii-os offers `qwen38-local` only when its backend has
`II_OS_LOCAL_AGENT_ENGINES_BASE64`; see `docs/deployment.md`. That setting
names the runner capabilities your workflow uses to place the job and the exact
reservation. A permission profile for the engine must match it exactly and
carries no Codex credential:

```json
{
  "schema_version": 3,
  "engine": "qwen38-local",
  "id": "qwen38-repository-maintainer",
  "version": "2026-11-04.1",
  "display_name": "Repository maintainer",
  "description": "Implements and verifies repository changes with the local Qwen model, then opens a pull request.",
  "allowed_actions": ["Read and edit files in the selected repository", "Run repository tests and validation commands"],
  "denied_actions": ["Create new GitHub issues or Project items"],
  "repository_actions": {"mode": "pull_request"},
  "fleet": {
    "profile": "example-gpu-coder",
    "image": "registry.example.com/acme-co/qwen-coder@sha256:<digest>",
    "runtime_kind": "docker",
    "resources": {"ram_mb": 8192, "cpu": 8, "disk_gb": 40, "vram_mb": 16384, "timeout_s": 7200},
    "capabilities": ["runtime-docker", "auto-agent", "github-app-token", "agent-usage-reporting", "nvidia-gpu", "example-model-cache", "example-sandbox"]
  },
  "secret_injection": {
    "environment": "ii-os-agent-maintainer",
    "bindings": [
      {"id": "github-app-token", "capability": "github-app-token", "github_secret": "IIAUTO_GITHUB_TOKEN", "target": "file", "target_name": "GITHUB_TOKEN_FILE"},
      {"id": "agent-usage", "capability": "agent-usage-reporting", "github_secret": "II_OS_AGENT_USAGE_API_KEY", "target": "file", "target_name": "AGENT_USAGE_KEY_FILE"}
    ]
  },
  "workflow": {"file": "ii-os-agent-task.yml", "ref": "dev"}
}
```
