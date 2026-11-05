#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
pins_tool="$repo_root/tool/ffmpeg_engine_pins.sh"
example="$repo_root/tool/ffmpeg-engine-pins.example"
owner="ii-os-ffmpeg-engine-pins-test-$$-$RANDOM"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/$owner.XXXXXX")"
printf '%s\n' "$owner" >"$fixture/.ii-disposable-owner"

cleanup() {
  if [[ -d "$fixture" ]]; then
    [[ -f "$fixture/.ii-disposable-owner" ]]
    [[ "$(<"$fixture/.ii-disposable-owner")" == "$owner" ]]
    find "$fixture" -xdev -depth -delete
  fi
}
trap cleanup EXIT

revision=1234567890abcdef1234567890abcdef12345678
aar_sha=abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789
source_root="$fixture/source"
mkdir -p "$source_root/tool"
git -C "$source_root" init -q --initial-branch=main
git -C "$source_root" config user.name 'ii-os engine pins test'
git -C "$source_root" config user.email 'ii-os-engine-pins@example.invalid'

commit_pins() {
  printf '%s\n' "$@" >"$source_root/tool/ffmpeg-engine-pins"
  git -C "$source_root" add tool/ffmpeg-engine-pins
  git -C "$source_root" commit -qm "pins $RANDOM"
}

read_pin() {
  bash -c 'source "$1"; ii_os_engine_pin "$2" "$3"' _ \
    "$pins_tool" "$source_root" "$1"
}

expect_refusal() {
  local reason="$1"
  local key="$2"
  if read_pin "$key" >/dev/null 2>"$fixture/refusal.stderr"; then
    echo "engine pins accepted a case that must refuse: $reason" >&2
    exit 1
  fi
  grep -Fq "$reason" "$fixture/refusal.stderr" || {
    echo "engine pins refused for the wrong reason (wanted: $reason)" >&2
    cat "$fixture/refusal.stderr" >&2
    exit 1
  }
}

# No pins file means no reviewed engine: refuse rather than guess.
expect_refusal 'tool/ffmpeg-engine-pins is missing' engine_source_revision

# A pins file that exists only in the runner's workspace was never reviewed.
printf 'engine_source_revision=%s\nandroid_aar_sha256=%s\n' \
  "$revision" "$aar_sha" >"$source_root/tool/ffmpeg-engine-pins"
expect_refusal 'tool/ffmpeg-engine-pins must be committed' engine_source_revision
rm "$source_root/tool/ffmpeg-engine-pins"

# The shipped example holds placeholders and is refused as-is.
cp "$example" "$source_root/tool/ffmpeg-engine-pins"
git -C "$source_root" add tool/ffmpeg-engine-pins
git -C "$source_root" commit -qm example
expect_refusal 'engine_source_revision in tool/ffmpeg-engine-pins is not a reviewed value' \
  engine_source_revision
expect_refusal 'android_aar_sha256 in tool/ffmpeg-engine-pins is not a reviewed value' \
  android_aar_sha256

# All-zero values are placeholders too.
commit_pins \
  "engine_source_revision=0000000000000000000000000000000000000000" \
  "android_aar_sha256=$aar_sha"
expect_refusal 'engine_source_revision in tool/ffmpeg-engine-pins is not a reviewed value' \
  engine_source_revision

# Reviewed values are returned exactly.
commit_pins \
  '# reviewed engine build' \
  "engine_source_revision=$revision" \
  "android_aar_sha256=$aar_sha"
test "$(read_pin engine_source_revision)" = "$revision"
test "$(read_pin android_aar_sha256)" = "$aar_sha"
expect_refusal 'unknown engine pin: ios_archive_sha256' ios_archive_sha256

# A local edit after review does not count.
printf 'android_aar_sha256=%s\n' "${aar_sha//a/b}" \
  >>"$source_root/tool/ffmpeg-engine-pins"
expect_refusal 'tool/ffmpeg-engine-pins differs from the reviewed commit' \
  android_aar_sha256
git -C "$source_root" checkout -q -- tool/ffmpeg-engine-pins

# A key set twice is ambiguous.
commit_pins \
  "engine_source_revision=$revision" \
  "android_aar_sha256=$aar_sha" \
  "android_aar_sha256=$aar_sha"
expect_refusal 'tool/ffmpeg-engine-pins must set android_aar_sha256 exactly once' \
  android_aar_sha256

# A link could point the reader at unreviewed bytes.
git -C "$source_root" rm -q tool/ffmpeg-engine-pins
mkdir -p "$source_root/tool"
printf 'engine_source_revision=%s\nandroid_aar_sha256=%s\n' \
  "$revision" "$aar_sha" >"$source_root/tool/reviewed-pins"
ln -s reviewed-pins "$source_root/tool/ffmpeg-engine-pins"
git -C "$source_root" add tool/reviewed-pins tool/ffmpeg-engine-pins
git -C "$source_root" commit -qm link
expect_refusal 'tool/ffmpeg-engine-pins must be a regular file' \
  engine_source_revision

printf 'ffmpeg engine pins test: ok\n'
