#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "${REPO_ROOT}/lib/co-evolution.sh"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
COMPOSER="codex"
EXECUTOR="codex"
BOUNCES="auto"
VERIFY=false
PLAN_ONLY=false
SKIP_PLAN=false
PLAN_SOURCE=""
WORKDIR="$(pwd)"
TASK=""
REVIEWER=""
RUN_DIR=""
PLAN_PATH=""
LOG_FILE=""
IN_GIT=false
INITIAL_GIT_DIRTY=false
INITIAL_GIT_STATUS=""
PRE_EXECUTE_SHA=""
POST_EXECUTE_SHA=""

usage() {
  cat <<'EOF'
Usage:
  bash dev-review.sh [OPTIONS] <task-description>

Options:
  --composer opus|codex    Who creates the plan (default: codex)
  --executor opus|codex    Who writes the code (default: codex)
  --bounces N|auto         Pass count or auto-converge up to 6 (default: auto)
  --verify                 Add verification pass after execution
  --plan-only              Stop after bounce and keep the plan artifact
  --skip-plan              Skip compose+bounce and execute an existing plan
  --plan FILE              Existing plan file to use with --skip-plan
  --model MODEL            Override Codex model
  --workdir DIR            Working directory (default: current directory)
  --help                   Show this help text
EOF
}

normalize_path_for_bash() {
  local candidate="$1"

  if [[ -z "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v wslpath >/dev/null 2>&1 && [[ "$candidate" =~ ^[A-Za-z]:[\\/].* ]]; then
    wslpath "$candidate"
    return 0
  fi

  printf '%s' "$candidate"
}

normalize_agent() {
  case "$1" in
    codex)
      echo "codex"
      ;;
    opus|claude)
      echo "opus"
      ;;
    *)
      return 1
      ;;
  esac
}

invoke_agent() {
  local agent="$1"
  shift

  case "$agent" in
    codex)
      invoke_codex "$@"
      ;;
    opus)
      invoke_claude "$@"
      ;;
    *)
      die "Unsupported agent: $agent"
      ;;
  esac
}

invoke_agent_function() {
  case "$1" in
    codex)
      echo "invoke_codex"
      ;;
    opus)
      echo "invoke_claude"
      ;;
    *)
      return 1
      ;;
  esac
}

require_agent_cli() {
  case "$1" in
    codex)
      command -v codex >/dev/null 2>&1 || die "codex CLI is required but not installed"
      ;;
    opus)
      command -v claude >/dev/null 2>&1 || die "claude CLI is required but not installed"
      ;;
  esac
}

select_verifier() {
  if [[ "$EXECUTOR" == "codex" ]]; then
    echo "opus"
  else
    echo "codex"
  fi
}

agent_cli_name() {
  case "$1" in
    opus)
      echo "claude"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

require_selected_agent_clis() {
  local verifier=""

  if [[ "$SKIP_PLAN" == "false" ]]; then
    require_agent_cli "$COMPOSER"
    if (( MAX_BOUNCES > 0 )); then
      require_agent_cli "$REVIEWER"
    fi
  fi

  if [[ "$PLAN_ONLY" != "true" ]]; then
    require_agent_cli "$EXECUTOR"
    if [[ "$VERIFY" == "true" ]]; then
      verifier=$(select_verifier)
      require_agent_cli "$verifier"
    fi
  fi
}

ensure_codex_compatible_workdir() {
  local needs_codex="false"
  local windows_workdir=""

  if [[ "$COMPOSER" == "codex" || "$EXECUTOR" == "codex" || "$REVIEWER" == "codex" ]]; then
    needs_codex="true"
  fi

  if [[ "$needs_codex" != "true" ]]; then
    return 0
  fi

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v wslpath >/dev/null 2>&1; then
    windows_workdir=$(wslpath -w "$WORKDIR")
    if [[ "$windows_workdir" == \\\\wsl.localhost\\* ]]; then
      die "Codex under WSL requires --workdir on a Windows-mounted path (for example /mnt/c/... or C:\\...)"
    fi
  fi
}

invoke_codex_schema() {
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local schema_file="$4"
  local workdir="${WORKDIR:-$PWD}"
  local -a cmd
  local windows_workdir=""
  local windows_output=""
  local windows_schema=""

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    windows_workdir=$(wslpath -w "$workdir")
    windows_output=$(wslpath -w "$output_file")
    windows_schema=$(wslpath -w "$schema_file")
    cmd=(cmd.exe /c codex exec --full-auto --skip-git-repo-check -C "$windows_workdir")
  else
    cmd=(codex exec --full-auto --skip-git-repo-check -C "$workdir")
  fi

  if [[ -n "${CODEX_MODEL:-}" ]]; then
    cmd+=(-c "model=${CODEX_MODEL}")
  fi

  if [[ -n "$windows_schema" ]]; then
    cmd+=(--output-schema "$windows_schema" -o "$windows_output")
  else
    cmd+=(--output-schema "$schema_file" -o "$output_file")
  fi

  "${cmd[@]}" < "$prompt_file" > /dev/null 2>"$stderr_file" || true
}

write_text_file() {
  local output_path="$1"
  local content="$2"
  printf '%s' "$content" > "$output_path"
}

agent_auth_failed() {
  local agent="$1"
  shift
  local file_path
  local cli_name

  cli_name=$(agent_cli_name "$agent")

  for file_path in "$@"; do
    if file_contains_auth_failure "$file_path"; then
      log "WARNING: ${cli_name} authentication failed. Refresh the ${cli_name} CLI session and rerun."
      return 0
    fi
  done

  return 1
}

ensure_nonempty_output() {
  local output_file="$1"
  local agent="$2"
  local prompt_file="$3"
  local stderr_file="$4"

  if [[ -s "$output_file" ]]; then
    return 0
  fi

  log " WARNING: ${agent} returned empty output. Retrying once..."
  invoke_agent "$agent" "$prompt_file" "$output_file" "$stderr_file"

  if [[ ! -s "$output_file" ]]; then
    die "${agent} returned empty output on retry"
  fi
}

build_bounce_prompt() {
  local pass_number="$1"
  local total_passes="$2"
  local role="$3"
  local plan_content="$4"
  local prompt_template_file="$RUN_DIR/.bounce-template-${pass_number}.md"
  local rendered

  {
    cat "${REPO_ROOT}/agent-bouncer/templates/role-${role}.md"
    echo
    cat "${REPO_ROOT}/skill/templates/bounce-protocol.md"
  } > "$prompt_template_file"

  rendered=$(fill_template "$prompt_template_file" \
    "TASK=$TASK" \
    "PASS_NUMBER=$pass_number" \
    "TOTAL_PASSES=$total_passes" \
    "YOUR_ROLE=$role" \
    "WORKING_DIR=$WORKDIR")

  rendered="${rendered//\{PLAN_CONTENT\}/$plan_content}"
  printf '%s' "$rendered"
}

build_execution_prompt() {
  local executor="$1"
  local plan_content="$2"
  local template_path="${REPO_ROOT}/skill/templates/dev-prompt-${executor}.md"
  local stripped_template_file="$RUN_DIR/.execute-template-${executor}.md"
  local rendered

  strip_conditional "SUBSEQUENT_PASS" < "$template_path" > "$stripped_template_file"
  rendered=$(fill_template "$stripped_template_file" "TASK=$TASK")
  rendered="${rendered//\{PLAN_CONTENT\}/$plan_content}"
  printf '%s' "$rendered"
}

build_review_prompt() {
  local verifier="$1"
  local plan_content="$2"
  local diff_content="$3"
  local diff_stat="$4"
  local template_path="${REPO_ROOT}/skill/templates/review-prompt-${verifier}.md"
  local rendered

  rendered=$(fill_template "$template_path" "TASK=$TASK")
  rendered="${rendered//\{PLAN_CONTENT\}/$plan_content}"
  rendered="${rendered//\{DIFF\}/$diff_content}"
  rendered="${rendered//\{DIFF_STAT\}/$diff_stat}"
  printf '%s' "$rendered"
}

run_compose_phase() {
  local compose_prompt_file="$RUN_DIR/.compose-prompt.md"
  local compose_stderr_file="$RUN_DIR/compose-stderr.log"
  local compose_prompt

  compose_prompt="You are creating an implementation plan for the following task.

TASK: $TASK

WORKING DIRECTORY: $WORKDIR

Create a detailed plan that includes:
- What will be built
- Key technical decisions and rationale
- File structure and changes needed
- Implementation approach step by step
- Mark anything you're unsure about with [CLARIFY] followed by two possible interpretations

Output ONLY the plan document. No preamble."

  write_text_file "$compose_prompt_file" "$compose_prompt"
  invoke_agent "$COMPOSER" "$compose_prompt_file" "$PLAN_PATH" "$compose_stderr_file"
  ensure_nonempty_output "$PLAN_PATH" "$COMPOSER" "$compose_prompt_file" "$compose_stderr_file"
  cp "$PLAN_PATH" "$RUN_DIR/original-plan.md"
}

run_bounce_phase() {
  local max_bounces="$1"
  local auto_converge="$2"
  local final_markers=0
  local pass
  local role
  local current_agent
  local plan_content
  local prompt_text
  local prompt_file
  local output_file
  local stderr_file
  local retry_stderr_file
  local clean_file
  local contested
  local clarify
  local total_markers
  local word_count

  if (( max_bounces == 0 )); then
    return 0
  fi

  for (( pass=1; pass<=max_bounces; pass++ )); do
    if (( pass % 2 == 1 )); then
      role="reviewer"
      current_agent="$REVIEWER"
    else
      role="composer"
      current_agent="$COMPOSER"
    fi

    plan_content=$(cat "$PLAN_PATH")
    prompt_text=$(build_bounce_prompt "$pass" "$max_bounces" "$role" "$plan_content")
    prompt_file="$RUN_DIR/.bounce-prompt-${pass}.md"
    output_file="$RUN_DIR/.bounce-output-${pass}.md"
    stderr_file="$RUN_DIR/pass-${pass}-stderr.log"
    retry_stderr_file="$RUN_DIR/pass-${pass}-stderr-retry.log"
    clean_file="$RUN_DIR/.bounce-output-${pass}.clean.md"

    write_text_file "$prompt_file" "$prompt_text"

    log "--------------------------------------------"
    log " BOUNCE $pass/$max_bounces - ${role} (${current_agent})"
    log "--------------------------------------------"

    invoke_agent "$current_agent" "$prompt_file" "$output_file" "$stderr_file"
    validate_output "$PLAN_PATH" "$output_file" "$current_agent" "$(invoke_agent_function "$current_agent")" "$prompt_file" "$retry_stderr_file" || die "Bounce phase failed on pass ${pass}"

    cp "$output_file" "$RUN_DIR/pass-${pass}-${role}-${current_agent}-raw.md"
    strip_human_summary "$output_file" "$clean_file"
    mv "$clean_file" "$output_file"
    cp "$output_file" "$PLAN_PATH"

    contested=$(count_markers "$PLAN_PATH" "[CONTESTED]")
    clarify=$(count_markers "$PLAN_PATH" "[CLARIFY]")
    total_markers=$((contested + clarify))
    word_count=$(wc -w < "$PLAN_PATH" | tr -d '\r\n ')

    log " [CONTESTED] markers: $contested"
    log " [CLARIFY] markers:   $clarify"
    log " Plan length:         $word_count words"
    log "--------------------------------------------"
    log ""

    final_markers="$total_markers"
    if [[ "$auto_converge" == "true" && "$total_markers" -eq 0 ]]; then
      log "Plan converged after $pass passes (no open markers)."
      log ""
      break
    fi
  done

  if (( final_markers > 0 )); then
    log "WARNING: $final_markers unresolved markers remain after the bounce phase."
    log ""
  fi
}

run_execute_phase() {
  local plan_content
  local execute_prompt
  local execute_prompt_file="$RUN_DIR/.execute-prompt.md"
  local execute_output_file="$RUN_DIR/execute-output.md"
  local execute_stderr_file="$RUN_DIR/execute-stderr.log"
  local status_output=""

  if [[ "$IN_GIT" == "true" ]]; then
    PRE_EXECUTE_SHA=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || true)
  fi

  plan_content=$(cat "$PLAN_PATH")
  execute_prompt=$(build_execution_prompt "$EXECUTOR" "$plan_content")
  write_text_file "$execute_prompt_file" "$execute_prompt"

  invoke_agent "$EXECUTOR" "$execute_prompt_file" "$execute_output_file" "$execute_stderr_file"

  if agent_auth_failed "$EXECUTOR" "$execute_output_file" "$execute_stderr_file"; then
    return 2
  fi

  if [[ ! -s "$execute_output_file" ]]; then
    log "WARNING: ${EXECUTOR} returned empty output. Retrying once..."
    invoke_agent "$EXECUTOR" "$execute_prompt_file" "$execute_output_file" "$execute_stderr_file"
  fi

  if agent_auth_failed "$EXECUTOR" "$execute_output_file" "$execute_stderr_file"; then
    return 2
  fi

  if [[ ! -s "$execute_output_file" ]]; then
    log "ERROR: ${EXECUTOR} returned empty output on retry."
    return 1
  fi

  if [[ "$IN_GIT" == "true" ]]; then
    POST_EXECUTE_SHA=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || true)
    status_output=$(git -C "$WORKDIR" status --short)

    if [[ "$PRE_EXECUTE_SHA" == "$POST_EXECUTE_SHA" && "$status_output" == "$INITIAL_GIT_STATUS" ]]; then
      log "WARNING: no changes detected after execute phase. Review the executor output manually."
      return 2
    fi

    if [[ "$PRE_EXECUTE_SHA" != "$POST_EXECUTE_SHA" ]]; then
      git -C "$WORKDIR" diff --stat "${PRE_EXECUTE_SHA}..${POST_EXECUTE_SHA}" > "$RUN_DIR/execute-diffstat.txt" || true
    else
      git -C "$WORKDIR" diff --stat HEAD > "$RUN_DIR/execute-diffstat.txt" || true
    fi
  fi

  return 0
}

run_verify_phase() {
  local verifier
  local diff_file="$RUN_DIR/verify-diff.txt"
  local diff_stat_file="$RUN_DIR/verify-diffstat.txt"
  local review_prompt_file="$RUN_DIR/.review-prompt.md"
  local review_stderr_file="$RUN_DIR/review-stderr.log"
  local verdict_file="$RUN_DIR/verdict.json"
  local plan_content
  local diff_content
  local diff_stat
  local review_prompt
  local review_status=""

  if [[ "$IN_GIT" != "true" ]]; then
    log "WARNING: verification skipped - workdir is not a git repo."
    return 0
  fi

  if [[ -n "$PRE_EXECUTE_SHA" && -n "$POST_EXECUTE_SHA" && "$PRE_EXECUTE_SHA" != "$POST_EXECUTE_SHA" ]]; then
    git -C "$WORKDIR" diff "${PRE_EXECUTE_SHA}..${POST_EXECUTE_SHA}" > "$diff_file"
    git -C "$WORKDIR" diff --stat "${PRE_EXECUTE_SHA}..${POST_EXECUTE_SHA}" > "$diff_stat_file"
  elif [[ "$INITIAL_GIT_DIRTY" == "true" ]]; then
    log "WARNING: verification skipped - workdir had pre-existing uncommitted changes, so this run's diff cannot be isolated."
    return 2
  elif [[ -n "$(git -C "$WORKDIR" status --short)" ]]; then
    git -C "$WORKDIR" diff HEAD > "$diff_file"
    git -C "$WORKDIR" diff --stat HEAD > "$diff_stat_file"
  else
    log "WARNING: no changes detected, skipping diff-based verification."
    return 0
  fi

  if [[ ! -s "$diff_file" ]]; then
    log "WARNING: diff is empty, skipping diff-based verification."
    return 0
  fi

  verifier=$(select_verifier)

  plan_content=$(cat "$PLAN_PATH")
  diff_content=$(cat "$diff_file")
  diff_stat=$(cat "$diff_stat_file")
  review_prompt=$(build_review_prompt "$verifier" "$plan_content" "$diff_content" "$diff_stat")
  write_text_file "$review_prompt_file" "$review_prompt"

  if [[ "$verifier" == "codex" ]]; then
    invoke_codex_schema "$review_prompt_file" "$verdict_file" "$review_stderr_file" "${REPO_ROOT}/skill/schemas/review-verdict.json"
  else
    invoke_claude "$review_prompt_file" "$verdict_file" "$review_stderr_file"
  fi

  if agent_auth_failed "$verifier" "$verdict_file" "$review_stderr_file"; then
    return 2
  fi

  if [[ ! -s "$verdict_file" ]]; then
    log "WARNING: verifier did not return a verdict. Review manually."
    return 2
  fi

  eval "$(parse_verdict "$verdict_file")"

  if [[ -z "${VERDICT:-}" ]]; then
    log "WARNING: verdict could not be parsed. Review manually."
    return 2
  fi

  review_status="$VERDICT"
  log "Verification verdict: ${review_status}"
  if [[ -n "${CONFIDENCE:-}" ]]; then
    log "Confidence: ${CONFIDENCE}"
  fi
  if [[ -n "${SUMMARY:-}" ]]; then
    log "Summary: ${SUMMARY}"
  fi

  if [[ "$review_status" == "REVISE" ]]; then
    return 2
  fi

  return 0
}

cleanup_runtime_artifacts() {
  find "$RUN_DIR" -maxdepth 1 -type f -name '.*' -delete 2>/dev/null || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --composer)
      [[ $# -gt 1 ]] || die "--composer requires a value"
      COMPOSER=$(normalize_agent "$2") || die "Unsupported composer: $2"
      shift 2
      ;;
    --executor)
      [[ $# -gt 1 ]] || die "--executor requires a value"
      EXECUTOR=$(normalize_agent "$2") || die "Unsupported executor: $2"
      shift 2
      ;;
    --bounces)
      [[ $# -gt 1 ]] || die "--bounces requires a value"
      BOUNCES="$2"
      shift 2
      ;;
    --verify)
      VERIFY=true
      shift
      ;;
    --plan-only)
      PLAN_ONLY=true
      shift
      ;;
    --skip-plan)
      SKIP_PLAN=true
      shift
      ;;
    --plan)
      [[ $# -gt 1 ]] || die "--plan requires a value"
      PLAN_SOURCE="$2"
      shift 2
      ;;
    --model)
      [[ $# -gt 1 ]] || die "--model requires a value"
      CODEX_MODEL="$2"
      shift 2
      ;;
    --workdir)
      [[ $# -gt 1 ]] || die "--workdir requires a value"
      WORKDIR="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    --)
      shift
      TASK="$*"
      break
      ;;
    -*)
      die "Unknown flag: $1"
      ;;
    *)
      if [[ -z "$TASK" ]]; then
        TASK="$1"
      else
        TASK="${TASK} $1"
      fi
      shift
      ;;
  esac
done

WORKDIR=$(normalize_path_for_bash "$WORKDIR")
if [[ -n "$PLAN_SOURCE" ]]; then
  PLAN_SOURCE=$(normalize_path_for_bash "$PLAN_SOURCE")
fi

WORKDIR="$(cd "$WORKDIR" && pwd)"

if [[ "$SKIP_PLAN" == "true" && -z "$PLAN_SOURCE" ]]; then
  die "--skip-plan requires --plan FILE"
fi

if [[ "$SKIP_PLAN" == "false" && -n "$PLAN_SOURCE" ]]; then
  die "--plan FILE requires --skip-plan"
fi

if [[ "$SKIP_PLAN" == "false" && -z "$TASK" ]]; then
  die "Task description is required unless --skip-plan is used"
fi

if [[ -n "$PLAN_SOURCE" && ! -f "$PLAN_SOURCE" ]]; then
  die "Plan file not found: $PLAN_SOURCE"
fi

if [[ "$SKIP_PLAN" == "true" && -z "$TASK" ]]; then
  TASK="Execute approved plan from ${PLAN_SOURCE}"
fi

case "$BOUNCES" in
  auto)
    MAX_BOUNCES=6
    AUTO_CONVERGE="true"
    ;;
  ''|*[!0-9]*)
    die "--bounces must be 'auto' or a non-negative integer"
    ;;
  *)
    MAX_BOUNCES="$BOUNCES"
    AUTO_CONVERGE="false"
    ;;
esac

if [[ "$COMPOSER" == "codex" ]]; then
  REVIEWER="opus"
else
  REVIEWER="codex"
fi

ensure_codex_compatible_workdir

require_selected_agent_clis

RUN_DIR="${REPO_ROOT}/runs/dev-review-${TIMESTAMP}"
mkdir -p "$RUN_DIR"
PLAN_PATH="${RUN_DIR}/plan.md"
LOG_FILE="${RUN_DIR}/run.log"

if git -C "$WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=true
  INITIAL_GIT_STATUS=$(git -C "$WORKDIR" status --short)
  if [[ -n "$INITIAL_GIT_STATUS" ]]; then
    INITIAL_GIT_DIRTY=true
  fi
fi

log "============================================"
log " DEV-REVIEW SESSION"
log "============================================"
log " Task:      $TASK"
log " Composer:  $COMPOSER"
log " Executor:  $EXECUTOR"
log " Bounces:   $BOUNCES"
log " Verify:    $VERIFY"
log " Workdir:   $WORKDIR"
log " Run dir:   $RUN_DIR"
log "============================================"
log ""

if [[ "$SKIP_PLAN" == "true" ]]; then
  cp "$PLAN_SOURCE" "$PLAN_PATH"
else
  run_compose_phase
  run_bounce_phase "$MAX_BOUNCES" "$AUTO_CONVERGE"
fi

if [[ "$PLAN_ONLY" == "true" ]]; then
  log "Plan saved to: $PLAN_PATH"
  cleanup_runtime_artifacts
  exit 0
fi

EXECUTE_EXIT=0
run_execute_phase || EXECUTE_EXIT=$?

VERIFY_EXIT=0
if [[ "$EXECUTE_EXIT" -eq 0 && "$VERIFY" == "true" ]]; then
  run_verify_phase || VERIFY_EXIT=$?
fi

cleanup_runtime_artifacts

log ""
log "============================================"
log " DEV-REVIEW COMPLETE"
log "============================================"
log " Task:      $TASK"
log " Composer:  $COMPOSER"
log " Executor:  $EXECUTOR"
log " Verify:    $VERIFY"
log " Run dir:   $RUN_DIR"
log "============================================"

if [[ "$EXECUTE_EXIT" -eq 2 || "$VERIFY_EXIT" -eq 2 ]]; then
  exit 2
fi

if [[ "$EXECUTE_EXIT" -ne 0 || "$VERIFY_EXIT" -ne 0 ]]; then
  exit 1
fi

exit 0
