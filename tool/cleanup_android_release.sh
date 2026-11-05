#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
state_root="${II_OS_ANDROID_RELEASE_STATE:-}"
if [[ -z "$state_root" ]]; then
  exit 0
fi
expected_root="${RUNNER_TEMP:?}/ii-os-android-release-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
expected="ii-os-android-release:${GITHUB_RUN_ID:?}:${GITHUB_RUN_ATTEMPT:?}"
owner_file="$state_root/.ii-disposable-owner"
if [[ "$state_root" != "$expected_root" || -L "$state_root" ||
      -L "$owner_file" || ! -f "$owner_file" || "$(cat "$owner_file")" != "$expected" ]]; then
  echo "Refusing to remove Android release state without matching ownership" >&2
  exit 1
fi
if [[ -L "$repo_root/android" || -L "$repo_root/android/app" ]]; then
  echo 'Refusing to remove Android configuration without matching ownership' >&2
  exit 1
fi
paths=("$repo_root/android/key.properties" "$repo_root/android/app/google-services.json")
# Validate every output before deleting any output. A replaced file belongs
# to its new owner and must be preserved together with the remaining state.
for path in "${paths[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    if [[ ! -L "$path" || "$(readlink "$path")" != "$state_root/${path##*/}" ]]; then
      echo 'Refusing to remove Android configuration without matching ownership' >&2
      exit 1
    fi
  fi
done
for path in "${paths[@]}"; do
  [[ ! -L "$path" ]] || rm -- "$path"
done
rm -rf -- "$state_root"
