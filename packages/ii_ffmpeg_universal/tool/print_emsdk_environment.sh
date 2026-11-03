#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 || ! -f "$1" ]]; then
  printf 'usage: %s /absolute/path/to/emsdk_env.sh\n' "$0" >&2
  exit 64
fi

# emsdk distributes environment activation as a shell fragment. This fixed,
# argument-only helper is the narrow boundary that sources it; callers never
# construct or execute a shell command string.
source "$1" >/dev/null
env -0
