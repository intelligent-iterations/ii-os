# Agents: Software Workshop, Connect Codex and agent permissions

This part of the kit runs ii-os's coding agents. ii-os dispatches the workflows
below in your repository; they run a Codex agent in an isolated container on a
host you name, and hand the result back to ii-os, which owns approvals,
tickets, publication and the Workshop UI. The agent itself runs on the public
[II Agent Runtime](https://github.com/intelligent-iterations/ii-agent-runtime)
through ii-os's `agent_execution` package.

| Workflow | Started by | What it does |
| --- | --- | --- |
| `ii-os-agent-task.yml` | ii-os (Deploy, Connect Codex) | Dispatch surface. Routes `work_ticket`, `codex_auth` and `codex_auth_verify` to the reviewed bodies below at the same immutable tag. |
| `ii-os-agent-work-ticket.yml` | `ii-os-agent-task.yml` | One approved Workshop pass: consume the approval, run the agent, prove cleanup, publish the change, finalize the ticket. |
| `ii-os-codex-auth.yml` | `ii-os-agent-task.yml` | Connect Codex: device sign-in and a one-time write of the `CODEX_AUTH_JSON` secret. |
| `ii-os-codex-auth-finalize.yml` | `ii-os-agent-task.yml` | Verifies the stored credential with a fixed smoke prompt, then finalizes the session. |
| `ii-os-agent-permissions.yml` | ii-os (Agent permissions, after two approvals) | Thin installer surface that calls the reviewed body pinned at a commit. |
| `ii-os-agent-permissions-impl.yml` | `ii-os-agent-permissions.yml` | Validates the approved profile, writes the profile and its installation proof to `dev`. |

All jobs run on the runner in `II_OS_AGENT_RUNS_ON`. Nothing here runs on a
schedule, on push or on pull requests; GitHub never loads these files from
`examples/`, only after you copy them to your repository's
`.github/workflows/`.

## Adopt

You need: an ii-os deployment, its GitHub App installed on your repository, a
`dev` branch, and a Linux host for agents (see
[`runners/agent-controller`](../runners/agent-controller/README.md)).

1. **Copy the kit.** Copy `.github/workflows/ii-os-agent*.yml`,
   `.github/workflows/ii-os-codex-auth*.yml`, `scripts/agent/`,
   `scripts/agent_kit_manifest.py` and `.ii-os/` into the root of the
   repository agents will work on. Every repository that receives agent
   tickets carries its own copy.
2. **Build the images.** Build `runners/agent-worker` and push it; pin its
   digest in every `.ii-os/runtimes/*.json` (`environment.image`) and in
   `execution-binding.json` (`namespacePolicyImage`, `workspaceHelperImage`).
   Build your agent host from `runners/agent-controller` at the ii-os commit you
   run, and set that commit and repository in `.ii-os/agent-controller.json`.
3. **Describe your repository.** In each `.ii-os/runtimes/*.json` set
   `source.repository` and every credential binding's `resource` to your
   repository, `source.appId` and `source.installationId` to your GitHub App,
   and add `environment.setup.commands` if dependencies must install before the
   network is sealed. Choose CPU, memory, disk and time limits.
4. **Pin the installer.** In `ii-os-agent-permissions.yml` replace
   `acme-co/example-app` and the zero commit with the repository and full commit
   SHA that hold `ii-os-agent-permissions-impl.yml` (usually this repository at
   a reviewed commit on `dev`).
5. **Generate the reviewed-source values.**

   ```bash
   python3 scripts/agent_kit_manifest.py trusted-sources --write
   python3 scripts/agent_kit_manifest.py trusted-sources --base64     # II_OS_AGENT_TRUSTED_SOURCE_MANIFEST_BASE64
   python3 scripts/agent_kit_manifest.py runtime-references           # II_OS_DEFAULT_AGENT_RUNTIME_REFERENCES
   ```

   The kit ships no manifest: the reviewed blob identities belong to your
   copy. Commit the generated `.ii-os/agent-trusted-source-manifest.json` (the
   permission installer reads it) with the files it describes, and rerun all
   three whenever a workflow, script or runtime file changes.
6. **Configure ii-os.** Set the backend settings
   `II_OS_AGENT_TRUSTED_SOURCE_MANIFEST_BASE64` and
   `II_OS_AGENT_COORDINATOR_REPOSITORY` (the repository from step 4), and build
   the app with `--dart-define=II_OS_DEFAULT_AGENT_RUNTIME_REFERENCES=<json>`.
   In the workspace, add the repository and enable `ii-os-agent-task.yml` and
   `ii-os-agent-permissions.yml` for it.
7. **Configure GitHub** (repository settings, the table below, and these
   protections, which ii-os checks before it allows a deployment):
   - environment `ii-os-agent-maintainer`: one custom tag policy that names the
     current trusted tag exactly (`ii-os-agent-v4-<commit>`), no required
     reviewers, administrators cannot bypass;
   - environment `ii-os-agent-bootstrap`: one custom tag policy
     `ii-os-agent-v4-bootstrap-*`, no required reviewers, no bypass;
   - an active tag ruleset on `refs/tags/ii-os-agent-v4-*` that blocks updates
     and deletion with no bypass actors;
   - GitHub App permissions: Actions, Contents, Issues, Pull requests and
     Secrets read and write; Administration and Deployments read-only;
     Organization projects read and write if you use the Workshop board.
8. **Mark reviewed source.** Push the immutable tags from a reviewed `dev`
   commit: `ii-os-agent-v4-bootstrap-<commit>` before installing permissions,
   and `ii-os-agent-v4-<commit>` for agent runs. ii-os never creates them: the
   tag is what proves a person reviewed the code that will hold credentials.
9. **Install a permission profile** from ii-os's Agent permissions screen
   (two people approve; the installer commits the profile and its proof to
   `dev`), then **Connect Codex**, then press **Deploy** on a ticket.

## Settings

Workflow settings live in the repository (variables) or in the environments
above (secrets). A missing setting stops the job in its first step and names
the setting.

| Setting | Kind | Meaning |
| --- | --- | --- |
| `II_OS_CONNECTOR_URL` | variable | Your ii-os API base, for example `https://ii-os.example.com/api`. OIDC audience is `<url>/v1/codex-auth-sessions`; usage is reported to the same base. |
| `II_OS_AGENT_RUNS_ON` | variable | JSON `runs-on` for every agent job, for example `["self-hosted","linux","acme-agents"]`. It may equal `II_OS_CPU_RUNS_ON` only if that runner meets the agent host contract. |
| `II_OS_AGENT_HOST_ID` | variable | The host identity the runner must declare in `/etc/ii-os/agent-host-id`. This is the explicit runtime target. |
| `II_OS_AGENT_STATE_DIR` | variable | Absolute, persistent, private directory on the agent host for the admission ledger, execution history and retained results. |
| `II_OS_AGENT_ALLOCATION` | variable | JSON `{"allocationId","monthlyLimit","capacity":{"cpu","memoryMiB","diskGiB"}}`: the capacity these agent jobs alone may use on that host. |
| `II_OS_GITHUB_APP_ID` | variable | Numeric id of the GitHub App your ii-os deployment uses. |
| `II_OS_GITHUB_APP_SLUG` | variable | That App's slug. Workflows refuse tokens from any other App. |
| `II_OS_GITHUB_APP_PRIVATE_KEY` | secret | That App's private key. Used only for read tokens before cleanup and the installer's one write token after cleanup. |
| `II_OS_AGENT_USAGE_API_KEY` | secret | The workspace usage-reporting key from ii-os. Every run reports usage with it, including failed runs. |
| `CODEX_AUTH_JSON` | secret | Written only by Connect Codex. Never set it by hand; API keys are refused. |

ii-os backend: `II_OS_AGENT_COORDINATOR_REPOSITORY`,
`II_OS_AGENT_TRUSTED_SOURCE_MANIFEST_BASE64`, optional
`II_OS_AGENT_PUBLICATION_TARGETS`; app build define
`II_OS_DEFAULT_AGENT_RUNTIME_REFERENCES`.

## How ii-os uses these workflows

**Software Workshop.** A person presses Deploy on a Todo ticket. ii-os records
a one-use approval and dispatches `ii-os-agent-task.yml` with
`operation=work_ticket` on the trusted tag, then binds the exact run by its
title. The work-ticket body verifies the tag and the source, consumes the
approval with its OIDC identity (the call succeeds once), receives the frozen
ticket prompt, and stages the job's credentials as private files. The
controller runs the agent through the runtime, reports usage, and collects the
result and a Git bundle. Only after runtime cleanup and credential-file
removal are both proven does the job ask ii-os to authorize publication; ii-os
returns a short-lived writer for the exact branch, the job pushes the exact
bundle, and finalization moves the ticket. Every other outcome also finalizes,
with a bounded failure the Workshop shows.

**Connect Codex.** ii-os creates a session and dispatches
`operation=codex_auth`. The job binds itself to the session with OIDC, runs the
device sign-in client in the controller (the person enters the code ii-os
shows), smoke-tests the credential in a disposable worker, and writes
`CODEX_AUTH_JSON` through a one-time repository-secret writer ii-os issues for
that session. After cleanup, ii-os dispatches `operation=codex_auth_verify`,
which repeats the smoke with the stored secret and finalizes with its digest.
A ticket run may refresh the token; the refreshed value is written back only
after cleanup through the same one-time writer.

**Agent permissions.** Two people approve a profile in ii-os, which dispatches
`ii-os-agent-permissions.yml` on the bootstrap tag. The pinned body consumes
the fenced approval, validates the profile and computes the installation proof
(the blob of every reviewed file) in the controller without any agent or
model, commits the profile and proof to `dev` with a one-run write token, and
completes the approval. Profiles reference runtime files by path and SHA-256,
so changing a runtime file requires a new installation.

## Engines

Only the `codex` engine has an executor in these workflows: `agent_execution`
runs native Codex in the trusted controller with its tool executor inside the
worker, and schema 4 permission profiles approve that harness. The work-ticket
preflight reads the approved profile at the trusted commit and stops, before
the approval is consumed, when it names any other engine.

ii-os can also offer the local Qwen engine (`qwen38-local`, container in
[`runners/qwen-coder`](../runners/qwen-coder/README.md), enabled by the backend
setting `II_OS_LOCAL_AGENT_ENGINES_BASE64`). That engine needs its own executor
in `agent_execution` (its own harness, a credential-free model endpoint, usage
source and isolation proof) before these workflows can run it. When one
exists, it is selected through the approved profile's `engine` and its runtime
configuration, never through a hard-coded branch, host or runner in these
workflows.

## Security model

| Property | Where it is enforced | Evidence in this kit |
| --- | --- | --- |
| One-use approval | ii-os consumes it atomically; the run identity is bound by OIDC; retries skip the consume | backend; workflow contract test |
| Frozen prompt and source | The prompt digest and the approved profile digest travel through the run; runtime files are read at the trusted commit and hash-checked | `test_providers_runtime_ticket.py`, `controller_contract.test.mjs` |
| Explicit runtime target | The job stops unless the host declares `II_OS_AGENT_HOST_ID` and the reviewed controller pins; recovery refuses a different Docker Engine | `test_providers_host.py`, `test_providers_runtime_admin.py` |
| Credentials outside the worker, as 0600 files | Inode-bound job-scoped handoff; the controller resolves each value by digest and passes none to the worker | `test_handoff_*`, agent_execution suite |
| No API-key fallback | OAuth credentials without a refresh token or with `OPENAI_API_KEY` are refused before staging and before every write | `test_handoff_*`, `test_codex_*` |
| Codex OAuth only through Connect Codex's writer | One-time writer token, single use, revoked after the write | `test_codex_github_secret_writer.py` |
| Publication only after verified cleanup | Ordered, conditioned workflow steps that ii-os itself verifies | `functions/test/agent_workflow_kit_test.dart` |
| Usage reporting on every result path | The runtime reports success and failure; missing usage blocks publication and the rerun recovers it | `test_providers_runtime_ticket.py`, `worker_usage_reporter.test.mjs` |
| No second launch | One deployment intent per run; reruns recover the original execution under a kernel lock that proves the earlier controller exited | `test_providers_host.py` |
| Partitioned capacity | ii-os's `openAdmission` ledger over `II_OS_AGENT_ALLOCATION`; capacity returns only with a cleanup receipt | agent_execution suite |

These are source-level proofs. Container isolation, live OAuth and a real
GitHub run need a live run on your own host.

## Point at your own runtime host

The runtime target is configuration, never the caller's location: the runner
labels in `II_OS_AGENT_RUNS_ON` choose the machine, `/etc/ii-os/agent-host-id`
on that machine must equal `II_OS_AGENT_HOST_ID`, and the reviewed
`.ii-os/agent-controller.json` and `execution-binding.json` must match its
toolchain. To move agents to another host, build it from
`runners/agent-controller`, give it a new identity, point the runner label and
`II_OS_AGENT_HOST_ID` at it, and give it its own `II_OS_AGENT_STATE_DIR` and
allocation. A run started on one host is recovered only on that host.

## Costs

The kit uses no GitHub-hosted runners, caches or artifact storage unless you
point `II_OS_AGENT_RUNS_ON` at GitHub-hosted runners, which bill minutes on
private repositories. Model use is your Codex subscription; every run reports
its tokens to ii-os.
