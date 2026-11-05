#!/usr/bin/env bash
set -euo pipefail

state_root="${II_OS_CLIENT_PROCESSING_STATE:-}"
runner_temp="${RUNNER_TEMP:?}"
owner="ii-os-client-processing:${GITHUB_RUN_ID:?}:${GITHUB_RUN_ATTEMPT:?}"

if [[ -n "$state_root" ]]; then
  [[ "$state_root" == "$runner_temp"/* && -d "$state_root" && ! -L "$state_root" ]]
  marker="$state_root/.ii-disposable-owner"
  [[ -f "$marker" && ! -L "$marker" && "$(<"$marker")" == "$owner" ]]
  rm -rf -- "$state_root"
  printf '%s\n' 'GIT_CONFIG_GLOBAL=/dev/null' >>"${GITHUB_ENV:?}"
fi
