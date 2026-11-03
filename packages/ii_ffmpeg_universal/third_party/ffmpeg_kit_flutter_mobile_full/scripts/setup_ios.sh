#!/bin/bash
set -euo pipefail

VERSION="8.1.2-full"
DEFAULT_BASE="https://github.com/sk3llo/ffmpeg_kit_flutter/releases/download/${VERSION}"
BASE_URL="${FFMPEG_KIT_IOS_BASE_URL:-$DEFAULT_BASE}"
FRAMEWORKS="ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale"
LOCAL_ARCHIVE_DIR="${II_FFMPEG_IOS_ARCHIVE_DIR:-}"
LOCAL_ATTESTATION="${II_FFMPEG_IOS_ATTESTATION:-}"
RELEASE_REQUIRED="${II_FFMPEG_REQUIRE_RELEASE_ENGINE:-false}"
DEBUG_FALLBACK_ALLOWED="${II_FFMPEG_ALLOW_DEBUG_FALLBACK:-false}"

if { [ -z "$LOCAL_ARCHIVE_DIR" ] || [ -z "$LOCAL_ATTESTATION" ]; } &&
    [ "$DEBUG_FALLBACK_ALLOWED" != true ]; then
  echo "A source-attested local iOS FFmpeg engine is required. Set II_FFMPEG_ALLOW_DEBUG_FALLBACK=true only for non-release development." >&2
  exit 1
fi
if [ "$RELEASE_REQUIRED" = true ] && [ "$DEBUG_FALLBACK_ALLOWED" = true ]; then
  echo "Release-engine enforcement cannot be combined with the debug fallback." >&2
  exit 1
fi
if [ -n "$LOCAL_ARCHIVE_DIR" ]; then
  case "$LOCAL_ARCHIVE_DIR" in /*) ;; *) echo "iOS archive directory must be absolute." >&2; exit 1 ;; esac
  [ -d "$LOCAL_ARCHIVE_DIR" ] && [ ! -L "$LOCAL_ARCHIVE_DIR" ] || exit 1
  [ -f "$LOCAL_ATTESTATION" ] && [ ! -L "$LOCAL_ATTESTATION" ] || exit 1
fi

checksum_for() {
  case "$1" in
    ffmpegkit) echo "49e64651d054226c89dd4c1db7ebf539f8f89f914ea16eb2c1455f7da0111894" ;;
    libavcodec) echo "cc51cc4faec995ae7da69c254506b15948190132717e5f95844080153bf5797b" ;;
    libavdevice) echo "40dfb7d807a018869bc996dc8c0cfdac6607f699764ffca2c6345262d4a71ca3" ;;
    libavfilter) echo "a8cd456274a0b163cef9beb5f44e4b1f3c6965df8dbf3d69d278821cd2612526" ;;
    libavformat) echo "54a82bfd57ca56e42b45c6161b214f6f8cb03cd592e522d3f0b837263356922a" ;;
    libavutil) echo "c0fe643e627c4376ec828d4e1f36e94a7d76e7a86d2d661346199fab297495e7" ;;
    libswresample) echo "6994edad7fbe472e265836ac4b33ef739f613a40d4e26505725e5d7d34087854" ;;
    libswscale) echo "ac9f4efc200e8af1f1f5ab7341bb175302fc1bdb6da7617f272ce126e140353d" ;;
    *) return 1 ;;
  esac
}

release_checksum_for() {
  python3 - "$LOCAL_ATTESTATION" "$1" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "rb") as source:
    raw = source.read(64 * 1024 + 1)
if len(raw) > 64 * 1024:
    raise SystemExit("iOS engine attestation exceeds limit")
value = json.loads(raw)
if value.get("schema") != 1 or value.get("platform") != "ios":
    raise SystemExit("invalid iOS engine attestation")
name = f"{sys.argv[2]}.xcframework.zip"
matches = [item for item in value.get("artifacts", []) if item.get("path") == name]
if len(matches) != 1 or not re.fullmatch(r"[0-9a-f]{64}", matches[0].get("sha256", "")):
    raise SystemExit(f"missing iOS engine checksum for {name}")
print(matches[0]["sha256"])
PY
}

work="$(mktemp -d "${TMPDIR:-/tmp}/ii-ffmpeg-ios.XXXXXX")"
token="ii-ffmpeg-ios-$$-$RANDOM"
marker="$work/.ii-disposable-owner"
printf '%s' "$token" > "$marker"
staging=""

cleanup() {
  if [ -f "$marker" ] && [ "$(cat "$marker")" = "$token" ]; then
    find "$work" -depth -delete
  fi
  if [ -n "$staging" ] &&
      [ -f "$staging/.ii-disposable-owner" ] &&
      [ "$(cat "$staging/.ii-disposable-owner")" = "$token" ]; then
    find "$staging" -depth -delete
  fi
}
trap cleanup EXIT

curl_args=(-fL --retry 3 --retry-delay 2 --connect-timeout 30)
if curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then
  curl_args+=(--retry-all-errors)
fi

download_verified() {
  local framework="$1"
  local archive="$work/${framework}.xcframework.zip"
  local extracted="$work/extracted-${framework}"
  local expected
  if [ -n "$LOCAL_ARCHIVE_DIR" ]; then
    local source_archive="$LOCAL_ARCHIVE_DIR/${framework}.xcframework.zip"
    [ -f "$source_archive" ] && [ ! -L "$source_archive" ] || {
      echo "Local iOS engine archive is missing: ${framework}" >&2
      exit 1
    }
    cp "$source_archive" "$archive"
    expected="$(release_checksum_for "$framework")"
  else
    curl "${curl_args[@]}" -o "$archive" \
      "$BASE_URL/${framework}.xcframework.zip"
    expected="$(checksum_for "$framework")"
  fi
  local actual
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "Checksum mismatch for ${framework}: ${actual}" >&2
    exit 1
  fi
  mkdir "$extracted"
  unzip -q "$archive" -d "$extracted"
  local candidate
  candidate="$(find "$extracted" -type d -name "${framework}.xcframework" -print -quit)"
  if [ -z "$candidate" ]; then
    echo "Verified archive does not contain ${framework}.xcframework." >&2
    exit 1
  fi
  printf '%s\n' "$candidate"
}

all_installed=true
for framework in $FRAMEWORKS; do
  [ -d "Frameworks/${framework}.xcframework" ] || all_installed=false
done
if $all_installed; then
  for framework in $FRAMEWORKS; do
    candidate="$(download_verified "$framework")"
    if ! diff -qr "$candidate" "Frameworks/${framework}.xcframework" >/dev/null; then
      echo "Cached ${framework}.xcframework differs from its verified archive." >&2
      exit 1
    fi
  done
  exit 0
fi
if [ -e Frameworks ]; then
  echo "Refusing to replace an incomplete or unrecognized Frameworks directory." >&2
  exit 1
fi

staging="Frameworks.ii-${token}.partial"
mkdir "$staging"
printf '%s' "$token" > "$staging/.ii-disposable-owner"

for framework in $FRAMEWORKS; do
  candidate="$(download_verified "$framework")"
  cp -R "$candidate" "$staging/${framework}.xcframework"
done

mv "$staging" Frameworks
staging=""
trap - EXIT
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$token" ]; then
  find "$work" -depth -delete
fi
