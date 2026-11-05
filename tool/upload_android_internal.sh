#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$repo_root/tool/workflow_source_identity.sh"

fail() {
  echo "Android internal upload refused: $*" >&2
  exit 1
}

# Only the one reviewed workflow named by II_OS_ANDROID_UPLOAD_WORKFLOW, run
# from the reviewed branch of the configured repository, may publish.
[[ -n "${II_OS_ANDROID_UPLOAD_WORKFLOW:-}" ]] ||
  fail 'II_OS_ANDROID_UPLOAD_WORKFLOW is required'
expected_repository="$(ii_os_workflow_repository)"
expected_ref="refs/heads/$(ii_os_workflow_branch)"
expected_workflow_ref="$(ii_os_workflow_ref "$II_OS_ANDROID_UPLOAD_WORKFLOW")"

[[ "${GITHUB_REPOSITORY:-}" == "$expected_repository" ]] ||
  fail 'unexpected repository'
[[ "${GITHUB_REF:-}" == "$expected_ref" ]] || fail 'unexpected ref'
[[ "${GITHUB_WORKFLOW_REF:-}" == "$expected_workflow_ref" ]] ||
  fail 'unexpected workflow identity'
[[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]] ||
  fail 'missing Google credentials path'
[[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]] ||
  fail 'Google credentials file is absent'
[[ -n "${ANDROID_AAB_PATH:-}" && -s "$ANDROID_AAB_PATH" ]] ||
  fail 'Android App Bundle is absent or empty'

(
  cd android
  bundle exec fastlane internal
)
