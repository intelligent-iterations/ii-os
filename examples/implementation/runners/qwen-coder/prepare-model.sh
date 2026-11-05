#!/usr/bin/env bash
# One-time model preparation. Run it as root in this image with the model
# folder mounted read-write at /models and no network (`--network none`).
#
# It never downloads anything. It verifies the weight file you placed under
# /models/sources against models.json, imports it into an Ollama store at
# /models/ollama, and writes /models/model-manifest.json. Agent runs then mount
# the same folder read-only.
set -euo pipefail

readonly models=/models
readonly expected=/etc/qwen-coder/models.json
readonly store="$models/ollama"
readonly store_marker="$store/.qwen-coder-store"
readonly manifest="$models/model-manifest.json"

die() {
  printf 'qwen-coder model preparation: %s\n' "$*" >&2
  exit 1
}

[[ "$(id -u)" -eq 0 ]] || die 'preparation must run as root in the runner image'
[[ -d "$models" && ! -L "$models" ]] || die '/models is missing or unsafe'
[[ -f "$expected" && ! -L "$expected" ]] || die 'models.json is missing'
[[ "$(jq '.files | length' "$expected")" -eq 1 ]] ||
  die 'models.json must list exactly one weight file'

model="$(jq -er '.model' "$expected")"
context_length="$(jq -er '.context_length' "$expected")"
relative="$(jq -er '.files[0].path' "$expected")"
expected_size="$(jq -er '.files[0].size_bytes' "$expected")"
expected_sha="$(jq -er '.files[0].sha256' "$expected")"
[[ "$relative" =~ ^sources/[A-Za-z0-9._-]+$ ]] || die 'weight path is unsafe'
[[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die 'expected digest is invalid'
readonly source_file="$models/$relative"

[[ -f "$source_file" && ! -L "$source_file" ]] ||
  die "place the weight file at \$II_OS_MODEL_ROOT/qwen-coder/$relative first (see README.md)"
[[ "$(stat -c '%s' "$source_file")" == "$expected_size" ]] ||
  die 'weight file size does not match models.json'
[[ "$(sha256sum "$source_file" | awk '{print $1}')" == "$expected_sha" ]] ||
  die 'weight file digest does not match models.json'

# Refuse to write into a store this script did not create.
if [[ -e "$store" ]]; then
  [[ -d "$store" && ! -L "$store" ]] || die 'Ollama store path is unsafe'
  if [[ ! -f "$store_marker" ]]; then
    [[ -z "$(find "$store" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
      die 'refusing to modify an Ollama store this script did not create'
  fi
fi
install -d -m 0755 "$store"
touch "$store_marker"
export OLLAMA_MODELS="$store"

ollama_log="$(mktemp)"
modelfile="$(mktemp)"
cleanup() {
  if [[ -n "${ollama_pid:-}" ]]; then
    kill "$ollama_pid" 2>/dev/null || true
    wait "$ollama_pid" 2>/dev/null || true
  fi
  rm -f -- "$ollama_log" "$modelfile"
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

cat >"$modelfile" <<MODELFILE
FROM $source_file
PARAMETER num_ctx $context_length
PARAMETER num_predict 16384
PARAMETER temperature 1.0
PARAMETER top_p 0.95
PARAMETER top_k 20
PARAMETER repeat_penalty 1.0
MODELFILE
ollama create "$model" --file "$modelfile"
ollama show "$model" >/dev/null
[[ -f "$store/blobs/sha256-$expected_sha" ]] ||
  die 'Ollama store does not contain the verified weight file'

manifest_tmp="$manifest.tmp-$$"
jq -c \
  '{schema_version: 1, model: .model, context_length: .context_length,
    source: (.files[0] | {path, sha256, size_bytes, revision: .source.revision})}' \
  "$expected" >"$manifest_tmp"
chmod 0644 "$manifest_tmp"
mv "$manifest_tmp" "$manifest"
printf '{"prepared":true,"model":"%s","context_length":%s,"source_sha256":"%s"}\n' \
  "$model" "$context_length" "$expected_sha"
