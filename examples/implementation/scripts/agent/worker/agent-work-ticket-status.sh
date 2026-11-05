# Readiness policy and the deferred result writer of the work-ticket policy.
#
# Sourced after the core helper. write_deferred_outcome accepts exactly one
# result path: the fixed placeholder in its guard, which agent_execution
# replaces with the run's private result file before the program runs. The
# placeholder must therefore occur exactly once in this file.

result_declares_ready_for_qa() {
  local note="$1"
  local value section
  value="$(result_field_value "$note" "Ready for QA")"
  if [[ -z "$value" ]]; then
    value="$(result_field_value "$note" "QA ready")"
  fi
  if [[ -n "$value" ]]; then
    value_is_yes "$value"
    return
  fi
  section="$(markdown_section "$note" "qa readiness")"
  if [[ -n "$section" ]]; then
    value="$(result_field_value "$section" "Ready for QA")"
    if [[ -z "$value" ]]; then
      value="$(result_field_value "$section" "QA ready")"
    fi
    [[ -n "$value" ]] && value_is_yes "$value"
    return
  fi
  return 1
}

result_qa_artifact_value() {
  local note="$1"
  local value section key
  for key in "QA artifact" "Deployed dev URL" "Dev URL" "Test URL" "Preview URL"; do
    value="$(result_field_value "$note" "$key")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  done
  section="$(markdown_section "$note" "qa readiness")"
  if [[ -n "$section" ]]; then
    for key in "QA artifact" "Deployed dev URL" "Dev URL" "Test URL" "Preview URL"; do
      value="$(result_field_value "$section" "$key")"
      if [[ -n "$value" ]]; then
        printf '%s' "$value"
        return
      fi
    done
  fi
}

result_qa_method_value() {
  local note="$1"
  local value section key heading
  for key in "QA method" "QA steps" "Manual QA" "Human QA"; do
    value="$(result_field_value "$note" "$key")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  done
  for heading in "qa method" "qa steps" "manual qa" "human qa"; do
    section="$(markdown_section "$note" "$heading")"
    if [[ -n "$section" ]]; then
      printf '%s' "$section"
      return
    fi
  done
}

result_verification_value() {
  local note="$1"
  local value section key heading
  for key in "Verification" "Verification ran"; do
    value="$(result_field_value "$note" "$key")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
  done
  for heading in "verification" "verification ran"; do
    section="$(markdown_section "$note" "$heading")"
    if [[ -n "$section" ]]; then
      printf '%s' "$section"
      return
    fi
  done
}

qa_readiness_blockers() {
  local note="$1"
  local pr="$2"
  local require_pr="${3:-$open_pr}"
  local blockers artifact method verification human_request human_need
  blockers=""

  if [[ -z "$(printf '%s' "$note" | tr -d '[:space:]')" ]]; then
    blockers="$(append_line "$blockers" "No .auto-agent-result.md status note was produced.")"
  else
    if result_declares_human_input_needed "$note"; then
      human_need="$(result_human_input_need_value "$note")"
      human_request="$(result_human_input_request_value "$note")"
      if value_is_meaningful_human_request "$human_need"; then
        blockers="$(append_line "$blockers" "Human input required: ${human_need}")"
      elif value_is_meaningful_human_request "$human_request"; then
        blockers="$(append_line "$blockers" "Human input required: ${human_request}")"
      else
        blockers="$(append_line "$blockers" "The result note says human input is needed but does not describe the exact human input or action required.")"
      fi
    elif ! result_declares_no_human_input "$note"; then
      blockers="$(append_line "$blockers" "The result note does not explicitly say Human input needed: No.")"
    fi

    if ! result_declares_ready_for_qa "$note"; then
      blockers="$(append_line "$blockers" "The result note does not explicitly say Ready for QA: Yes.")"
    fi

    artifact="$(result_qa_artifact_value "$note")"
    if ! value_is_present_artifact "$artifact"; then
      blockers="$(append_line "$blockers" "No human-testable QA artifact was reported.")"
    elif ! value_is_deployed_or_live_artifact "$artifact"; then
      blockers="$(append_line "$blockers" "No deployed or live-verifiable QA artifact was reported.")"
    fi
    if [[ -n "$pr" ]] && ! value_is_deployed_or_live_artifact "$artifact"; then
      blockers="$(append_line "$blockers" "Human input required: the worker opened or updated a PR, but the result is not deployed or live-verifiable yet; a human must review the PR, merge or deploy it to dev/staging when appropriate, and provide the deployed/live QA artifact before this can be Ready for QA.")"
    fi

    method="$(result_qa_method_value "$note")"
    if ! value_is_meaningful_qa_method "$method"; then
      blockers="$(append_line "$blockers" "No detailed human QA method was reported.")"
    fi

    verification="$(result_verification_value "$note")"
    if ! value_is_meaningful_verification "$verification"; then
      blockers="$(append_line "$blockers" "No meaningful verification evidence was reported.")"
    fi
  fi

  if [[ "$require_pr" == "1" || "$require_pr" == "true" ]]; then
    if [[ -z "$pr" ]]; then
      blockers="$(append_line "$blockers" "No pull request URL was produced for QA review.")"
    fi
  fi

  printf '%s' "$blockers"
}

blockers_require_human_input() {
  local blockers="$1"
  local blocker
  while IFS= read -r blocker; do
    case "$blocker" in
      Human\ input\ required:*) return 0 ;;
    esac
  done <<< "$blockers"
  return 1
}

human_input_need_summary() {
  local note="$1"
  local blockers="$2"
  local need
  need="$(result_human_input_need_value "$note")"
  if value_is_meaningful_human_request "$need"; then
    printf -- '- %s\n' "$need"
    return
  fi
  format_file_list "$blockers"
}

human_input_action_summary() {
  local note="$1"
  local blockers="$2"
  local action actions blocker detail
  action="$(result_human_input_action_value "$note")"
  if value_is_meaningful_human_request "$action"; then
    printf -- '- %s\n' "$action"
    return
  fi
  actions=""
  while IFS= read -r blocker; do
    [[ -n "$blocker" ]] || continue
    case "$blocker" in
      Human\ input\ required:*)
        detail="${blocker#Human input required: }"
        actions="$(append_line "$actions" "Provide the requested input or complete the requested action: ${detail}")"
        ;;
      "No human-testable QA artifact was reported.")
        actions="$(append_line "$actions" "Comment with the deployed or live-verifiable QA artifact: dev/staging URL, live endpoint, workflow run, audit link, rendered artifact, or process evidence.")"
        ;;
      "No deployed or live-verifiable QA artifact was reported.")
        actions="$(append_line "$actions" "Comment with a deployed or live-verifiable artifact instead of a PR/local preview: dev/staging URL, live endpoint, workflow run, audit link, rendered artifact, or process evidence.")"
        ;;
      "No detailed human QA method was reported.")
        actions="$(append_line "$actions" "Comment with the detailed human QA method: exact steps, command or URL, and expected result.")"
        ;;
      "No meaningful verification evidence was reported.")
        actions="$(append_line "$actions" "Run the narrow live verification and comment with the command plus relevant output, log, or audit evidence.")"
        ;;
      "No pull request URL was produced for QA review.")
        actions="$(append_line "$actions" "Push the work branch, open or link the pull request, and comment with the PR URL.")"
        ;;
      "No .auto-agent-result.md status note was produced.")
        actions="$(append_line "$actions" "Rerun or fix the worker so it writes .auto-agent-result.md with the required status block.")"
        ;;
      *"does not explicitly say Human input needed: No"*)
        actions="$(append_line "$actions" "Update the result note to explicitly state whether human input is needed, then rerun the worker.")"
        ;;
      *"does not explicitly say Ready for QA: Yes"*)
        actions="$(append_line "$actions" "Confirm whether the work is ready for QA; if it is, rerun with Ready for QA: Yes and the QA artifact, otherwise provide the blocker.")"
        ;;
      *"does not describe the exact human input"*)
        actions="$(append_line "$actions" "Comment with the exact missing secret, env var, credential, account access, approval, or externally provisioned artifact needed.")"
        ;;
      *)
        actions="$(append_line "$actions" "Resolve this blocker and comment with the artifact or evidence: ${blocker}")"
        ;;
    esac
  done <<< "$blockers"
  format_file_list "$actions"
}

agent_followup_action_summary() {
  local blockers="$1"
  local actions blocker
  actions=""
  while IFS= read -r blocker; do
    [[ -n "$blocker" ]] || continue
    case "$blocker" in
      "No .auto-agent-result.md status note was produced.")
        actions="$(append_line "$actions" "Run another automation pass that writes .auto-agent-result.md with the required status decision.")"
        ;;
      *"does not explicitly say Human input needed: No"*)
        actions="$(append_line "$actions" "Run another automation pass that makes an explicit human-input decision from the available evidence.")"
        ;;
      *"does not explicitly say Ready for QA: Yes"*)
        actions="$(append_line "$actions" "Run another automation pass to finish a meaningful code, doc, config, or test change; planning-only work should comment on the ticket instead of claiming Ready for QA.")"
        ;;
      "No human-testable QA artifact was reported.")
        actions="$(append_line "$actions" "Run another automation pass that reports a deployed or live-verifiable artifact: dev/staging URL, live endpoint, workflow run, audit link, rendered artifact, or process evidence.")"
        ;;
      "No deployed or live-verifiable QA artifact was reported.")
        actions="$(append_line "$actions" "Run another automation pass that deploys or captures a live-verifiable artifact instead of reporting only a PR, local preview, screenshot, or build log.")"
        ;;
      "No detailed human QA method was reported.")
        actions="$(append_line "$actions" "Run another automation pass that reports a detailed human QA method: exact steps, command or URL, and expected result.")"
        ;;
      "No meaningful verification evidence was reported.")
        actions="$(append_line "$actions" "Run another automation pass that performs the narrowest live verification available and records the evidence.")"
        ;;
      "No pull request URL was produced for QA review.")
        actions="$(append_line "$actions" "Run another automation pass that opens or links the PR after meaningful repository changes, or comments on the ticket with the planning/blocker result and requested human follow-up.")"
        ;;
      *)
        actions="$(append_line "$actions" "Run another automation pass to resolve or narrow this blocker without asking a human unless it is a true external human-only action: ${blocker}")"
        ;;
    esac
  done <<< "$blockers"
  format_file_list "$actions"
}

set_agent_followup_status() {
  local reason="$1"
  local evidence="$2"
  if [[ -n "${IIAUTO_STATUS_TODO_OPTION_ID:-}" ]]; then
    set_project_status "$IIAUTO_STATUS_TODO_OPTION_ID" "$reason" "$evidence"
    return
  fi
  issue_comment "$(printf 'II Auto Agent queued agent follow-up, but IIAUTO_STATUS_TODO_OPTION_ID is not configured.\n\nReason: %s\n\nEvidence:\n%s' "$reason" "$evidence")"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# Writes the bounded result ii-os validates and publishes after cleanup:
# {dispatch_id, repository, repository_id, issue_number, project_item_id,
#  outcome, status, comments, pull_request, automation_failure}.
write_deferred_outcome() {
  local outcome="$1"
  local status="${2:-}"
  [[ "${IIAUTO_DEFER_GITHUB_MUTATIONS:-}" == "1" ]] || return 0
  [[ "${IIAUTO_RESULT_FILE:-}" == '/ii-os-agent/artifacts/ii-os-agent-result.json' ]] \
    || { log "refusing a result path other than the run's private result file"; return 1; }
  case "$outcome" in
    ready_for_qa) status="${status:-ready_for_qa}" ;;
    not_ready) status="${status:-todo}" ;;
    *) die "invalid deferred outcome" ;;
  esac
  if [[ "$outcome" == "ready_for_qa" && "$status" != "ready_for_qa" ]] ||
     [[ "$outcome" == "not_ready" && "$status" != "todo" && "$status" != "needs_human_input" ]]; then
    die "invalid deferred outcome status"
  fi
  deferred_outcome="$outcome"
  deferred_status="$status"
  mkdir -p "${IIAUTO_RESULT_FILE%/*}"
  local result_tmp comments_json
  comments_json='[]'
  if [[ -s "${deferred_comments_file:-}" ]]; then
    comments_json="$(jq -s '
      if length > 8 or (map(length) | add // 0) > 24000
      then error("deferred comments exceed broker limits")
      else .
      end
    ' "$deferred_comments_file")"
  fi
  result_tmp="$(mktemp "${IIAUTO_RESULT_FILE}.XXXXXX")"
  jq -n \
    --arg dispatch_id "${IIAUTO_DISPATCH_ID:?}" \
    --arg repository "${owner}/${repo}" \
    --argjson repository_id "${IIAUTO_REPOSITORY_ID:?}" \
    --argjson issue_number "$issue_number" \
    --arg project_item_id "${IIAUTO_PROJECT_ITEM_ID:?}" \
    --arg outcome "$outcome" \
    --arg status "$status" \
    --argjson comments "$comments_json" \
    --argjson pull_request "$deferred_pull_request" \
    --argjson automation_failure "$deferred_failure_json" \
    '{dispatch_id: $dispatch_id, repository: $repository,
      repository_id: $repository_id,
      issue_number: $issue_number, project_item_id: $project_item_id,
      outcome: $outcome, status: $status, comments: $comments,
      pull_request: $pull_request,
      automation_failure: $automation_failure}' > "$result_tmp"
  chmod 0600 "$result_tmp"
  mv "$result_tmp" "$IIAUTO_RESULT_FILE"
}

agent_worker_phase="post_sandbox"

set_agent_worker_phase() {
  local phase="$1"
  [[ "$phase" =~ ^[a-z][a-z0-9_]{0,63}$ ]] \
    || die "invalid agent worker phase"
  agent_worker_phase="$phase"
}
