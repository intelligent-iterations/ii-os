# Deployment boundary

ii-os does not ship an active deployment workflow. Operators copy and review
the inert examples under `examples/workflows/`, then bind them to their own
hosting project, repository variables, secrets, and cost controls.

The workflows the dashboard dispatches for generation, agents, and mobile
updates live in a separate repository that the operator connects to ii-os.
`examples/implementation/` is a ready-made, inert copy of that repository. Its
[README](../examples/implementation/README.md) explains how to adopt it and
lists every repository setting its workflows read.

Keep these values in the implementation repository or deployment platform,
never in the public source repository:

- cloud project, database, bucket, and service-account identifiers;
- GitHub organization, repository, environment, and runner topology;
- signing identities, mobile application IDs, and store credentials;
- secret names when they reveal private topology, and all secret values;
- production smoke-test identities, runbooks, migrations, and incident notes.

The source defaults are intentionally generic. Cross-repository agent
publication is disabled unless `II_OS_AGENT_COORDINATOR_REPOSITORY` and
`II_OS_AGENT_PUBLICATION_TARGETS` explicitly allow the exact repositories.
Agent execution additionally requires the implementation-owned
`II_OS_AGENT_TRUSTED_SOURCE_MANIFEST_BASE64`. Mobile update dispatch stays
disabled unless the implementation supplies `II_OS_MOBILE_UPDATE_REPOSITORY`.
[Mobile releases and FFmpeg engines](mobile-release.md) covers the release
workflows that repository runs and the engines they embed.

The Software Workshop always offers the Codex agent engine. The local Qwen
engine (`qwen38-local`), which runs its own model on the operator's GPU runner,
is offered only when the implementation supplies
`II_OS_LOCAL_AGENT_ENGINES_BASE64`: base64 of a JSON document naming the exact
execution profile, runner capabilities, and resource reservation that every
`qwen38-local` permission profile must match.

```json
{
  "schema_version": 1,
  "engines": {
    "qwen38-local": {
      "profile": "example-gpu-coder",
      "capabilities": [
        "runtime-docker",
        "auto-agent",
        "github-app-token",
        "agent-usage-reporting",
        "nvidia-gpu",
        "example-model-cache",
        "example-sandbox"
      ],
      "resources": {
        "ram_mb": 8192,
        "cpu": 8,
        "disk_gb": 40,
        "vram_mb": 16384,
        "timeout_s": 7200
      }
    }
  }
}
```

The capabilities must include `runtime-docker`, `github-app-token`, and
`agent-usage-reporting` and may not include `codex-oauth`; `vram_mb` is
required. The profile's image must still be pinned by `sha256` digest. Without
the setting, profiles naming the engine are left out of the profile list and
refused at install, activation, and dispatch with
`agent_engine_not_configured`; an invalid value stops the API at startup with
an error naming the setting. The container that runs the engine is described
in `examples/implementation/runners/qwen-coder/`.

`II_OS_RUNNER_CAPACITY_PROVIDER` says where runner capacity reports come from.
The default, `none`, suits a deployment with no runner control plane, for
example when the workflow kit in `examples/implementation/` runs on your own
GitHub runners: classification is offered without reading any report, and the
workflow's model-folder check names a missing model when the run starts. Set
`fleet` when a runner control plane reports to this deployment: each
organization's report (**Infrastructure**) is read, and classification is
offered only while a fresh, healthy host advertises the open JEV runtime; a
missing, stale, or unreadable report keeps it waiting.
Any other value stops the API at startup with an error naming the setting.
Song render choices use provider-neutral defaults and may be replaced with a
validated `II_OS_SONG_RENDER_PROFILES_JSON` list owned by the implementation.

Before enabling a copied workflow, calculate its expected and worst-case
runner, cloud, storage, transfer, and retry costs. Add bounded concurrency,
timeouts, retry limits, and a terminal cleanup step appropriate to your
provider.

The repository's own quality, CodeQL, and Scorecard workflows are deliberately
limited to standard GitHub-hosted Linux runners in a public repository. They
upload no Actions artifacts, create no caches, call no cloud or model provider,
and have per-job timeouts. Under GitHub's public-standard-runner terms their
expected and worst-case GitHub charge is $0. Larger runners, private-repository
execution, artifacts, caches, Packages, and deployment are outside that
approved envelope and remain disabled.

## Prompt enhancement credentials

An explicit Enhance action can use a pasted DeepSeek API key stored encrypted
for its workspace, or a Secret Manager version. Secret Manager payloads must
be JSON bound to the exact organization, workspace, and purpose:

```json
{
  "schemaVersion": 1,
  "purpose": "ii-os-deepseek",
  "organizationId": "example-organization",
  "workspaceId": "example-workspace",
  "apiKey": "replace-with-your-deepseek-key"
}
```

The secret owner supplies the real identifiers and grants the backend access
only to that secret. The backend verifies these bindings on every read before
using the key. A raw key, another workspace's payload, or an unrelated secret
is rejected without contacting DeepSeek. Existing raw-key secret versions must
be replaced with this bound format before Secret Manager enhancement can work;
pasted keys are unaffected. Keep payloads and real identifiers out of source.
