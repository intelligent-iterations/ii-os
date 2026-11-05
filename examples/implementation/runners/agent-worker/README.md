# Agent worker image

The agent runs inside this image, in a container the agent runtime creates and
removes for each run. The runtime runs it with a read-only root filesystem, a
bounded writable `/workspace`, UID 10001, CPU and memory caps, and no network
after dependency setup. It never receives the Codex OAuth credential, the
GitHub App key, the usage-reporting key, or Docker access.

Build it, push it to a registry your agent hosts can pull from, and pin the
digest in three places:

- `environment.image` in every `.ii-os/runtimes/*.json` configuration;
- `namespacePolicyImage` and `workspaceHelperImage` in
  `.ii-os/runtimes/execution-binding.json`.

Changing those files changes their SHA-256, so profiles approved before the
change stop authorizing runs until the permission installer runs again.

The Codex version is pinned (`CODEX_VERSION`, default `0.164.0`) and must equal
`harness.version` in the runtime configurations and the controller host's
Codex. Add language toolchains your repository needs (for example Flutter or
Go) in a derived image; keep their caches under `/workspace`.
