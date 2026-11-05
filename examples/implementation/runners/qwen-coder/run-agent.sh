#!/usr/bin/env bash
# Run one coding task with OpenCode against the local Qwen model.
#
# usage: qwen-coder-run-agent WORKSPACE PROMPT_FILE JSONL_PATH PROOF_DIR
#
# Start it as root. It re-enters itself as UID 10001 inside a Bubblewrap user,
# PID, mount, and network namespace with only loopback up, so Ollama and
# OpenCode can reach each other and nothing else. The workspace and PROOF_DIR
# are the only writable paths; every Git metadata directory is read-only, so
# only a trusted step after this one can publish a change.
#
# Environment:
#   QWEN_CODER_VRAM_LIMIT_MB  required; the accelerator memory reserved for
#                             this run (the permission profile's vram_mb).
#   GITHUB_TOKEN_FILE,        optional; credential files the trusted caller
#   AGENT_USAGE_KEY_FILE      keeps. The run fails if the agent can read them.
set -euo pipefail

[[ "$#" -eq 4 ]] || {
  echo 'usage: qwen-coder-run-agent WORKSPACE PROMPT_FILE JSONL_PATH PROOF_DIR' >&2
  exit 2
}

readonly workspace="$1"
readonly prompt_file="$2"
readonly jsonl_path="$3"
readonly proof_dir="$4"
readonly config='/etc/qwen-coder/opencode.json'
readonly expected='/etc/qwen-coder/models.json'
readonly manifest='/models/model-manifest.json'

die() {
  printf 'qwen-coder run: %s\n' "$*" >&2
  exit 1
}

vram_limit_mb="${QWEN_CODER_VRAM_LIMIT_MB:-}"
[[ "$vram_limit_mb" =~ ^[1-9][0-9]{0,6}$ ]] ||
  die 'QWEN_CODER_VRAM_LIMIT_MB must name the reserved accelerator memory in MiB'

if [[ "${QWEN_CODER_SANDBOXED:-0}" == 1 ]]; then
  [[ "$(id -u)" -eq 10001 ]] || die 'sandboxed runtime must run as UID 10001'
else
  [[ "$(id -u)" -eq 0 ]] || die 'runtime supervisor must run as root'
fi
[[ -d "$workspace" && ! -L "$workspace" ]] || die 'workspace is missing or unsafe'
[[ "$(stat -c '%u' "$workspace")" -eq 10001 ]] || die 'workspace is not owned by UID 10001'
[[ -f "$prompt_file" && ! -L "$prompt_file" && -r "$prompt_file" ]] || die 'prompt file is unsafe'
[[ -f "$config" && ! -L "$config" ]] || die 'OpenCode config is unsafe'
[[ -f "$manifest" && ! -L "$manifest" ]] ||
  die 'model manifest is missing; run qwen-coder-prepare-model once (see README.md)'
model="$(jq -er '.model' "$expected")"
context_length="$(jq -er '.context_length' "$expected")"
jq -e --slurpfile expected "$expected" '
  .schema_version == 1
  and .model == $expected[0].model
  and .context_length == $expected[0].context_length
  and .source.sha256 == $expected[0].files[0].sha256
' "$manifest" >/dev/null || die 'model manifest does not match models.json'

install -d -m 0700 "$proof_dir"

if [[ "${QWEN_CODER_SANDBOXED:-0}" != 1 ]]; then
  command -v bwrap >/dev/null || die 'Bubblewrap is required'
  command -v ip >/dev/null || die 'iproute2 is required'
  command -v runuser >/dev/null || die 'runuser is required'
  sandbox_home="$(mktemp -d "$proof_dir/.sandbox-home.XXXXXX")"
  sandbox_prompt="$(mktemp "$proof_dir/.prompt.XXXXXX")"
  cp -- "$prompt_file" "$sandbox_prompt"
  chown -R 10001:10001 "$proof_dir"
  chmod 0400 "$sandbox_prompt"
  [[ -d "$workspace/.git" && ! -L "$workspace/.git" ]] \
    || die 'workspace Git metadata is missing or unsafe'
  sandbox=(
    bwrap --die-with-parent --new-session
    --unshare-all
    --uid 10001
    --gid 10001
    --cap-add CAP_NET_ADMIN
    --ro-bind / /
    --dev-bind /dev /dev
    --proc /proc
    --tmpfs /tmp
    --bind "$workspace" "$workspace"
    --ro-bind "$workspace/.git" "$workspace/.git"
    --bind "$proof_dir" "$proof_dir"
    --bind "$sandbox_home" /home/sandbox
  )
  while IFS= read -r -d '' nested_git; do
    [[ ! -L "$nested_git" ]] || die 'nested Git metadata is unsafe'
    sandbox+=(--ro-bind "$nested_git" "$nested_git")
  done < <(
    find "$workspace" -mindepth 1 \( -path "$workspace/.git" -prune \) \
      -o \( -name .git -prune -print0 \)
  )
  set +e
  runuser --user sandbox -- env \
    HOME=/home/sandbox \
    QWEN_CODER_SANDBOXED=1 \
    QWEN_CODER_VRAM_LIMIT_MB="$vram_limit_mb" \
    GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-}" \
    AGENT_USAGE_KEY_FILE="${AGENT_USAGE_KEY_FILE:-}" \
    "${sandbox[@]}" \
      /bin/bash -c 'ip link set lo up; exec "$@"' _ \
      /usr/local/bin/qwen-coder-run-agent \
      "$workspace" "$sandbox_prompt" "$jsonl_path" "$proof_dir"
  sandbox_status=$?
  set -e
  rm -rf -- "$sandbox_home"
  rm -f -- "$sandbox_prompt"
  unset sandbox
  exit "$sandbox_status"
fi

if [[ -n "${GITHUB_TOKEN_FILE:-}" ]]; then
  [[ ! -r "$GITHUB_TOKEN_FILE" ]] || die 'GitHub credential is readable by the agent user'
fi
if [[ -n "${AGENT_USAGE_KEY_FILE:-}" ]]; then
  [[ ! -r "$AGENT_USAGE_KEY_FILE" ]] || die 'usage credential is readable by the agent user'
fi
unset GITHUB_TOKEN_FILE AGENT_USAGE_KEY_FILE CODEX_AUTH_JSON_FILE CODEX_AUTH_JSON

[[ ! -e "$jsonl_path" ]] || die 'JSONL destination already exists'
readonly ollama_log="$proof_dir/ollama.log"
readonly warm_response="$proof_dir/warm-response.json"
readonly ps_json="$proof_dir/ollama-ps.json"
readonly gpu_csv="$proof_dir/nvidia-smi.csv"
readonly usage_jsonl="$proof_dir/opencode-usage.jsonl"

# shellcheck disable=SC2329 # Invoked by the EXIT/INT/TERM trap below.
cleanup() {
  if [[ -n "${ollama_pid:-}" ]]; then
    kill "$ollama_pid" 2>/dev/null || true
    wait "$ollama_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

ollama serve >"$ollama_log" 2>&1 &
ollama_pid=$!
for _ in $(seq 1 120); do
  curl -fsS http://127.0.0.1:11434/api/version | jq -e '.version == "0.32.15"' >/dev/null && break
  kill -0 "$ollama_pid" 2>/dev/null || die 'Ollama exited during startup'
  sleep 1
done
curl -fsS http://127.0.0.1:11434/api/version | jq -e '.version == "0.32.15"' >/dev/null ||
  die 'Ollama did not become ready'
if curl -fsS --connect-timeout 2 --max-time 5 https://example.com >/dev/null 2>&1; then
  die 'external network is reachable from the sandbox'
fi

jq -cn \
  --arg model "$model" \
  --argjson context_length "$context_length" \
  '{model:$model,prompt:"Reply with ready.",stream:false,think:"medium",keep_alive:"30m",options:{num_ctx:$context_length,num_predict:8,temperature:1.0,top_p:0.95,top_k:20,repeat_penalty:1.0}}' |
  curl -fsS --max-time 900 -H 'Content-Type: application/json' \
    --data-binary @- http://127.0.0.1:11434/api/generate >"$warm_response"
jq -e '.done == true and .model != null' "$warm_response" >/dev/null ||
  die 'Ollama warmup did not complete'
curl -fsS http://127.0.0.1:11434/api/ps >"$ps_json"
jq -e --arg model "$model" --argjson context_length "$context_length" '
  (.models | length) == 1
  and (.models[0].name | startswith($model + ":"))
  and .models[0].context_length == $context_length
  and .models[0].size > 0
  and .models[0].size_vram >= .models[0].size
' "$ps_json" >/dev/null || die 'model is not fully resident on the GPU at its full context'
nvidia-smi \
  --query-gpu=uuid,name,driver_version,memory.total,memory.used,utilization.gpu,temperature.gpu \
  --format=csv,noheader,nounits >"$gpu_csv"
[[ "$(wc -l <"$gpu_csv" | tr -d ' ')" -eq 1 ]] || die 'expected exactly one NVIDIA GPU'
gpu_used_mb="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | tr -d ' ')"
[[ "$gpu_used_mb" =~ ^[0-9]+$ && "$gpu_used_mb" -le "$vram_limit_mb" ]] ||
  die 'loaded runtime exceeds its VRAM reservation'

set +e
# shellcheck disable=SC2016 # The inner shell receives its arguments as $1-$3.
env \
  HOME=/home/sandbox \
  XDG_CONFIG_HOME=/home/sandbox/.config \
  XDG_DATA_HOME=/home/sandbox/.local/share \
  OPENCODE_CONFIG="$config" \
  OPENCODE_DISABLE_AUTOUPDATE=true \
  /bin/bash -c '
    set -euo pipefail
    cd "$1"
    exec opencode run --auto --format json \
      --model "ollama/$3" "$(cat "$2")"
  ' _ "$workspace" "$prompt_file" "$model" >"$jsonl_path" 2>"$proof_dir/opencode.stderr"
opencode_status=$?
set -e

jq -c 'select(.type == "step_finish")' "$jsonl_path" >"$usage_jsonl"
jq -s -e 'length > 0' "$usage_jsonl" >/dev/null || die 'OpenCode emitted no usage-bearing step events'
jq -n \
  --argjson exit_status "$opencode_status" \
  --arg model "$model" \
  --argjson context_length "$context_length" \
  --arg ollama_version "$(ollama --version 2>&1 | awk '{print $NF}')" \
  --arg opencode_version "$(opencode --version)" \
  --argjson gpu_used_mb "$gpu_used_mb" \
  --argjson vram_limit_mb "$vram_limit_mb" \
  --slurpfile ps "$ps_json" \
  --slurpfile usage "$usage_jsonl" \
  '{schema_version:1,model:$model,context_length:$context_length,fully_gpu_resident:true,network_isolated:true,gpu_used_mb:$gpu_used_mb,vram_limit_mb:$vram_limit_mb,ollama_version:$ollama_version,opencode_version:$opencode_version,opencode_exit_status:$exit_status,ollama_ps:$ps[0],usage_steps:($usage|length)}' \
  >"$proof_dir/runtime-proof.json"
printf '{"opencode_exit_status":%s,"usage_steps":%s,"context_length":%s,"fully_gpu_resident":true,"network_isolated":true}\n' \
  "$opencode_status" "$(wc -l <"$usage_jsonl" | tr -d ' ')" "$context_length"
exit "$opencode_status"
