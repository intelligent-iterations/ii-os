# Agent controller toolchain: everything the trusted controller process needs
# on the runtime host, at the fixed paths the reviewed execution binding names.
# Use it as the base of the single-use runner image (or VM image) that serves
# II_OS_AGENT_RUNS_ON; see README.md for the host contract and the Docker
# access requirement. It contains no credentials and no agent workload.
#
#   docker buildx build --platform linux/amd64 \
#     --build-arg II_OS_REPOSITORY=acme-co/ii-os --build-arg II_OS_COMMIT=<40-character ii-os commit> \
#     --build-arg II_OS_AGENT_HOST_ID=acme-agent-host -t registry.example.com/acme-co/ii-os-agent-controller \
#     runners/agent-controller
#
# Base images are the same public digests the agent runtime's own live proof uses.
FROM docker@sha256:000bb62ff495f986c9f5578eb67cc2cb98b91138eda81d7762d5371eb8a497fe AS docker-tools
FROM node@sha256:363e1587494626837fa7f9a23bdb453d13b0ff3c67c705c2805cfc69c2d2fad7 AS node
FROM ubuntu@sha256:78d4744ead1f5b19b04d0df558ab182a5300903900755e515b2ca4d10eb2044d
COPY --from=node /usr/local/ /usr/local/
COPY --from=docker-tools /usr/local/bin/docker /usr/local/bin/docker
ENV DEBIAN_FRONTEND=noninteractive NPM_CONFIG_FUND=false NPM_CONFIG_UPDATE_NOTIFIER=false
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      ca-certificates curl gh git jq python3 sudo iptables iproute2 unzip util-linux apparmor \
 && rm -rf /var/lib/apt/lists/*
# The controller runs native Codex itself; it must equal the worker's version.
ARG CODEX_VERSION=0.164.0
RUN npm install --global --no-audit --no-fund "@openai/codex@${CODEX_VERSION}" \
 && test "$(codex --version)" = "codex-cli ${CODEX_VERSION}" \
 && npm cache clean --force && rm -rf /root/.npm /root/.codex /root/.config
ARG TARGETARCH
ARG TOFU_VERSION=1.12.6
RUN set -eu; arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    curl -fsSLo /tmp/tofu.zip "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${arch}.zip"; \
    curl -fsSLo /tmp/checksums "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS"; \
    expected="$(awk -v f="tofu_${TOFU_VERSION}_linux_${arch}.zip" '$2==f {print $1}' /tmp/checksums)"; \
    test -n "$expected"; echo "$expected  /tmp/tofu.zip" | sha256sum -c -; \
    unzip /tmp/tofu.zip tofu -d /usr/local/bin; rm /tmp/tofu.zip /tmp/checksums; tofu version
# ii-os's agent_execution package at the exact commit the reviewed kit pins in
# .ii-os/agent-controller.json. Its runtime dependency is pinned by commit too.
ARG II_OS_REPOSITORY
ARG II_OS_COMMIT
RUN set -eu; \
    echo "$II_OS_REPOSITORY" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; \
    echo "$II_OS_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; \
    git init --quiet /tmp/ii-os; \
    git -C /tmp/ii-os fetch --quiet --depth 1 "https://github.com/${II_OS_REPOSITORY}.git" "$II_OS_COMMIT"; \
    git -C /tmp/ii-os checkout --quiet --detach FETCH_HEAD; \
    test "$(git -C /tmp/ii-os rev-parse HEAD)" = "$II_OS_COMMIT"; \
    mkdir -p /opt/ii-os; cp -R /tmp/ii-os/agent_execution /opt/ii-os/agent_execution; rm -rf /tmp/ii-os; \
    cd /opt/ii-os/agent_execution; npm ci --ignore-scripts --no-audit --no-fund; npm cache clean --force; \
    runtime="$(node -p 'Object.values(require("/opt/ii-os/agent_execution/package.json").dependencies)[0].split("#")[1]')"; \
    echo "$runtime" | grep -Eq '^[0-9a-f]{40}$'; \
    jq -n --arg repository "$II_OS_REPOSITORY" --arg commit "$II_OS_COMMIT" --arg runtime "$runtime" --arg codex "$CODEX_VERSION" \
      '{schemaVersion: 1, iiOsRepository: $repository, iiOsCommit: $commit, runtimeRevision: $runtime, codexVersion: $codex}' \
      > /opt/ii-os/agent-controller.json; \
    chmod -R go-w /opt/ii-os
# The identity II_OS_AGENT_HOST_ID must name; a job on any other host stops.
ARG II_OS_AGENT_HOST_ID
RUN set -eu; echo "$II_OS_AGENT_HOST_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'; \
    mkdir -p /etc/ii-os; printf '%s\n' "$II_OS_AGENT_HOST_ID" > /etc/ii-os/agent-host-id; chmod 0644 /etc/ii-os/agent-host-id
