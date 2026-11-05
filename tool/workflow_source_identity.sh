#!/usr/bin/env bash

# Shared fail-closed identity checks for release and deployment workflows.
#
# II_OS_WORKFLOW_REPOSITORY (owner/name) is required everywhere: it names the
# one repository whose workflows may run these tools. There is no default, so
# a missing value refuses instead of trusting whichever repository happens to
# run the script. II_OS_WORKFLOW_BRANCH names the branch reviewed workflows
# run from; checks that compare a workflow ref or a checkout branch require it.
#
# A workflow in the same repository as this source uses the workflow commit
# for both roles. A workflow in a separate implementation repository that pins
# this source binds II_OS_WORKFLOW_REPO_ROOT, II_OS_IMPLEMENTATION_SHA, and
# II_OS_SOURCE_SHA together; a partial split identity refuses.

ii_os_identity_fail() {
  printf 'ii-os workflow identity refused: %s\n' "$1" >&2
  return 1
}

ii_os_require_git_sha() {
  local name="$1"
  local value="${2:-}"
  [[ "$value" =~ ^[0-9a-f]{40}$ ]] || {
    ii_os_identity_fail "$name must be an exact lowercase Git SHA"
    return 1
  }
}

ii_os_workflow_repository() {
  local value="${II_OS_WORKFLOW_REPOSITORY:-}"
  [[ -n "$value" ]] || {
    ii_os_identity_fail 'II_OS_WORKFLOW_REPOSITORY is required'
    return 1
  }
  [[ "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
    ii_os_identity_fail 'workflow repository must be an owner/repository name'
    return 1
  }
  printf '%s\n' "$value"
}

ii_os_workflow_branch() {
  local value="${II_OS_WORKFLOW_BRANCH:-}"
  [[ -n "$value" ]] || {
    ii_os_identity_fail 'II_OS_WORKFLOW_BRANCH is required'
    return 1
  }
  [[ "$value" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ &&
    "$value" != refs/* && "$value" != *..* && "$value" != *.lock ]] || {
    ii_os_identity_fail 'II_OS_WORKFLOW_BRANCH must be a branch name'
    return 1
  }
  printf '%s\n' "$value"
}

ii_os_identity_mode() {
  local name
  local configured=0
  local split=(
    II_OS_WORKFLOW_REPO_ROOT
    II_OS_IMPLEMENTATION_SHA
    II_OS_SOURCE_SHA
  )
  ii_os_workflow_repository >/dev/null || return
  for name in "${split[@]}"; do
    if [[ -n "${!name:-}" ]]; then configured=$((configured + 1)); fi
  done
  if ((configured == 0)); then
    printf 'single\n'
    return
  fi
  if ((configured != ${#split[@]})); then
    ii_os_identity_fail \
      'workflow root, implementation SHA, and source SHA must be configured together'
    return 1
  fi
  printf 'split\n'
}

ii_os_source_sha() {
  local mode
  local value
  mode="$(ii_os_identity_mode)" || return
  if [[ "$mode" == split ]]; then
    value="$II_OS_SOURCE_SHA"
  else
    value="${GITHUB_SHA:-}"
  fi
  ii_os_require_git_sha II_OS_SOURCE_SHA "$value" || return
  printf '%s\n' "$value"
}

ii_os_implementation_sha() {
  local mode
  local value
  mode="$(ii_os_identity_mode)" || return
  if [[ "$mode" == split ]]; then
    value="$II_OS_IMPLEMENTATION_SHA"
  else
    value="${GITHUB_SHA:-}"
  fi
  ii_os_require_git_sha II_OS_IMPLEMENTATION_SHA "$value" || return
  printf '%s\n' "$value"
}

ii_os_workflow_ref() {
  local workflow_path="$1"
  local repository
  local branch
  [[ "$workflow_path" =~ ^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$ ]] || {
    ii_os_identity_fail 'workflow path must name a root GitHub workflow YAML file'
    return 1
  }
  repository="$(ii_os_workflow_repository)" || return
  branch="$(ii_os_workflow_branch)" || return
  printf '%s/%s@refs/heads/%s\n' "$repository" "$workflow_path" "$branch"
}

ii_os_verify_checkout() {
  local label="$1"
  local root="$2"
  local expected_sha="$3"
  local require_branch="$4"
  local branch
  local physical_root
  local resolved_root
  [[ "$root" == /* && -d "$root" && ! -L "$root" ]] || {
    ii_os_identity_fail "$label checkout root must be a real absolute directory"
    return 1
  }
  physical_root="$(cd "$root" && pwd -P)" || {
    ii_os_identity_fail "$label checkout root cannot be resolved"
    return 1
  }
  resolved_root="$(git -C "$physical_root" rev-parse --show-toplevel 2>/dev/null)" || {
    ii_os_identity_fail "$label checkout root is not a Git worktree"
    return 1
  }
  [[ "$resolved_root" == "$physical_root" ]] || {
    ii_os_identity_fail "$label checkout root must be the Git worktree root"
    return 1
  }
  [[ "$(git -C "$physical_root" rev-parse HEAD)" == "$expected_sha" ]] || {
    ii_os_identity_fail "$label checkout does not match its reviewed commit"
    return 1
  }
  [[ -z "$(git -C "$physical_root" status --porcelain)" ]] || {
    ii_os_identity_fail "$label checkout is not clean"
    return 1
  }
  if [[ "$require_branch" == true ]]; then
    branch="$(ii_os_workflow_branch)" || return
    [[ "$(git -C "$physical_root" branch --show-current)" == "$branch" ]] || {
      ii_os_identity_fail "$label checkout must be on $branch"
      return 1
    }
  fi
}

ii_os_verify_source_checkout() {
  local source_root="$1"
  local mode
  local source_sha
  mode="$(ii_os_identity_mode)" || return
  source_sha="$(ii_os_source_sha)" || return
  if [[ "$mode" == single ]]; then
    ii_os_verify_checkout source "$source_root" "$source_sha" true
  else
    ii_os_verify_checkout source "$source_root" "$source_sha" false
  fi
}

ii_os_verify_workflow_and_source() {
  local source_root="$1"
  local workflow_path="$2"
  local mode
  local source_sha
  local implementation_sha
  local workflow_repository
  local expected_workflow_ref
  local implementation_root

  mode="$(ii_os_identity_mode)" || return
  source_sha="$(ii_os_source_sha)" || return
  implementation_sha="$(ii_os_implementation_sha)" || return
  workflow_repository="$(ii_os_workflow_repository)" || return
  expected_workflow_ref="$(ii_os_workflow_ref "$workflow_path")" || return
  implementation_root="${II_OS_WORKFLOW_REPO_ROOT:-$source_root}"

  [[ "${GITHUB_ACTIONS:-}" == true ]] || {
    ii_os_identity_fail 'deployment must run in GitHub Actions'
    return 1
  }
  [[ "${GITHUB_REPOSITORY:-}" == "$workflow_repository" ]] || {
    ii_os_identity_fail 'workflow repository does not match the configured repository'
    return 1
  }
  [[ "${GITHUB_WORKFLOW_REF:-}" == "$expected_workflow_ref" ]] || {
    ii_os_identity_fail 'workflow ref does not match the approved workflow'
    return 1
  }
  [[ "${GITHUB_SHA:-}" == "$implementation_sha" ]] || {
    ii_os_identity_fail 'workflow commit does not match the implementation commit'
    return 1
  }

  if [[ "$mode" == single ]]; then
    ii_os_verify_source_checkout "$source_root"
  else
    ii_os_verify_source_checkout "$source_root" || return
    ii_os_verify_checkout implementation "$implementation_root" \
      "$implementation_sha" true
  fi
}
