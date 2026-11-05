#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
identity="$repo_root/tool/workflow_source_identity.sh"
# shellcheck source=tool/workflow_source_identity.sh
source "$identity"
owner="ii-os-workflow-source-identity-test-$$-$RANDOM"
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

make_repository() {
  local path="$1"
  local content="$2"
  mkdir "$path"
  git -C "$path" init -q --initial-branch=main
  git -C "$path" config user.name 'ii-os workflow identity test'
  git -C "$path" config user.email 'ii-os-workflow-identity@example.invalid'
  printf '%s\n' "$content" >"$path/content.txt"
  git -C "$path" add content.txt
  git -C "$path" commit -qm initial
}

# Runs one refusal case in a subshell and requires the named reason, so a
# refusal for some unrelated reason cannot satisfy the test.
expect_refusal() {
  local reason="$1"
  shift
  if ("$@") 2>"$fixture/refusal.stderr"; then
    echo "identity check accepted a case that must refuse: $reason" >&2
    exit 1
  fi
  grep -Fq "$reason" "$fixture/refusal.stderr" || {
    echo "identity check refused for the wrong reason (wanted: $reason)" >&2
    cat "$fixture/refusal.stderr" >&2
    exit 1
  }
}

source_root="$fixture/source"
implementation_root="$fixture/implementation"
make_repository "$source_root" source
make_repository "$implementation_root" implementation
source_sha="$(git -C "$source_root" rev-parse HEAD)"
implementation_sha="$(git -C "$implementation_root" rev-parse HEAD)"
workflow=.github/workflows/release.yml
# The refusal cases run in child shells that redefine the fixtures below.
export source_sha implementation_sha implementation_root workflow

single_repository() {
  GITHUB_ACTIONS=true
  GITHUB_REPOSITORY=acme-co/example-app
  GITHUB_WORKFLOW_REF="acme-co/example-app/$workflow@refs/heads/main"
  GITHUB_SHA="$source_sha"
  II_OS_WORKFLOW_REPOSITORY=acme-co/example-app
  II_OS_WORKFLOW_BRANCH=main
  export GITHUB_ACTIONS GITHUB_REPOSITORY GITHUB_WORKFLOW_REF GITHUB_SHA
  export II_OS_WORKFLOW_REPOSITORY II_OS_WORKFLOW_BRANCH
}

split_repository() {
  GITHUB_ACTIONS=true
  GITHUB_REPOSITORY=acme-co/example-implementation
  GITHUB_WORKFLOW_REF="acme-co/example-implementation/$workflow@refs/heads/main"
  GITHUB_SHA="$implementation_sha"
  II_OS_WORKFLOW_REPOSITORY=acme-co/example-implementation
  II_OS_WORKFLOW_BRANCH=main
  II_OS_WORKFLOW_REPO_ROOT="$implementation_root"
  II_OS_IMPLEMENTATION_SHA="$implementation_sha"
  II_OS_SOURCE_SHA="$source_sha"
  export GITHUB_ACTIONS GITHUB_REPOSITORY GITHUB_WORKFLOW_REF GITHUB_SHA
  export II_OS_WORKFLOW_REPOSITORY II_OS_WORKFLOW_BRANCH
  export II_OS_WORKFLOW_REPO_ROOT II_OS_IMPLEMENTATION_SHA II_OS_SOURCE_SHA
}

# A single repository names itself and the branch its reviewed workflows run
# from; the workflow commit is both the source and the implementation commit.
(
  single_repository
  ii_os_verify_workflow_and_source "$source_root" "$workflow"
  test "$(ii_os_source_sha)" = "$source_sha"
  test "$(ii_os_implementation_sha)" = "$source_sha"
  test "$(ii_os_workflow_repository)" = acme-co/example-app
  test "$(ii_os_workflow_ref "$workflow")" = \
    "acme-co/example-app/$workflow@refs/heads/main"
)

# There is no default repository: without the setting every entry point
# refuses, even when the running repository would otherwise match.
for entry in ii_os_workflow_repository ii_os_source_sha ii_os_implementation_sha; do
  expect_refusal 'II_OS_WORKFLOW_REPOSITORY is required' \
    bash -c "source '$identity'; $(declare -f single_repository)
      single_repository; unset II_OS_WORKFLOW_REPOSITORY; $entry"
done
expect_refusal 'II_OS_WORKFLOW_REPOSITORY is required' \
  bash -c "source '$identity'; $(declare -f single_repository)
    single_repository; unset II_OS_WORKFLOW_REPOSITORY
    ii_os_verify_source_checkout '$source_root'"
expect_refusal 'II_OS_WORKFLOW_REPOSITORY is required' \
  bash -c "source '$identity'; $(declare -f single_repository)
    single_repository; unset II_OS_WORKFLOW_REPOSITORY
    ii_os_verify_workflow_and_source '$source_root' '$workflow'"

# The reviewed branch is a setting too, never an assumed default.
expect_refusal 'II_OS_WORKFLOW_BRANCH is required' \
  bash -c "source '$identity'; $(declare -f single_repository)
    single_repository; unset II_OS_WORKFLOW_BRANCH
    ii_os_verify_workflow_and_source '$source_root' '$workflow'"
expect_refusal 'II_OS_WORKFLOW_BRANCH must be a branch name' \
  bash -c "source '$identity'; $(declare -f single_repository)
    single_repository; II_OS_WORKFLOW_BRANCH=refs/heads/main
    ii_os_workflow_ref '$workflow'"
expect_refusal 'checkout must be on main' \
  bash -c "source '$identity'; $(declare -f single_repository)
    single_repository; git -C '$source_root' switch -q -c feature
    trap 'git -C \"$source_root\" switch -q main' EXIT
    ii_os_verify_source_checkout '$source_root'"
expect_refusal 'workflow ref does not match the approved workflow' \
  bash -c "source '$identity'; $(declare -f single_repository)
    single_repository; II_OS_WORKFLOW_BRANCH=release
    ii_os_verify_workflow_and_source '$source_root' '$workflow'"

# A fork running the same workflow is a different repository.
expect_refusal 'workflow repository does not match the configured repository' \
  bash -c "source '$identity'; $(declare -f single_repository)
    single_repository; GITHUB_REPOSITORY=someone-else/example-app
    ii_os_verify_workflow_and_source '$source_root' '$workflow'"
expect_refusal 'workflow repository must be an owner/repository name' \
  bash -c "source '$identity'; $(declare -f single_repository)
    single_repository; II_OS_WORKFLOW_REPOSITORY=example-app
    ii_os_workflow_repository"

# An implementation repository may authorize an exact, detached source pin.
git -C "$source_root" switch -q --detach "$source_sha"
(
  split_repository
  ii_os_verify_workflow_and_source "$source_root" "$workflow"
  test "$(ii_os_source_sha)" = "$source_sha"
  test "$(ii_os_implementation_sha)" = "$implementation_sha"
)

# A partial split identity could silently attribute one repository's build
# to another repository's commit, so it must fail closed.
expect_refusal 'must be configured together' \
  bash -c "source '$identity'; $(declare -f split_repository)
    split_repository; unset II_OS_WORKFLOW_REPO_ROOT II_OS_IMPLEMENTATION_SHA
    ii_os_verify_workflow_and_source '$source_root' '$workflow'"

# The reviewed source and implementation SHAs are both immutable bindings.
expect_refusal 'source checkout does not match its reviewed commit' \
  bash -c "source '$identity'; $(declare -f split_repository)
    split_repository
    II_OS_SOURCE_SHA=0000000000000000000000000000000000000000
    ii_os_verify_workflow_and_source '$source_root' '$workflow'"

printf 'workflow source identity test: ok\n'
