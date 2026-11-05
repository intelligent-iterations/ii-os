#!/usr/bin/env bash
# Only the configured upload workflow, on the configured branch of the
# configured repository, reaches the Google Play upload command.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
upload_script="$repo_root/tool/upload_android_internal.sh"
upload_workflow=.github/workflows/mobile-update-android.yml

grep -Fq 'ii_os_workflow_ref "$II_OS_ANDROID_UPLOAD_WORKFLOW"' "$upload_script"

state_root="$(mktemp -d)"
ownership_marker="$state_root/.ii-os-upload-contract-owned"
touch "$ownership_marker"

cleanup() {
  [[ -f "$ownership_marker" ]] || return 1
  rm -rf "$state_root"
}
trap cleanup EXIT

mkdir -p "$state_root/bin"
touch "$state_root/credentials.json"
printf 'contract fixture\n' >"$state_root/app-release.aab"
cat >"$state_root/bin/bundle" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"$II_OS_UPLOAD_CONTRACT_LOG"
SH
chmod +x "$state_root/bin/bundle"

expect_refusal() {
  local reason="$1"
  : >"$II_OS_UPLOAD_CONTRACT_LOG"
  if "$upload_script" >"$state_root/rejected.stdout" \
    2>"$state_root/rejected.stderr"; then
    echo "unapproved upload reached the upload command: $reason" >&2
    exit 1
  fi
  grep -Fq "$reason" "$state_root/rejected.stderr"
  [[ ! -s "$II_OS_UPLOAD_CONTRACT_LOG" ]]
}

# A single repository whose own catalog wrapper publishes the release.
export II_OS_WORKFLOW_REPOSITORY=acme-co/example-app
export II_OS_WORKFLOW_BRANCH=main
export II_OS_ANDROID_UPLOAD_WORKFLOW="$upload_workflow"
export GITHUB_REPOSITORY=acme-co/example-app
export GITHUB_REF=refs/heads/main
export GITHUB_WORKFLOW_REF="acme-co/example-app/$upload_workflow@refs/heads/main"
export GOOGLE_APPLICATION_CREDENTIALS="$state_root/credentials.json"
export ANDROID_AAB_PATH="$state_root/app-release.aab"
export II_OS_UPLOAD_CONTRACT_LOG="$state_root/bundle.log"
export PATH="$state_root/bin:$PATH"

"$upload_script"
grep -Fxq 'exec fastlane internal' "$II_OS_UPLOAD_CONTRACT_LOG"

# Directly dispatching the release workflow cannot publish; only the
# configured wrapper can.
export GITHUB_WORKFLOW_REF=\
acme-co/example-app/.github/workflows/release-android.yml@refs/heads/main
expect_refusal 'unexpected workflow identity'

# A run from another branch cannot publish.
export GITHUB_WORKFLOW_REF="acme-co/example-app/$upload_workflow@refs/heads/feature"
export GITHUB_REF=refs/heads/feature
expect_refusal 'unexpected ref'

# There is no default repository or upload workflow.
export GITHUB_REF=refs/heads/main
export GITHUB_WORKFLOW_REF="acme-co/example-app/$upload_workflow@refs/heads/main"
unset II_OS_WORKFLOW_REPOSITORY
expect_refusal 'II_OS_WORKFLOW_REPOSITORY is required'
export II_OS_WORKFLOW_REPOSITORY=acme-co/example-app
unset II_OS_ANDROID_UPLOAD_WORKFLOW
expect_refusal 'II_OS_ANDROID_UPLOAD_WORKFLOW is required'
export II_OS_ANDROID_UPLOAD_WORKFLOW="$upload_workflow"

# An implementation repository that pins this source as a submodule.
: >"$II_OS_UPLOAD_CONTRACT_LOG"
export GITHUB_REPOSITORY=acme-co/example-implementation
export GITHUB_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export GITHUB_WORKFLOW_REF=\
"acme-co/example-implementation/$upload_workflow@refs/heads/main"
export II_OS_WORKFLOW_REPOSITORY=acme-co/example-implementation
export II_OS_WORKFLOW_REPO_ROOT="$state_root"
export II_OS_IMPLEMENTATION_SHA="$GITHUB_SHA"
export II_OS_SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
"$upload_script"
grep -Fxq 'exec fastlane internal' "$II_OS_UPLOAD_CONTRACT_LOG"

printf 'android upload contract: ok\n'
