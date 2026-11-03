#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$repo_root/example/web/ffmpeg"
target_marker="$target/.ii-disposable-owner"
target_owner="ii-ffmpeg-universal-web-test-assets-v1"
attestation="${II_FFMPEG_WEB_ENGINE_ATTESTATION:-}"

if [[ -z "$attestation" || "$attestation" != /* || ! -f "$attestation" || -L "$attestation" ]]; then
  echo "II_FFMPEG_WEB_ENGINE_ATTESTATION must name an absolute regular release attestation" >&2
  exit 1
fi
engine_dir="$(cd "$(dirname "$attestation")" && pwd)"
test "$(jq -r .schema "$attestation")" = 1
test "$(jq -r .engine_version "$attestation")" = n5.1.10
ledger="$engine_dir/source-ledger.json"
notices="$engine_dir/THIRD_PARTY_NOTICES.txt"
verification="$engine_dir/verification.json"
test -f "$ledger" && test ! -L "$ledger"
test -f "$notices" && test ! -L "$notices"
test -f "$verification" && test ! -L "$verification"

digest() {
  shasum -a 256 "$1" | awk '{print $1}'
}
test "$(digest "$ledger")" = "$(jq -r .source_ledger_sha256 "$attestation")"
test "$(digest "$notices")" = "$(jq -r .notices_sha256 "$attestation")"
test "$(digest "$verification")" = "$(jq -r .verification_sha256 "$attestation")"
python3 "$repo_root/tool/verify_web_engine.py" \
  --artifacts "$engine_dir" --ledger "$ledger" >/dev/null

expected=(ffmpeg-core.js ffmpeg-core.wasm ffmpeg.js)
names="$(jq -r '.artifacts[].path' "$attestation" | sort | tr '\n' ' ' | sed 's/ $//')"
[[ "$names" == "${expected[*]}" ]]

mkdir -p "$target"
if [[ -f "$target_marker" ]] && [[ "$(<"$target_marker")" != "$target_owner" ]]; then
  echo "Refusing to manage unowned web test assets at $target" >&2
  exit 1
fi
if [[ ! -e "$target_marker" ]]; then
  printf '%s' "$target_owner" > "$target_marker"
fi
for name in "${expected[@]}"; do
  source_path="$engine_dir/$name"
  expected_sha="$(jq -r --arg name "$name" '.artifacts[] | select(.path == $name) | .sha256' "$attestation")"
  test -f "$source_path" && test ! -L "$source_path"
  test "$(digest "$source_path")" = "$expected_sha"
  cp "$source_path" "$target/$name"
done

jq -n \
  --arg core_js "$(jq -r '.artifacts[] | select(.path == "ffmpeg-core.js") | .sha256' "$attestation")" \
  --arg core_wasm "$(jq -r '.artifacts[] | select(.path == "ffmpeg-core.wasm") | .sha256' "$attestation")" \
  '{core_js_sha256:$core_js,core_wasm_sha256:$core_wasm}'
