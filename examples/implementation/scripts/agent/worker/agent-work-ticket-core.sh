#!/usr/bin/env bash
# Shared functions of the work-ticket policy.
#
# agent_execution never runs these helpers as standalone scripts. Its trusted
# controller verifies each staged helper's SHA-256 and concatenates them into
# one generated bash program: this file, then the status helper (whose fixed
# result-path placeholder becomes the run's private result file), then the
# prompt prefix of the prepare helper or the result policy of the execute
# helper. `gh` and `curl` are stubbed to fail in those programs. Every GitHub
# mutation is deferred (IIAUTO_DEFER_GITHUB_MUTATIONS=1): comments, the Project
# status and the pull request intent are written to one bounded result file,
# which ii-os publishes only after the runtime proves cleanup.
set -euo pipefail

log() {
  printf 'auto-agent: %s\n' "$*" >&2
}

die() {
  local detail="$*"
  log "$detail"
  if [[ "${IIAUTO_DEFER_GITHUB_MUTATIONS:-}" == "1" ]] &&
     declare -F write_deferred_outcome >/dev/null 2>&1 &&
     command -v jq >/dev/null 2>&1 &&
     [[ -n "${deferred_failure_json:-}" ]]; then
    detail="$(
      jq -nr --arg value "$detail" \
        '$value | gsub("[\\r\\n]+"; " ") | gsub("[[:space:]]+"; " ")
         | ltrimstr(" ") | rtrimstr(" ") | .[0:500]'
    )"
    deferred_failure_json="$(
      jq -cn --arg detail "${detail:-Sandbox setup failed.}" \
        '{code:"agent_worker_setup_failed", detail:$detail}'
    )"
    write_deferred_outcome "not_ready" "todo" || true
  fi
  exit 2
}

csv_has_value() {
  local csv="$1"
  local needle="$2"
  local part
  local -a parts=()
  IFS=',' read -r -a parts <<< "$csv"
  for part in ${parts[@]+"${parts[@]}"}; do
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    [[ "$part" == "$needle" ]] && return 0
  done
  return 1
}

automation_actor_login=""
automation_actor_type=""

# The only automation identity is the configured GitHub App. The controller
# passes its slug as both IIAUTO_GITHUB_APP_SLUG and the allow-list.
require_automation_identity() {
  local app_slug="${IIAUTO_GITHUB_APP_SLUG:-}"
  if [[ ! "$app_slug" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,99}$ ]]; then
    log "refusing missing or invalid GitHub App automation identity"
    return 1
  fi
  if ! csv_has_value "${IIAUTO_AUTOMATION_ALLOWED_APP_SLUGS:-}" "$app_slug"; then
    log "refusing unapproved GitHub App automation identity: ${app_slug}"
    return 1
  fi
  automation_actor_login="${app_slug}[bot]"
  automation_actor_type="Bot"
}

status_name_for_option() {
  local option_id="$1"
  case "$option_id" in
    "${IIAUTO_STATUS_TODO_OPTION_ID:-}") printf 'Todo' ;;
    "${IIAUTO_STATUS_IN_PROGRESS_OPTION_ID:-}") printf 'In Progress' ;;
    "${IIAUTO_STATUS_READY_FOR_QA_OPTION_ID:-}") printf 'Ready for QA' ;;
    "${IIAUTO_STATUS_NEEDS_HUMAN_INPUT_OPTION_ID:-}") printf 'Needs Human Input' ;;
    "${IIAUTO_STATUS_QA_FAILED_OPTION_ID:-}") printf 'QA failed' ;;
    "${IIAUTO_STATUS_QA_FAILED_REFINEMENT_OPTION_ID:-}") printf 'QA failed refinement' ;;
    "") printf 'unknown' ;;
    *) printf '%s' "$option_id" ;;
  esac
}

# Appends one bounded comment to the deferred result; ii-os posts it later.
issue_comment() {
  local text="$1"
  [[ "${IIAUTO_DEFER_GITHUB_MUTATIONS:-}" == "1" ]] \
    || die "GitHub comments are published by the trusted controller only"
  # Explicit returns: a bare [[ ]] guard is not enforced by set -e in older
  # bash or inside a caller's || context.
  [[ -n "$text" && "$text" == "${text#"${text%%[![:space:]]*}"}" ]] || return 1
  [[ "${#text}" -le 8000 ]] || return 1
  jq -Rn --arg value "$text" '$value' >> "$deferred_comments_file"
  write_deferred_outcome "$deferred_outcome" "$deferred_status"
}

status_audit_comment() {
  local old_status="$1"
  local new_status="$2"
  local reason="$3"
  local evidence="$4"
  if [[ "$new_status" == "Needs Human Input" ]]; then
    cat <<COMMENT
The ii-os agent needs human input

- Actor: ${automation_actor_login:-unknown} (${automation_actor_type:-unknown})
- Status: ${old_status:-unknown} -> ${new_status:-unknown}

Question for human:
${reason}

How to answer:
${evidence}
COMMENT
    return
  fi
  cat <<COMMENT
ii-os agent status update

- Actor: ${automation_actor_login:-unknown} (${automation_actor_type:-unknown})
- Status: ${old_status:-unknown} -> ${new_status:-unknown}
- Reason: ${reason}
- Evidence: ${evidence}
COMMENT
}

human_only_status_ids() {
  if [[ -n "${IIAUTO_STATUS_HUMAN_ONLY_OPTION_IDS:-}" ]]; then
    printf '%s' "$IIAUTO_STATUS_HUMAN_ONLY_OPTION_IDS"
    return
  fi
  printf '%s,%s' "${IIAUTO_STATUS_QA_FAILED_OPTION_ID:-}" "${IIAUTO_STATUS_QA_FAILED_REFINEMENT_OPTION_ID:-}"
}

# Records the requested Project status in the deferred result. Done and the
# QA-failed states stay human-only.
set_project_status() {
  local option_id="$1"
  local reason="${2:-Project status transition requested by the ii-os agent.}"
  local evidence="${3:-No additional evidence provided.}"
  local new_status
  if [[ -z "${IIAUTO_PROJECT_ID:-}" || -z "${IIAUTO_PROJECT_ITEM_ID:-}" || -z "${IIAUTO_STATUS_FIELD_ID:-}" ]]; then
    log "project status env missing; refusing status mutation"
    return 1
  fi
  if csv_has_value "$(human_only_status_ids)" "$option_id"; then
    log "refusing automation transition to human-only Project status: $(status_name_for_option "$option_id")"
    return 1
  fi
  require_automation_identity || return 1
  if [[ "${IIAUTO_DEFER_GITHUB_MUTATIONS:-}" != "1" ]]; then
    log "Project status is published by the trusted controller only"
    return 1
  fi
  new_status="$(status_name_for_option "$option_id")"
  case "$new_status" in
    "Todo") deferred_status="todo"; deferred_outcome="not_ready" ;;
    "Needs Human Input") deferred_status="needs_human_input"; deferred_outcome="not_ready" ;;
    "Ready for QA") deferred_status="ready_for_qa"; deferred_outcome="ready_for_qa" ;;
    *) log "refusing unsupported deferred Project status: $new_status"; return 1 ;;
  esac
  issue_comment "$(
    status_audit_comment \
      "In Progress" \
      "$new_status" \
      "$reason" \
      "$evidence"
  )"
  write_deferred_outcome "$deferred_outcome" "$deferred_status"
}

format_file_list() {
  local files="$1"
  if [[ -z "$files" ]]; then
    printf 'None.'
    return
  fi
  printf '%s\n' "$files" | sed 's/^/- /'
}

extract_pr_urls() {
  local text="$1"
  printf '%s\n' "$text" \
    | grep -Eo 'https://github.com/[^[:space:])]+/pull/[0-9]+' \
    | sed 's/[.,;:]*$//' \
    | sort -u \
    || true
}

format_pr_links() {
  local primary_url="$1"
  local note="$2"
  local link any
  any=0
  if [[ -n "$primary_url" ]]; then
    printf -- '- %s/%s: %s\n' "$owner" "$repo" "$primary_url"
    any=1
  fi
  while IFS= read -r link; do
    [[ -n "$link" ]] || continue
    [[ "$link" == "$primary_url" ]] && continue
    printf -- '- %s\n' "$link"
    any=1
  done < <(extract_pr_urls "$note")
  if [[ "$any" == "0" ]]; then
    printf 'None opened by wrapper.\n'
  fi
}

append_line() {
  local existing="$1"
  local line="$2"
  if [[ -z "$existing" ]]; then
    printf '%s' "$line"
  else
    printf '%s\n%s' "$existing" "$line"
  fi
}

file_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi
  shasum -a 256 "$path" | awk '{print $1}'
}

markdown_section() {
  local text="$1"
  local heading="$2"
  printf '%s\n' "$text" \
    | awk -v target="$heading" '
      BEGIN { target = tolower(target); in_section = 0 }
      /^#{1,6}[[:space:]]+/ {
        line = tolower($0)
        sub(/^#+[[:space:]]*/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line == target) {
          in_section = 1
          next
        }
        if (in_section) {
          exit
        }
      }
      in_section { print }
    '
}

result_field_value() {
  local text="$1"
  local key="$2"
  printf '%s\n' "$text" \
    | awk -v target="$key" '
      BEGIN { target = tolower(target) }
      {
        raw = $0
        line = tolower($0)
        sub(/^[[:space:]>*-]+/, "", line)
        split(line, parts, ":")
        field = parts[1]
        sub(/[[:space:]]+$/, "", field)
        if (field == target) {
          sub(/^[[:space:]>*-]*[^:]+:[[:space:]]*/, "", raw)
          print raw
          exit
        }
      }
    '
}

value_is_yes() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" =~ (^|[^a-z])(yes|true)([^a-z]|$) ]]
}

value_is_no() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" =~ (^|[^a-z])(no|false)([^a-z]|$) ]]
}

value_is_present_artifact() {
  local value lower
  value="$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$value" ]] || return 1
  [[ "$lower" =~ ^(none|no|n/a|na|not[[:space:]-]*(available|applicable)|missing|tbd|todo|unknown)([[:space:].,;:]|$) ]] && return 1
  return 0
}

value_is_deployed_or_live_artifact() {
  local value lower token
  value="$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$value" ]] || return 1
  while IFS= read -r token; do
    token="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
    token="${token%%[),.;]}"
    [[ "$token" == http://* || "$token" == https://* ]] || continue
    [[ "$token" == *"github.com/"*"/pull/"* ]] && continue
    [[ "$token" == *"localhost"* || "$token" == *"127.0.0.1"* ]] && continue
    return 0
  done < <(printf '%s\n' "$value" | tr '[:space:],;' '\n')
  [[ "$lower" == *"pull request"* || "$lower" == *"pr review"* || "$lower" == *"review surface"* ]] && return 1
  [[ "$lower" == *"localhost"* || "$lower" == *"127.0.0.1"* || "$lower" == *"local preview"* || "$lower" == *"static preview"* ]] && return 1
  [[ "$lower" =~ (^|[^[:alnum:]])(deployed|deployment|dev|staging|firebase|hosting|workflow[[:space:]-]*run|lease|audit[[:space:]-]*event|process[[:space:]-]*status|process[[:space:]-]*evidence|rendered)([^[:alnum:]]|$) ]] && return 0
  return 1
}

value_is_meaningful_qa_method() {
  local value lower word_count
  value="$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$value" ]] || return 1
  [[ "$lower" =~ ^(none|no|n/a|na|not[[:space:]-]*(available|applicable)|missing|tbd|todo|unknown)([[:space:].,;:]|$) ]] && return 1
  [[ "$lower" =~ ^(manual[[:space:]-]*qa|qa|test|check|verify|review|see[[:space:]-]*(qa[[:space:]-]*)?artifact|use[[:space:]-]*(the[[:space:]-]*)?(qa[[:space:]-]*)?artifact)([[:space:].,;:]|$) ]] && return 1
  word_count="$(printf '%s' "$value" | awk '{print NF}')"
  [[ "$word_count" -ge 5 ]] || return 1
  return 0
}

value_is_meaningful_verification() {
  local value lower
  value="$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$value" ]] || return 1
  [[ "$lower" =~ ^(none|no|n/a|na|not[[:space:]-]*(run|verified|available|applicable)|missing|tbd|todo|unknown)([[:space:].,;:]|$) ]] && return 1
  [[ "$lower" == *"did not run tests"* ]] && return 1
  [[ "$lower" == *"did not run builds"* ]] && return 1
  [[ "$lower" == *"did not run deployment"* ]] && return 1
  [[ "$lower" == *"no verification"* ]] && return 1
  return 0
}

result_declares_human_input_needed() {
  local note="$1"
  local value section
  value="$(result_field_value "$note" "Human input needed")"
  if [[ -n "$value" ]]; then
    value_is_yes "$value"
    return
  fi
  section="$(markdown_section "$note" "human input needed")"
  if [[ -n "$section" ]]; then
    value_is_yes "$section" && ! value_is_no "$section"
    return
  fi
  return 1
}

result_declares_no_human_input() {
  local note="$1"
  local value section
  value="$(result_field_value "$note" "Human input needed")"
  if [[ -n "$value" ]]; then
    value_is_no "$value"
    return
  fi
  section="$(markdown_section "$note" "human input needed")"
  if [[ -n "$section" ]]; then
    value_is_no "$section"
    return
  fi
  return 1
}

strip_yes_no_prefix() {
  printf '%s' "$1" \
    | sed -E 's/^[[:space:]]*([Yy][Ee][Ss]|[Nn][Oo]|[Tt][Rr][Uu][Ee]|[Ff][Aa][Ll][Ss][Ee])[[:space:].:;-]*//'
}

value_is_meaningful_human_request() {
  local value lower
  value="$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ -n "$value" ]] || return 1
  [[ "$lower" =~ ^(yes|true|needed|required|human[[:space:]-]*input[[:space:]-]*(needed|required))([[:space:].,;:]|$) ]] && return 1
  [[ "$lower" =~ ^(none|no|false|n/a|na|not[[:space:]-]*(available|applicable)|tbd|todo|unknown)([[:space:].,;:]|$) ]] && return 1
  return 0
}

result_human_input_request_value() {
  local note="$1"
  local value section key heading
  for key in "Human input request" "Human ask" "Human action required" "Human action needed" "Missing human input"; do
    value="$(result_field_value "$note" "$key")"
    if value_is_meaningful_human_request "$value"; then
      printf '%s' "$value"
      return
    fi
  done

  value="$(strip_yes_no_prefix "$(result_field_value "$note" "Human input needed")")"
  if value_is_meaningful_human_request "$value"; then
    printf '%s' "$value"
    return
  fi

  for heading in "human input required" "human input needed" "human ask"; do
    section="$(markdown_section "$note" "$heading")"
    if [[ -n "$section" ]]; then
      for key in "Request" "Action required" "Human input request" "Human ask"; do
        value="$(result_field_value "$section" "$key")"
        if value_is_meaningful_human_request "$value"; then
          printf '%s' "$value"
          return
        fi
      done
      value="$(strip_yes_no_prefix "$section")"
      if value_is_meaningful_human_request "$value"; then
        printf '%s' "$value"
        return
      fi
    fi
  done
}

result_human_input_need_value() {
  local note="$1"
  local value key
  for key in "Question for human" "Blocking question" "What is needed" "Needed input" "Needed artifact" "Missing artifact" "Missing input"; do
    value="$(result_field_value "$note" "$key")"
    if value_is_meaningful_human_request "$value"; then
      printf '%s' "$value"
      return
    fi
  done
  result_human_input_request_value "$note"
}

result_human_input_action_value() {
  local note="$1"
  local value key
  for key in "How to answer" "How human can provide it" "How a human can provide it" "Human unblock action" "How to provide it" "Action to unblock"; do
    value="$(result_field_value "$note" "$key")"
    if value_is_meaningful_human_request "$value"; then
      printf '%s' "$value"
      return
    fi
  done
  result_human_input_request_value "$note"
}
