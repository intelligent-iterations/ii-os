#!/usr/bin/env bash
set -euo pipefail
umask 077

# Builds and attests the iOS FFmpeg engine from this repository's embedded
# package on every release, so no prebuilt iOS engine is ever trusted. Needs an
# Apple Silicon macOS runner with Xcode and Homebrew, the workflow identity
# settings (II_OS_WORKFLOW_REPOSITORY, II_OS_WORKFLOW_BRANCH), and a run-owned
# II_OS_CLIENT_PROCESSING_STATE directory under RUNNER_TEMP whose
# .ii-disposable-owner reads ii-os-client-processing:<run id>:<run attempt>.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$repo_root/tool/workflow_source_identity.sh"
universal="$repo_root/packages/ii_ffmpeg_universal"
runner_temp="${RUNNER_TEMP:?}"
state_root="${II_OS_CLIENT_PROCESSING_STATE:?}"
owner="ii-os-client-processing:${GITHUB_RUN_ID:?}:${GITHUB_RUN_ATTEMPT:?}"
scratch="$state_root/ios-release-engine"
marker="$scratch/.ii-disposable-owner"
tap_name=""
tap_root=""
tap_identity=""
tap_owner_file="$scratch/.ii-homebrew-tap-owner"
tap_owner_record=""

fail() {
  printf 'iOS release engine preparation failed: %s\n' "$1" >&2
  exit 1
}

[[ "$runner_temp" == /* && -d "$runner_temp" && ! -L "$runner_temp" ]] ||
  fail 'RUNNER_TEMP must be a real absolute directory'
[[ "$state_root" == "$runner_temp"/* && -d "$state_root" && ! -L "$state_root" ]] ||
  fail 'client-processing state is outside RUNNER_TEMP or unsafe'
[[ -f "$state_root/.ii-disposable-owner" && ! -L "$state_root/.ii-disposable-owner" ]] ||
  fail 'client-processing ownership marker is missing or unsafe'
[[ "$(<"$state_root/.ii-disposable-owner")" == "$owner" ]] ||
  fail 'client-processing state belongs to another run'
[[ ! -e "$scratch" && ! -L "$scratch" ]] ||
  fail 'release-engine state path is already occupied'
mkdir -m 0700 "$scratch"
printf '%s\n' "$owner" >"$marker"

cleanup_tap() {
  local actual_identity
  [[ -n "$tap_name" ]] || return 0
  if [[ ! -e "$tap_owner_file" ]]; then
    [[ -z "$tap_root" || ! -e "$tap_root" ]]
    return
  fi
  [[ -f "$tap_owner_file" && ! -L "$tap_owner_file" ]]
  [[ "$(<"$tap_owner_file")" == "$tap_owner_record" ]]
  if [[ -e "$tap_root" ]]; then
    [[ -d "$tap_root" && ! -L "$tap_root" ]]
    actual_identity="$(stat -f '%d:%i' "$tap_root")"
    [[ "$actual_identity" =~ ^[0-9]+:[0-9]+$ ]]
    if [[ -z "$tap_identity" ]]; then
      tap_identity="$actual_identity"
      tap_owner_record="$owner"$'\t'"$tap_root"$'\t'"$tap_identity"
      printf '%s\n' "$tap_owner_record" >"$tap_owner_file"
    fi
    [[ "$actual_identity" == "$tap_identity" ]]
    [[ "$(<"$tap_owner_file")" == "$tap_owner_record" ]]
    if brew tap | grep -Fx "$tap_name" >/dev/null; then
      [[ "$(brew --repository "$tap_name")" == "$tap_root" ]]
      brew untap --force "$tap_name"
    else
      find "$tap_root" -xdev -depth -delete
    fi
    [[ ! -e "$tap_root" ]]
  fi
  rm -- "$tap_owner_file"
}

on_exit() {
  local status="$?"
  trap - EXIT INT TERM
  set +e
  cleanup_tap
  local cleanup_status="$?"
  if ((status != 0)); then
    if [[ -d "$scratch" && ! -L "$scratch" &&
          -f "$marker" && ! -L "$marker" && "$(<"$marker")" == "$owner" ]]; then
      find "$scratch" -xdev -depth -delete
    fi
  fi
  set -e
  if ((status == 0 && cleanup_status != 0)); then status="$cleanup_status"; fi
  exit "$status"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] ||
  fail 'release engine requires an Apple Silicon macOS runner'
ii_os_verify_source_checkout "$repo_root"
[[ -d "$universal" && ! -L "$universal" ]]
[[ "$(git -C "$universal" rev-parse --show-toplevel)" == "$repo_root" ]]

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
base_path="$PATH"
attested_formula_bins=""
lock="$universal/tool/mobile_engine_lock.json"
core_repository="$(jq -r .toolchains.homebrew_core.repository "$lock")"
core_revision="$(jq -r .toolchains.homebrew_core.revision "$lock")"
[[ "$core_repository" == https://github.com/Homebrew/homebrew-core.git ]]
[[ "$core_revision" =~ ^[0-9a-f]{40}$ ]]
tap_name="ii-os/locked-release-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
[[ -z "$(brew tap | grep -Fx "$tap_name" || true)" ]]
brew_root="$(brew --repository)"
tap_root="$brew_root/Library/Taps/ii-os/homebrew-locked-release-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
case "$tap_root" in
  "$brew_root"/Library/Taps/ii-os/homebrew-locked-release-*) ;;
  *) fail 'resolved Homebrew tap path is outside the owned namespace' ;;
esac
[[ ! -e "$tap_root" ]]
tap_owner_record="$owner"$'\t'"$tap_root"
printf '%s\n' "$tap_owner_record" >"$tap_owner_file"
brew tap "$tap_name" "$core_repository"
[[ -d "$tap_root" && ! -L "$tap_root" ]]
tap_identity="$(stat -f '%d:%i' "$tap_root")"
[[ "$tap_identity" =~ ^[0-9]+:[0-9]+$ ]]
tap_owner_record="$owner"$'\t'"$tap_root"$'\t'"$tap_identity"
printf '%s\n' "$tap_owner_record" >"$tap_owner_file"
[[ "$(git -C "$tap_root" remote get-url origin)" == "$core_repository" ]]
git -C "$tap_root" fetch --quiet --depth 1 origin "$core_revision"
git -C "$tap_root" switch --quiet -C dev "$core_revision"
[[ "$(git -C "$tap_root" branch --show-current)" == dev ]]
[[ "$(git -C "$tap_root" rev-parse HEAD)" == "$core_revision" ]]
brew trust "$tap_name"

while IFS=$'\t' read -r formula formula_path; do
  formula_file="$tap_root/$formula_path"
  [[ -f "$formula_file" && ! -L "$formula_file" ]]
  qualified="$tap_name/$formula"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    brew reinstall --force-bottle --formula "$qualified"
  else
    brew install --force-bottle --formula "$qualified"
  fi
  prefix="$(brew --prefix "$formula")"
  [[ -d "$prefix/bin" ]]
  attested_formula_bins="$prefix/bin${attested_formula_bins:+:$attested_formula_bins}"
done < <(jq -r '.toolchains.apple_build_formulae[] | [.formula,.path] | @tsv' "$lock")
gnu_sed_prefix="$(brew --prefix gnu-sed)"
gnu_sed_bin="$gnu_sed_prefix/libexec/gnubin"
[[ -d "$gnu_sed_bin" && ! -L "$gnu_sed_bin" ]]
[[ -L "$gnu_sed_bin/sed" ]]
export PATH="$gnu_sed_bin:$attested_formula_bins:/usr/bin:$base_path"
[[ "$(command -v sed)" == "$gnu_sed_bin/sed" ]]
sed --version | grep -F 'GNU sed' >/dev/null
[[ "$(command -v xcode-select)" == /usr/bin/xcode-select ]]
[[ "$(command -v xcrun)" == /usr/bin/xcrun ]]

toolchain_attestation="$scratch/apple-build-tools.json"
python3 "$universal/tool/attest_apple_build_tools.py" \
  --lock "$lock" \
  --formula-root "$tap_root" \
  --output "$toolchain_attestation"
mobile_workspace="$scratch/mobile-engine-ios"
python3 "$universal/tool/build_mobile_engine.py" ios \
  --workspace "$mobile_workspace" \
  --apple-build-tool-attestation "$toolchain_attestation" \
  --apple-formula-root "$tap_root"
archive_dir="$mobile_workspace/artifacts"
attestation="$archive_dir/build-attestation.json"
[[ -f "$archive_dir/ffmpegkit.xcframework.zip" && ! -L "$archive_dir/ffmpegkit.xcframework.zip" ]]
[[ -f "$attestation" && ! -L "$attestation" ]]

desktop_workspace="$scratch/desktop-engine-macos"
python3 "$universal/tool/build_desktop_engine.py" \
  --workspace "$desktop_workspace"
desktop_assets="$desktop_workspace/assets"
desktop_attestation="$desktop_workspace/build-attestation.json"
desktop_manifest="$desktop_assets/manifest.json"
[[ -d "$desktop_assets" && ! -L "$desktop_assets" ]]
[[ -f "$desktop_attestation" && ! -L "$desktop_attestation" ]]
[[ -f "$desktop_manifest" && ! -L "$desktop_manifest" ]]
desktop_manifest_sha="$(
  jq -er '.manifest_sha256 | select(test("^[0-9a-f]{64}$"))' \
    "$desktop_attestation"
)"
[[ "$(shasum -a 256 "$desktop_manifest" | awk '{print $1}')" == \
  "$desktop_manifest_sha" ]]

cleanup_tap
tap_name=""
{
  printf 'II_FFMPEG_IOS_ARCHIVE_DIR=%s\n' "$archive_dir"
  printf 'II_FFMPEG_IOS_ATTESTATION=%s\n' "$attestation"
  printf 'II_FFMPEG_REQUIRE_RELEASE_ENGINE=true\n'
  printf 'II_FFMPEG_LIVE_TEST_ENGINE_ROOT=%s\n' "$desktop_assets"
  printf 'II_FFMPEG_LIVE_TEST_MANIFEST_SHA256=%s\n' "$desktop_manifest_sha"
} >>"${GITHUB_ENV:?}"
trap - EXIT INT TERM
