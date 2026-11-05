# Agent worker image: the isolated container the runtime starts for each run.
# Pin the pushed digest in .ii-os/runtimes/*.json ("environment.image") and in
# .ii-os/runtimes/execution-binding.json (namespacePolicyImage and
# workspaceHelperImage use the same image). Rebuild and re-pin to change Codex.
#
#   docker buildx build --platform linux/amd64 -t registry.example.com/acme-co/ii-os-agent-worker:codex-0.164.0 \
#     --push runners/agent-worker
#
# The runtime checks at launch: /bin/sleep, Node.js, Git, `codex --version`
# equal to harness.version, and a usable UID/GID 10001 under a read-only root.
# apparmor and e2fsprogs serve the runtime's user-namespace policy and bounded
# disk helpers. Add your repository's toolchains in a derived image and keep
# their caches under /workspace, which the runtime bounds per run.
# Base images are the same public digests the agent runtime's own live proof uses.
FROM node@sha256:363e1587494626837fa7f9a23bdb453d13b0ff3c67c705c2805cfc69c2d2fad7 AS node
FROM ubuntu@sha256:78d4744ead1f5b19b04d0df558ab182a5300903900755e515b2ca4d10eb2044d
COPY --from=node /usr/local/ /usr/local/
ARG CODEX_VERSION=0.164.0
ENV DEBIAN_FRONTEND=noninteractive NPM_CONFIG_FUND=false NPM_CONFIG_UPDATE_NOTIFIER=false
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      ca-certificates git python3 util-linux e2fsprogs apparmor \
      ripgrep jq patch diffutils procps file unzip xz-utils make gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*
RUN npm install --global --no-audit --no-fund "@openai/codex@${CODEX_VERSION}" \
 && test "$(codex --version)" = "codex-cli ${CODEX_VERSION}" \
 && npm cache clean --force \
 && rm -rf /root/.npm /root/.codex /root/.config \
 && find /tmp -mindepth 1 -delete
RUN groupadd --gid 10001 agent \
 && useradd --uid 10001 --gid 10001 --no-create-home --home-dir /workspace/user agent \
 && for tool in node git python3 rg jq make gcc mkfs.ext4 apparmor_parser sleep; do command -v "$tool" >/dev/null || exit 1; done
WORKDIR /workspace
ENTRYPOINT []
CMD ["/bin/sleep", "infinity"]
