# syntax=docker/dockerfile:1

# Ollama 0.32.15, linux/amd64 image manifest.
FROM ollama/ollama@sha256:57d60e686821ea81a7748a3ec8141308c8b8f95b27105713954abf7a6529e700

ARG TARGETARCH
ARG OPENCODE_VERSION=1.18.21
ARG OPENCODE_SHA256=d910c3ed7613bb5791a328904615d41cc25b7d3a6b470e3199ab0426a995b38a

LABEL org.opencontainers.image.title="qwen-coder" \
      org.opencontainers.image.description="Local Qwen3.8 coding agent: Ollama and OpenCode in a network-isolated sandbox" \
      ollama.version="0.32.15" \
      opencode.version="${OPENCODE_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive \
    OLLAMA_HOST=127.0.0.1:11434 \
    OLLAMA_MODELS=/models/ollama \
    OLLAMA_CONTEXT_LENGTH=64000 \
    OLLAMA_FLASH_ATTENTION=true \
    OLLAMA_KV_CACHE_TYPE=q8_0 \
    OLLAMA_GPU_OVERHEAD=2147483648 \
    OLLAMA_MAX_LOADED_MODELS=1 \
    OLLAMA_NUM_PARALLEL=1 \
    OLLAMA_NO_CLOUD=true \
    OLLAMA_NOHISTORY=true \
    OLLAMA_KEEP_ALIVE=30m \
    OPENCODE_DISABLE_AUTOUPDATE=true \
    OPENCODE_CONFIG=/etc/qwen-coder/opencode.json

RUN test "${TARGETARCH}" = amd64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      bubblewrap \
      build-essential \
      ca-certificates \
      curl \
      git \
      gnupg \
      iproute2 \
      jq \
      nodejs \
      npm \
      python3 \
      python3-pip \
      python3-venv \
      ripgrep \
      tini \
      util-linux \
    && rm -rf /var/lib/apt/lists/*

RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/* \
    && bwrap --version \
    && gh --version \
    && node --version \
    && npm --version

RUN curl --fail --location --silent --show-error \
      --output /tmp/opencode.tar.gz \
      "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
    && printf '%s  %s\n' "${OPENCODE_SHA256}" /tmp/opencode.tar.gz | sha256sum --check --strict - \
    && tar -xzf /tmp/opencode.tar.gz -C /usr/local/bin opencode \
    && rm /tmp/opencode.tar.gz \
    && test "$(opencode --version)" = "${OPENCODE_VERSION}"

RUN groupadd --gid 10001 sandbox \
    && useradd --uid 10001 --gid 10001 --create-home --shell /bin/bash sandbox \
    && install -d -o sandbox -g sandbox -m 0700 \
      /home/sandbox/.config/opencode \
      /home/sandbox/.local/share/opencode \
    && install -d -m 0755 /etc/qwen-coder /workspace /models

COPY opencode.json models.json /etc/qwen-coder/
COPY prepare-model.sh /usr/local/bin/qwen-coder-prepare-model
COPY run-agent.sh /usr/local/bin/qwen-coder-run-agent

RUN chmod 0644 /etc/qwen-coder/opencode.json /etc/qwen-coder/models.json \
    && chmod 0755 \
      /usr/local/bin/qwen-coder-prepare-model \
      /usr/local/bin/qwen-coder-run-agent

WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/qwen-coder-run-agent"]
