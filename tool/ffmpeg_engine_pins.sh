#!/usr/bin/env bash

# Reads the reviewed FFmpeg engine pins that release builds consume.
#
# tool/ffmpeg-engine-pins is written by the repository operator after building
# their own engines (see docs/mobile-release.md); start from
# tool/ffmpeg-engine-pins.example. A pin is accepted only from that committed,
# unmodified, regular file, so a runner workspace or a repository variable
# cannot substitute an unreviewed engine.

ii_os_engine_pins_fail() {
  printf 'FFmpeg engine pins refused: %s\n' "$1" >&2
  return 1
}

# Usage: ii_os_engine_pin <repository root> <engine_source_revision|android_aar_sha256>
ii_os_engine_pin() {
  local repo_root="$1"
  local key="$2"
  local relative=tool/ffmpeg-engine-pins
  local path="$repo_root/$relative"
  local pattern
  local placeholder
  local lines
  local value

  case "$key" in
    engine_source_revision)
      pattern='^[0-9a-f]{40}$'
      placeholder=0000000000000000000000000000000000000000
      ;;
    android_aar_sha256)
      pattern='^[0-9a-f]{64}$'
      placeholder=0000000000000000000000000000000000000000000000000000000000000000
      ;;
    *)
      ii_os_engine_pins_fail "unknown engine pin: $key"
      return 1
      ;;
  esac
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    ii_os_engine_pins_fail \
      "$relative is missing; copy $relative.example and record your own engine build"
    return 1
  fi
  [[ -f "$path" && ! -L "$path" ]] || {
    ii_os_engine_pins_fail "$relative must be a regular file"
    return 1
  }
  git -C "$repo_root" ls-files --error-unmatch -- "$relative" >/dev/null 2>&1 || {
    ii_os_engine_pins_fail "$relative must be committed"
    return 1
  }
  git -C "$repo_root" diff --quiet HEAD -- "$relative" || {
    ii_os_engine_pins_fail "$relative differs from the reviewed commit"
    return 1
  }
  lines="$(grep -E "^${key}=" "$path" || true)"
  [[ -n "$lines" && "$lines" != *$'\n'* ]] || {
    ii_os_engine_pins_fail "$relative must set $key exactly once"
    return 1
  }
  value="${lines#*=}"
  [[ "$value" =~ $pattern && "$value" != "$placeholder" ]] || {
    ii_os_engine_pins_fail "$key in $relative is not a reviewed value"
    return 1
  }
  printf '%s\n' "$value"
}
