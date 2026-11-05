# Result policy of the work-ticket policy.
#
# The trusted controller runs Codex itself and reports usage outside the
# worker. After Codex exits, agent_execution runs this file from the
# codex_failure_diagnostic definition to its end, inside the worker, after the
# core and status helpers, under `env -i`, with `gh` and `curl` stubbed and
# with these fixed globals:
#   owner repo issue_number title issue_url stream_id
#   work_root repo_dir codex_log codex_status prompt_sha
#   branch=ii-os-agent/<first 32 hex of sha256(dispatch id)> base_branch=dev
#   work_start_sha base_sha expected_old_head_sha
#   git_user_name git_user_email push_changes=1 open_pr=1 change_bundle
#   submodule_path submodule_repository submodule_repository_id
#   submodule_base_sha submodule_expected_old_head_sha (empty without one)
#   deferred_comments_file deferred_outcome deferred_status
#   deferred_pull_request deferred_failure_json
#   IIAUTO_DEFER_GITHUB_MUTATIONS=1 IIAUTO_RESULT_FILE IIAUTO_DISPATCH_ID
#   IIAUTO_REPOSITORY_ID IIAUTO_PROJECT_ITEM_ID IIAUTO_GITHUB_APP_SLUG
#   IIAUTO_AUTOMATION_ALLOWED_APP_SLUGS IIAUTO_PROJECT_ID
#   IIAUTO_STATUS_FIELD_ID IIAUTO_STATUS_*_OPTION_ID
#   IIAUTO_WORKSPACE_HELPER_FILE (a fixed name: `python3 <it>` runs the
#   reviewed workspace materializer from stdin, never a worker file)
# It reads .auto-agent-result.md from the repository, materializes the change
# into a fresh trusted Git repository and $change_bundle, and records the
# outcome, comments and pull request intent in $IIAUTO_RESULT_FILE. Nothing
# before the codex_failure_diagnostic definition is executed.

codex_failure_diagnostic() {
  local candidate=""
  candidate="$(
    jq -Rr '
      fromjson?
      | select(.type == "turn.failed" or .type == "error")
      | [
          if (.error | type) == "object" then .error.message else empty end,
          if (.error | type) == "string" then .error else empty end,
          .message,
          .detail
        ]
      | .[]
      | select(type == "string" and length > 0)
      | gsub("[\\r\\n]+"; " ")
      | .[0:4096]
    ' "$codex_log" 2>/dev/null | tail -n 1 || true
  )"
  if [[ -z "$candidate" ]]; then
    candidate="$(
      jq -Rr '
        . as $line
        | (try fromjson catch null) as $json
        | if ($json | type) == "object" then empty else $line end
        | select(length > 0)
        | .[0:4096]
      ' "$codex_log" 2>/dev/null | tail -n 1 || true
    )"
  fi
  [[ -n "$candidate" ]] || return 0
  jq -nr --arg value "$candidate" '
    $value
    | gsub("[\\r\\n]+"; " ")
    | gsub("[[:space:]]+"; " ")
    | gsub(
        "(?i)(authorization|bearer|api[_ -]?key|access[_ -]?token|refresh[_ -]?token)[=:[:space:]]+[^[:space:]]+";
        "[CREDENTIAL]"
      )
    | gsub("gh[pousr]_[A-Za-z0-9_]+"; "[CREDENTIAL]")
    | gsub("sk-[A-Za-z0-9_-]{12,}"; "[CREDENTIAL]")
    | gsub(
        "[A-Za-z0-9_-]{12,}\\.[A-Za-z0-9_-]{12,}\\.[A-Za-z0-9_-]{12,}";
        "[CREDENTIAL]"
      )
    | gsub("https?://[^[:space:]]+"; "[URL]")
    | gsub("/(home|Users|mnt|tmp|var|private|workspace|ii-os-agent)/[^[:space:]]+"; "[PATH]")
    | ltrimstr(" ")
    | rtrimstr(" ")
    | .[0:400]
  '
}

read_agent_result_note() {
  local repository="$1"
  local note=""
  if ! note="$(
    python3 "$IIAUTO_WORKSPACE_HELPER_FILE" note "$repository" 2>/dev/null
  )"; then
    log "invalid agent result note discarded"
    return 0
  fi
  printf '%s' "$note"
}

discard_agent_result_note() {
  local repository="$1"
  rm -rf -- "$repository/.auto-agent-result.md" 2>/dev/null \
    || log "agent result note cleanup skipped"
}

set_agent_worker_phase "result_note_processing"
result_note="$(read_agent_result_note "$repo_dir")"
discard_agent_result_note "$repo_dir"
if [[ -n "${submodule_path:-}" ]]; then
  submodule_result_note="$(read_agent_result_note "$submodule_path")"
  discard_agent_result_note "$submodule_path"
  if [[ -z "$result_note" ]]; then
    result_note="$submodule_result_note"
  fi
fi

set_agent_worker_phase "outcome_evaluation"
if [[ "$codex_status" -ne 0 ]]; then
  log "codex failed with exit code $codex_status"
  codex_diagnostic="$(codex_failure_diagnostic)"
  if grep -qiE 'refresh_token_reused|token_expired|access token could not be refreshed|session expired|please (log|sign) in again|reauthenticate' "$codex_log"; then
    deferred_failure_json="$(
      jq -cn '{
        code: "codex_oauth_refresh_failed",
        detail: "The Codex OAuth session could not be refreshed."
      }'
    )"
  else
    codex_failure_detail="The Codex worker exited before producing a reviewable change."
    if [[ -n "$codex_diagnostic" ]]; then
      codex_failure_detail="Codex exited with code ${codex_status}. Diagnostic: ${codex_diagnostic}"
    fi
    deferred_failure_json="$(
      jq -cn --arg detail "$codex_failure_detail" '{
        code: "codex_worker_failed",
        detail: $detail
      }'
    )"
  fi
  write_deferred_outcome "not_ready" "todo"
  if [[ "${IIAUTO_COMMENT_ON_FAILURE:-1}" == "1" ]]; then
    if [[ "$(jq -r '.code' <<< "$deferred_failure_json")" == \
          'codex_oauth_refresh_failed' ]]; then
      issue_comment "$(printf '%s\n\nCodex authentication failed before the agent could work this ticket. Reconnect Codex from the ii-os GitHub setup page, review the failure, and press Deploy again.\n\nStream: %s\nPrompt SHA-256: %s\nExit code: %s' '<!-- ii-os:codex-auth-failed -->' "${stream_id:-unknown}" "$prompt_sha" "$codex_status")"
    else
      issue_comment "$(printf 'Auto-agent run failed before producing a reviewable change.\n\nStream: %s\nPrompt SHA-256: %s\nExit code: %s\nDiagnostic: %s' "${stream_id:-unknown}" "$prompt_sha" "$codex_status" "${codex_diagnostic:-Unavailable}")"
    fi
  fi
  set_agent_followup_status \
    "The Codex worker exited before producing a reviewable change; returning the ticket to Todo for human review." \
    "$(printf 'Stream: %s\nPrompt SHA-256: %s\nExit code: %s\nDiagnostic: %s' "${stream_id:-unknown}" "$prompt_sha" "$codex_status" "${codex_diagnostic:-Unavailable}")" \
    || exit 2
  exit "$codex_status"
fi

[[ "${IIAUTO_DEFER_GITHUB_MUTATIONS:-}" == "1" ]] \
  || die "trusted agent commits require deferred post-cleanup publication"
mkdir -p "${change_bundle%/*}"
[[ ! -e "$change_bundle" && ! -L "$change_bundle" ]] \
  || die "change bundle destination already exists"
materialize_dir="$repo_dir"
materialize_start_sha="$work_start_sha"
publication_repository="${owner}/${repo}"
publication_repository_id="${IIAUTO_REPOSITORY_ID:?}"
publication_base_sha="$base_sha"
publication_expected_old_head_sha="$expected_old_head_sha"
if [[ -n "${submodule_path:-}" ]] &&
   [[ -n "$(git -C "$submodule_path" status --porcelain --untracked-files=all)" ]]; then
  git -C "$repo_dir" diff --quiet --ignore-submodules=all -- \
    || die "the worker changed both the source repository and its submodule"
  git -C "$repo_dir" diff --cached --quiet --ignore-submodules=all -- \
    || die "the worker staged changes in both the source repository and its submodule"
  [[ -z "$(git -C "$repo_dir" ls-files --others --exclude-standard)" ]] \
    || die "the worker added files to both the source repository and its submodule"
  materialize_dir="$submodule_path"
  materialize_start_sha="$submodule_base_sha"
  publication_repository="$submodule_repository"
  publication_repository_id="$submodule_repository_id"
  publication_base_sha="$submodule_base_sha"
  publication_expected_old_head_sha="$submodule_expected_old_head_sha"
fi
set_agent_worker_phase "change_materialization"
materialized="$(
  python3 "$IIAUTO_WORKSPACE_HELPER_FILE" commit \
    "$materialize_dir" \
    "$materialize_start_sha" \
    "$branch" \
    "$change_bundle" \
    "$git_user_name" \
    "$git_user_email" \
    "Auto-agent work for #${issue_number}"
)"
head_sha="$(jq -er '.head_sha' <<< "$materialized")"
changed_files="$(jq -r '.changed_files[]?' <<< "$materialized")"
meaningful_files="$changed_files"
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || die "agent commit is invalid"

if [[ -z "$meaningful_files" ]]; then
  log "codex completed with no meaningful repository changes"
  no_op_evidence="$(printf 'Stream: %s\nPrompt SHA-256: %s\nChanged files after removing metadata: %s' "${stream_id:-unknown}" "$prompt_sha" "$(format_file_list "$changed_files" | tr '\n' ' ')")"
  readiness_blockers="$(qa_readiness_blockers "$result_note" "" "0")"
  qa_artifact="$(result_qa_artifact_value "$result_note")"
  qa_method="$(result_qa_method_value "$result_note")"
  qa_verification="$(result_verification_value "$result_note")"
  analysis_comment="$(printf 'Auto-agent completed an analysis/proposal pass for stream %s with no repository diff.\n\nPrompt SHA-256: %s\n\nResult note:\n%s' "${stream_id:-unknown}" "$prompt_sha" "${result_note:-No .auto-agent-result.md was produced.}")"
  if [[ -z "$readiness_blockers" ]]; then
    human_need_summary="Can a human review the analysis/proposal comment and confirm the direction or clarify the implementation that should be made?"
    human_action_summary="Review the ticket comment and either approve the proposed direction, clarify the requested implementation, or return the item to Todo for another automation pass that makes a meaningful code, doc, config, or test change."
    issue_comment "$(printf '%s\n\nStatus decision: Needs Human Input\n\nQuestion for human:\n%s\n\nHow to answer:\n%s\n\nNo PR was opened because planning-only work is not a PR deliverable.\n\nQA artifact: %s\nQA method: %s\nVerification: %s' "$analysis_comment" "$human_need_summary" "$human_action_summary" "${qa_artifact:-None}" "${qa_method:-None}" "${qa_verification:-None}")"
    if [[ -n "${IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID:-}" ]]; then
      set_project_status \
        "$IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID" \
        "$human_need_summary" \
        "$(printf '%s\n\nRun evidence:\n%s' "$human_action_summary" "$no_op_evidence")" \
        || exit 2
    fi
    exit 0
  fi

  if blockers_require_human_input "$readiness_blockers"; then
    human_need_summary="$(human_input_need_summary "$result_note" "$readiness_blockers")"
    human_action_summary="$(human_input_action_summary "$result_note" "$readiness_blockers")"
    blocker_summary="$(format_file_list "$readiness_blockers")"
    issue_comment "$(printf '%s\n\nStatus decision: Needs Human Input\n\nQuestion for human:\n%s\n\nHow to answer:\n%s\n\nReadiness blockers:\n%s' "$analysis_comment" "$human_need_summary" "$human_action_summary" "$blocker_summary")"
    if [[ -n "${IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID:-}" ]]; then
      set_project_status \
        "$IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID" \
        "$human_need_summary" \
        "$(printf '%s\n\nRun evidence:\n%s' "$human_action_summary" "$no_op_evidence")" \
        || exit 2
    fi
    exit 0
  fi

  agent_action_summary="$(agent_followup_action_summary "$readiness_blockers")"
  blocker_summary="$(format_file_list "$readiness_blockers")"
  issue_comment "$(printf '%s\n\nStatus decision: Agent follow-up requires another Deploy\n\nWhy this is not human input:\nThe blockers are automation/result-quality gaps, not external human-only actions.\n\nNext automation actions:\n%s\n\nReadiness blockers:\n%s' "$analysis_comment" "$agent_action_summary" "$blocker_summary")"
  set_agent_followup_status \
    "The worker produced no repository diff and did not meet the Ready for QA contract; returning the ticket to Todo for human review." \
    "$(printf '%s\n\nNext automation actions:\n%s\n\nReadiness blockers:\n%s' "$no_op_evidence" "$agent_action_summary" "$blocker_summary")" \
    || exit 2
  exit 0
fi

if [[ -n "${IIAUTO_STATUS_READY_FOR_QA_OPTION_ID:-}" ]]; then
  require_automation_identity \
    || { log "refusing to record a pull request without the configured GitHub App identity"; exit 2; }
fi

staged_files="$meaningful_files"
pr_url=""
if [[ "$push_changes" == "1" || "$push_changes" == "true" ]] &&
   [[ "$open_pr" == "1" || "$open_pr" == "true" ]]; then
  # ii-os pushes the verified bundle and opens or updates the pull request
  # after cleanup; the worker only records the exact intent.
  [[ -f "$change_bundle" && ! -L "$change_bundle" ]] \
    || die "trusted change bundle is missing"
  deferred_pull_request="$(
    jq -cn \
      --arg head "$branch" \
      --arg base "$base_branch" \
      --arg head_sha "$head_sha" \
      --arg base_sha "$publication_base_sha" \
      --arg repository "$publication_repository" \
      --argjson repository_id "$publication_repository_id" \
      --arg expected_old_head_sha "$publication_expected_old_head_sha" \
      '{repository: $repository, repository_id: $repository_id,
        head: $head, base: $base, head_sha: $head_sha,
        base_sha: $base_sha,
        expected_old_head_sha:
          (if $expected_old_head_sha == ""
           then null else $expected_old_head_sha end)}'
  )"
  write_deferred_outcome "$deferred_outcome" "$deferred_status"
fi

comment="Auto-agent completed meaningful repository work for stream ${stream_id:-unknown}."
comment="$(printf '%s\n\nPrompt SHA-256: %s' "$comment" "$prompt_sha")"
if [[ -n "$pr_url" ]]; then
  comment="$(printf '%s\n\nPR: %s' "$comment" "$pr_url")"
fi
comment="$(printf '%s\n\nChanged files:\n%s' "$comment" "$(format_file_list "$staged_files")")"
comment="$(printf '%s\n\nSubmodule PR links:\n%s' "$comment" "$(format_pr_links "$pr_url" "$result_note")")"

require_pr="$open_pr"
if [[ "$deferred_pull_request" != "null" ]]; then
  require_pr=0
fi
readiness_blockers="$(qa_readiness_blockers "$result_note" "$pr_url" "$require_pr")"
qa_artifact="$(result_qa_artifact_value "$result_note")"
qa_method="$(result_qa_method_value "$result_note")"
qa_verification="$(result_verification_value "$result_note")"

if [[ -n "$readiness_blockers" ]]; then
  blocker_summary="$(format_file_list "$readiness_blockers")"
  if blockers_require_human_input "$readiness_blockers"; then
    human_need_summary="$(human_input_need_summary "$result_note" "$readiness_blockers")"
    human_action_summary="$(human_input_action_summary "$result_note" "$readiness_blockers")"
    decision_comment="$(printf '%s\n\nStatus decision: Needs Human Input\n\nQuestion for human:\n%s\n\nHow to answer:\n%s\n\nReadiness blockers:\n%s' "$comment" "$human_need_summary" "$human_action_summary" "$blocker_summary")"
    issue_comment "$decision_comment"
    if [[ -n "${IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID:-}" ]]; then
      set_project_status \
        "$IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID" \
        "$human_need_summary" \
        "$(printf '%s\n\nRun evidence:\n- Stream: %s\n- Prompt SHA-256: %s\n- PR: %s' "$human_action_summary" "${stream_id:-unknown}" "$prompt_sha" "${pr_url:-none}")" \
        || exit 2
    fi
    log "completed with human-only blockers"
    exit 0
  else
    agent_action_summary="$(agent_followup_action_summary "$readiness_blockers")"
    decision_comment="$(printf '%s\n\nStatus decision: Agent follow-up requires another Deploy\n\nWhy this is not human input:\nThe blockers are automation/result-quality gaps, not external human-only actions.\n\nNext automation actions:\n%s\n\nReadiness blockers:\n%s' "$comment" "$agent_action_summary" "$blocker_summary")"
    issue_comment "$decision_comment"
    set_agent_followup_status \
      "The worker opened or updated repository work but did not meet the Ready for QA contract; returning the ticket to Todo for human review." \
      "$(printf 'Run evidence:\n- Stream: %s\n- Prompt SHA-256: %s\n- PR: %s\n\nNext automation actions:\n%s\n\nReadiness blockers:\n%s' "${stream_id:-unknown}" "$prompt_sha" "${pr_url:-none}" "$agent_action_summary" "$blocker_summary")" \
      || exit 2
    log "completed with agent follow-up blockers"
    exit 0
  fi
fi

ready_comment="$(printf '%s\n\nStatus decision: Ready for QA\n\nQA artifact: %s\nQA method: %s\nVerification: %s' "$comment" "$qa_artifact" "$qa_method" "$qa_verification")"
write_deferred_outcome "ready_for_qa" "ready_for_qa"
issue_comment "$(printf '%s\n\nRuntime cleanup is still being verified. ii-os will apply Ready for QA only after the exact runtime is cleaned and capacity is restored.' "$ready_comment")"
log "completed"
