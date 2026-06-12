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
# RTUX-03: REVISE auto-loop budget. 0 = disabled (v1.0 parity: single execute+verify pass).
# Exported REVISE_LOOP_MAX env var is honored via parameter expansion below;
# CLI flag --revise-loop N overrides the env value. See option parser below.
REVISE_LOOP_MAX="${REVISE_LOOP_MAX:-0}"
# RTUX-01: Live-window mode. Honors LIVE_MODE env var (string "true"/"false");
# --live CLI flag sets it to "true". Default off = Phase 2 byte-parity.
LIVE_MODE="${LIVE_MODE:-false}"
# RTUX-02: Branch + worktree specs. Honor DEV_REVIEW_BRANCH / DEV_REVIEW_WORKTREE
# env vars as defaults; CLI flags (--branch / --worktree) override. Mutually
# exclusive — both non-empty after parsing = die. Default empty = Phase 3 byte-parity.
BRANCH_SPEC="${DEV_REVIEW_BRANCH:-}"
WORKTREE_SPEC="${DEV_REVIEW_WORKTREE:-}"
# v1.5: explicit verifier seat override. Empty = derive from executor via the
# existing select_verifier logic (byte-parity default). Env default + --verifier flag.
VERIFIER_OVERRIDE="${DEV_REVIEW_VERIFIER:-}"
# v1.5: named seat preset (e.g. codex-build). Empty = no preset (byte-parity
# default). Applied in-parser so AFTER-preset flags win (last-wins) and model/
# effort values fill-if-empty so pre-set env vars win. See apply_preset().
PRESET=""
BRANCH_CREATED=""
WORKTREE_PATH=""
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
STATE_JSON=""
BASELINE_HASHES_JSON=""
CURRENT_HASHES_JSON=""
EXECUTE_DELTA_JSON=""
RUN_ID=""
LAST_INVOKE_EXIT_CODE=0
# Phase 3 LAB-01: opt-in lab-mode routing. Empty = default runner (byte-parity invariant L-03).
LAB_MODE=""
# Phase 8 flags — default off / unset so v1.1 invocations remain byte-parity (SC-5).
TARGET=""
TIER=""
PR_BRANCH=""
DRY_RUN=false
BUDGET_USD="25"
AUTO_YES=false
FLAVOR_OVERRIDE=""
# Phase 8.1 WR-04 / D-05: run-dir override for eval harness. Empty = v1.2 default path
# (byte-parity invariant SC-5 / D-06). Harness-side passes an absolute path rooted under
# the eval fixture's .co-evolution/runs/ subtree.
RUN_DIR_OVERRIDE=""
# v1.5 Phase 3: lineage token for orchestrated re-kicks. Empty = standalone run
# (byte-parity: .orchestration is omitted). Validated as a safe fs-ish token.
PARENT_RUN_ID=""

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
  --verifier AGENT         Force the verify-phase agent (codex|opus|claude); default derives from --executor
  --claude-model MODEL     Override Claude model (alias: fable -> claude-fable-5; else passthrough)
  --preset NAME            Expand a named seat preset (available: codex-build).
                           codex-build = Fable plans (high) + Codex executes (xhigh) + Fable reviews (max),
                           --verify on, bounces 2, revise-loop 1. Precedence: flags placed AFTER --preset
                           override it (last-wins); pre-set model/effort env vars win over the preset.
  --workdir DIR            Working directory (default: current directory)
  --timeout SECONDS        Per-phase timeout in seconds (default: 1800)
  --revise-loop N          Auto-retry on REVISE verdict up to N extra passes (default: 0 = disabled)
  --live                   Launch visible Windows terminal tailing each phase's stderr (Windows-only; warns + falls back on other OS)
  --branch auto|NAME       Create a feature branch off HEAD before execute (auto = dev-review/auto-<timestamp>-<slug>); mutually exclusive with --worktree
  --worktree auto|PATH     Create a git worktree for isolation before execute (auto = sibling dir); mutually exclusive with --branch
  --parent-run RUN_ID      Lineage tag: record the orchestrator's parent run id in state.orchestration.parent_run_id (re-kicks always get a fresh run dir; no behavior change)
  --lab MODE               Route to lab/<MODE>/entry.sh (opt-in beta channel; see lab/README.md)
  --target FILE            PEL-only: file to mutate (used with --lab pel-proposer; must be repo-relative forward-slash path, e.g. lib/co-evolution.sh — NOT absolute or WSL/Windows-style)
  --tier TIER              PEL-only: override tier auto-detect (template|policy|code)
  --pr-branch NAME         PEL-only: override default pel/<tier>/<short-hash> branch name
  --dry-run                PEL-only: stub `gh` via CO_EVOLVE_DRY_RUN=1 + PATH shadow
  --budget USD             PEL-only: scoring budget cap (default 25; exit 6 on exhaustion)
  --yes                    PEL-only: skip interactive preflight cost-estimate prompt
  --flavor NAME            PEL-only: override classifier (maps to PEL_FLAVOR_OVERRIDE)
  --help                   Show this help text
EOF
}

# normalize_path_for_bash is provided by lib/co-evolution.sh (sourced above) and
# is the single canonical cross-platform path helper. Do not redefine it here.

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

# v1.5: resolve a friendly Claude model alias to its CLI model id. Only `fable`
# is aliased today (→ claude-fable-5); anything else passes through verbatim so
# explicit ids (claude-opus-4-6, claude-opus-4-8[1m], …) and an empty value are
# untouched. Used by the --claude-model flag and the per-seat env layer.
resolve_claude_model_alias() {
  case "$1" in
    fable) echo "claude-fable-5" ;;
    *)     echo "$1" ;;
  esac
}

# v1.5: expand a named seat preset into the underlying seat/model/effort knobs.
# Called from the --preset parser arm. Two precedence rules, both deliberate:
#   - seat/structural knobs (COMPOSER, EXECUTOR, VERIFIER_OVERRIDE, VERIFY,
#     BOUNCES, REVISE_LOOP_MAX) are set hard, so flags placed AFTER --preset
#     override them via last-wins parsing.
#   - model/effort knobs use fill-if-empty (`: "${VAR:=…}"`) so a value already
#     present in the environment (e.g. COMPOSER_EFFORT=low) wins over the preset.
apply_preset() {
  case "$1" in
    codex-build)   # "build with codex": Fable plans/reviews, Codex executes.
      COMPOSER="opus"; EXECUTOR="codex"; VERIFIER_OVERRIDE="opus"
      VERIFY=true; BOUNCES=2; REVISE_LOOP_MAX=1
      : "${COMPOSER_MODEL:=fable}";  : "${COMPOSER_EFFORT:=high}"
      : "${VERIFIER_MODEL:=fable}";  : "${VERIFIER_EFFORT:=max}"
      : "${EXECUTOR_EFFORT:=xhigh}"   # codex model stays the CLI's configured default — deliberately unpinned
      ;;
    *) die "Unknown preset: $1 (available: codex-build)" ;;
  esac
}

invoke_agent() {
  local agent="$1"
  shift

  # Last positional arg (4th after agent) is the writable flag for Claude.
  # Codex invocations ignore it. Default: text-phase ("false") if unset.
  local prompt_file="$1"
  local output_file="$2"
  local stderr_file="$3"
  local writable="${4:-false}"

  case "$agent" in
    codex)
      # Narrowed from "$@" to explicit positionals because codex has no
      # writable-flag analogue (its permission model is --full-auto, set
      # inside invoke_codex). Phase 7 may revisit if codex grows a parity flag.
      invoke_codex "$prompt_file" "$output_file" "$stderr_file"
      ;;
    opus)
      invoke_claude "$prompt_file" "$output_file" "$stderr_file" "$writable"
      ;;
    *)
      die "Unsupported agent: $agent"
      ;;
  esac
}

# RNPT-05: Centralized timeout-abort. When LAST_INVOKE_EXIT_CODE==124, record
# the timeout event in state.json, log a clear error, clean up transient
# artifacts, and exit with the script's own fatal code 1 (124 lives only in
# state.json.phases[].exit_code for observability).
abort_on_timeout() {
  local phase_name="$1"
  local phase_start="$2"
  if (( LAST_INVOKE_EXIT_CODE == 124 )); then
    local phase_end
    phase_end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [[ -n "${STATE_JSON:-}" ]]; then
      write_state_phase "$STATE_JSON" "$phase_name" "timeout" 124 "$phase_start" "$phase_end"
      write_state_field "$STATE_JSON" ".completed_at" "string" "$phase_end"
    fi
    log "ERROR: ${phase_name} phase timed out after ${PHASE_TIMEOUT}s - aborting run"
    cleanup_runtime_artifacts
    exit 1
  fi
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
  # v1.5: an explicit --verifier / DEV_REVIEW_VERIFIER override wins; otherwise
  # derive the opposite-of-executor default (byte-parity when unset).
  if [[ -n "${VERIFIER_OVERRIDE:-}" ]]; then
    echo "$VERIFIER_OVERRIDE"
    return 0
  fi
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

  # v1.5: with --verifier codex (or executor=opus default) the verify phase runs
  # codex too, so its workdir must satisfy the same WSL constraint. Only matters
  # when verification is requested. Byte-parity holds: default executor=codex →
  # verifier=opus → this branch is a no-op.
  if [[ "$VERIFY" == "true" && "$(select_verifier)" == "codex" ]]; then
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

# v1.5 (fixes B2): invoke_codex_schema now lives in lib/co-evolution.sh (sourced
# at the top of this script). It was previously defined here, but the verify
# phase dispatches it inside a `bash -c 'source lib/co-evolution.sh; invoke_...'`
# child that can only see lib-defined functions — so the local copy was invisible
# there (exit 127 when a timeout binary exists and verifier=codex). Moved to lib
# so both the timeout child and the no-timeout fallback resolve the same function.

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
    cat "${REPO_ROOT}/skills/dev-review/templates/bounce-protocol.md"
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

# RTUX-03: Summarize the normalized verdict JSON into a one-paragraph feedback
# block for the execute prompt. Output is plain text (no markdown preamble),
# because the surrounding template already labels the section.
build_reviewer_feedback_summary() {
  local verdict_json="$1"
  local summary
  summary=$(printf '%s' "$verdict_json" | jq -r '.summary // "(no summary)"' 2>/dev/null)
  # Collapse to one line — jq already returns a single string field, but defensively
  # guard against embedded newlines in adversarial verdicts.
  summary=${summary//$'\n'/ }
  printf 'The verifier marked the prior pass as REVISE. Summary: %s' "$summary"
}

# RTUX-03: Render the verdict JSON's issues[] as a markdown bullet list for the
# execute prompt. Rendering goes through `jq -r`, which safely escapes any
# adversarial content in reviewer-authored fields (T-02-02 mitigation).
build_issues_list_markdown() {
  local verdict_json="$1"
  local rendered
  rendered=$(printf '%s' "$verdict_json" | jq -r '
    (.issues // []) | if length == 0 then "(no issues listed)"
    else
      map(
        "- **[" + (.severity // "?") + "]** " +
        (if .file then "`" + .file + "`" + (if .line_range then ":" + .line_range else "" end) + " — " else "" end) +
        (.description // "") +
        (if .suggestion then " _Suggestion: " + .suggestion + "_" else "" end)
      ) | join("\n")
    end
  ' 2>/dev/null)
  if [[ -z "$rendered" ]]; then
    rendered="(issue parser failed)"
  fi
  printf '%s' "$rendered"
}

build_execution_prompt() {
  local executor="$1"
  local plan_content="$2"
  local feedback_json="${3:-}"   # RTUX-03: empty = first pass, v1.0-identical output
  local template_path="${REPO_ROOT}/skills/dev-review/templates/dev-prompt-${executor}.md"
  local stripped_template_file="$RUN_DIR/.execute-template-${executor}.md"
  local rendered

  if [[ -z "$feedback_json" ]]; then
    # First pass: strip the SUBSEQUENT_PASS block entirely.
    # Byte-identical output to v1.0 (see Task 4 Scenario 4 invariant).
    strip_conditional "SUBSEQUENT_PASS" < "$template_path" > "$stripped_template_file"
    rendered=$(fill_template "$stripped_template_file" "TASK=$TASK")
    rendered="${rendered//\{PLAN_CONTENT\}/$plan_content}"
  else
    # Retry pass: keep the SUBSEQUENT_PASS block; replace {REVIEWER_FEEDBACK} and
    # {ISSUES_LIST} with rendered content from the normalized verdict JSON.
    # fill_conditional reads the template on stdin, strips the IF/END_IF tag
    # lines, and substitutes KEY={value} placeholders in the full stripped text.
    local reviewer_feedback issues_list
    reviewer_feedback=$(build_reviewer_feedback_summary "$feedback_json")
    issues_list=$(build_issues_list_markdown "$feedback_json")

    rendered=$(fill_conditional "SUBSEQUENT_PASS" \
      "REVIEWER_FEEDBACK=$reviewer_feedback" \
      "ISSUES_LIST=$issues_list" \
      < "$template_path")
    rendered="${rendered//\{TASK\}/$TASK}"
    rendered="${rendered//\{PLAN_CONTENT\}/$plan_content}"
  fi

  printf '%s' "$rendered"
}

build_review_prompt() {
  local verifier="$1"
  local plan_content="$2"
  local diff_content="$3"
  local diff_stat="$4"
  local template_path="${REPO_ROOT}/skills/dev-review/templates/review-prompt-${verifier}.md"
  local rendered

  rendered=$(fill_template "$template_path" "TASK=$TASK")
  rendered="${rendered//\{PLAN_CONTENT\}/$plan_content}"
  rendered="${rendered//\{DIFF\}/$diff_content}"
  rendered="${rendered//\{DIFF_STAT\}/$diff_stat}"
  printf '%s' "$rendered"
}

inspect_plan_output() {
  local agent="$1"
  local output_file="$2"
  local stderr_file="$3"
  local input_file="${4:-}"
  local cli_name=""
  local input_words=0
  local output_words=0
  local plan_reason=""

  PLAN_OUTPUT_STATUS="ok"
  PLAN_OUTPUT_REASON=""
  cli_name=$(agent_cli_name "$agent")

  if file_contains_auth_failure "$output_file" || file_contains_auth_failure "$stderr_file"; then
    PLAN_OUTPUT_STATUS="review"
    PLAN_OUTPUT_REASON="${cli_name} authentication failed"
    return 1
  fi

  if [[ ! -s "$output_file" ]]; then
    if file_contains_error_payload "$stderr_file"; then
      PLAN_OUTPUT_STATUS="review"
      PLAN_OUTPUT_REASON="${cli_name} returned an error payload"
      return 1
    fi

    PLAN_OUTPUT_STATUS="empty"
    PLAN_OUTPUT_REASON="${cli_name} returned empty output"
    return 1
  fi

  if [[ -n "$input_file" ]] && ! size_sanity_check "$input_file" "$output_file"; then
    input_words=$(wc -w < "$input_file" | tr -d '\r\n ')
    output_words=$(wc -w < "$output_file" | tr -d '\r\n ')

    if file_contains_error_payload "$output_file" || file_contains_error_payload "$stderr_file"; then
      PLAN_OUTPUT_STATUS="review"
      PLAN_OUTPUT_REASON="${cli_name} returned an error payload instead of a full plan"
      return 1
    fi

    PLAN_OUTPUT_STATUS="thin"
    PLAN_OUTPUT_REASON="${cli_name} returned ${output_words} words for a ${input_words}-word plan"
    return 1
  fi

  if ! plan_reason=$(validate_plan_artifact "$output_file"); then
    if file_contains_error_payload "$output_file" || file_contains_error_payload "$stderr_file"; then
      PLAN_OUTPUT_STATUS="review"
      PLAN_OUTPUT_REASON="${cli_name} returned an error payload instead of a structured plan"
      return 1
    fi

    PLAN_OUTPUT_STATUS="thin"
    PLAN_OUTPUT_REASON="$plan_reason"
    return 1
  fi

  return 0
}

ensure_valid_plan_output() {
  local phase_name="$1"
  local agent="$2"
  local prompt_file="$3"
  local output_file="$4"
  local stderr_file="$5"
  local retry_stderr_file="$6"
  local input_file="${7:-}"
  # RNPT-02: 8th positional is the calling phase name (compose|bounce) so the
  # retry inherits its parent's writable posture via phase_is_writable.
  # Default to "bounce" — the common call site — which resolves to text-phase.
  local calling_phase="${8:-bounce}"

  inspect_plan_output "$agent" "$output_file" "$stderr_file" "$input_file" && return 0

  case "$PLAN_OUTPUT_STATUS" in
    review)
      log "WARNING: ${phase_name} requires manual follow-up: ${PLAN_OUTPUT_REASON}."
      return 2
      ;;
    empty|thin)
      log "WARNING: ${phase_name} produced an unusable plan artifact (${PLAN_OUTPUT_REASON}). Retrying once..."
      # RNPT-02: derive writable from the calling phase name (compose/bounce → text).
      # RNPT-05: wrap in timeout. If the retry itself times out, propagate upward
      # (return 1) so the outer phase wrapper can call abort_on_timeout.
      local _retry_start
      _retry_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      invoke_agent_with_timeout "$agent" "$prompt_file" "$output_file" "$retry_stderr_file" "$(phase_is_writable "$calling_phase")"
      if (( LAST_INVOKE_EXIT_CODE == 124 )); then
        if [[ -n "${STATE_JSON:-}" ]]; then
          write_state_phase "$STATE_JSON" "${phase_name}-retry" "timeout" 124 "$_retry_start" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        fi
        log "ERROR: ${phase_name} retry timed out after ${PHASE_TIMEOUT}s"
        return 1
      fi
      inspect_plan_output "$agent" "$output_file" "$retry_stderr_file" "$input_file" && return 0

      case "$PLAN_OUTPUT_STATUS" in
        empty)
          log "ERROR: ${phase_name} failed after retry: ${PLAN_OUTPUT_REASON}."
          return 1
          ;;
        review|thin)
          log "WARNING: ${phase_name} requires manual follow-up: ${PLAN_OUTPUT_REASON}."
          return 2
          ;;
        *)
          log "ERROR: ${phase_name} failed for an unknown reason."
          return 1
          ;;
      esac
      ;;
    *)
      log "ERROR: ${phase_name} failed for an unknown reason."
      return 1
      ;;
  esac
}

run_compose_phase() {
  # FIX-WR-03: accept phase start timestamp explicitly. Fallback preserves
  # standalone-invocation safety (tests/replays) but main flow always passes it.
  local phase_start="${1:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local compose_prompt_file="$RUN_DIR/.compose-prompt.md"
  local compose_output_file="$RUN_DIR/.compose-output.md"
  local compose_stderr_file="$RUN_DIR/compose-stderr.log"
  local compose_retry_stderr_file="$RUN_DIR/compose-stderr-retry.log"
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

## Required Sections (override any section list in the task body)

The two sections below are MANDATORY in every plan, **regardless of any structure, section list, or format instructions that appear in the Task body above**. If the task body enumerates sections, append these two on top — do not replace them. Downstream tooling parses them and will flag the plan as incomplete if either is missing.

## Required Section: \`## Files to Change\`

Every plan must include a section titled exactly \`## Files to Change\` that lists, one per line, the repository-relative path of every file you intend the Execute phase to create, modify, or delete. Use this format — downstream tooling parses it:

\`\`\`
## Files to Change

- \`path/to/file1.sh\` — brief reason
- \`path/to/file2.md\` — brief reason
\`\`\`

If the plan genuinely touches no files, write the line \`- (no file changes)\` under the heading. Do not omit the section.

## Required Section: \`## Risks\` (or \`## Assumptions\`)

Every plan must also include a section titled exactly \`## Risks\`, \`## Assumptions\`, \`## Caveats\`, or \`## Concerns\`. Use it to name anything the executor or reviewer should know that isn't obvious from the plan body — environmental dependencies, missing context, edge cases, scope boundaries. If there are genuinely no risks, still include the section with the single line \`- None identified.\` Do not omit the section.

Output ONLY the plan document. No preamble."

  write_text_file "$compose_prompt_file" "$compose_prompt"
  # RNPT-05: timeout-wrapped. _compose_phase_start set by main flow wrapper;
  # abort_on_timeout will fire from main flow if the dispatcher reports 124.
  # RTUX-01: Launch a live-tail window before the agent call (no-op unless --live).
  maybe_launch_live_window "compose" "$compose_stderr_file"
  # v1.5 Phase 3: mark the compose phase as STARTING (status reader heartbeat).
  begin_state_phase "$STATE_JSON" "compose"
  # v1.5: layer the composer seat's model/effort (no-op when no per-seat env set).
  apply_seat_env composer "$COMPOSER"
  invoke_agent_with_timeout "$COMPOSER" "$compose_prompt_file" "$compose_output_file" "$compose_stderr_file" "$(phase_is_writable compose)"
  abort_on_timeout "compose" "$phase_start"
  ensure_valid_plan_output "compose phase" "$COMPOSER" "$compose_prompt_file" "$compose_output_file" "$compose_stderr_file" "$compose_retry_stderr_file" "" "compose" || return $?
  cp "$compose_output_file" "$PLAN_PATH"
  cp "$PLAN_PATH" "$RUN_DIR/original-plan.md"
  # WR-02 / D-03: persist compose output at the contract path (evals/RUNNER-CONTRACT.md §2)
  # so scorer cross-AI diversity dimension (evals/score-run.sh:559) can read it. Plain path
  # (no dot-prefix) survives cleanup_runtime_artifacts (maxdepth 1, -name '.*'). Mirrors the
  # outputs/bounce-NN.txt persistence pattern at line 675.
  cp "$compose_output_file" "$RUN_DIR/outputs/compose.txt"
}

verify_bounce_ran() {
  local run_dir="$1"
  local outputs_dir="${run_dir}/outputs"
  local count=0

  # PRTP-04 / UPSTREAM-MESSAGE.md item 6: structural signal.
  # "No bounce-NN.txt files == loop never actually ran a pass."
  # Zero-padded NN matches the write pattern in run_bounce_phase.
  if [[ -d "$outputs_dir" ]]; then
    count=$(find "$outputs_dir" -maxdepth 1 -type f -name 'bounce-*.txt' 2>/dev/null | wc -l | tr -d '\r\n ')
  fi

  BOUNCE_ARTIFACT_COUNT="$count"

  if (( count > 0 )); then
    return 0
  fi

  return 1
}

run_bounce_phase() {
  local max_bounces="$1"
  local auto_converge="$2"
  local final_markers=0
  local final_contested=0
  local final_clarify=0
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
  local pass_padded

  if (( max_bounces == 0 )); then
    return 0
  fi

  local bounce_pass_start=""
  local bounce_pass_end=""
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

    bounce_pass_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf -v pass_padded '%02d' "$pass"
    # RNPT-05: timeout-wrapped. abort_on_timeout uses per-pass bounce-NN name
    # so state.json records which pass hit the timeout.
    # RTUX-01: Per-pass live-tail window (bounce-01, bounce-02, ...) when --live.
    maybe_launch_live_window "bounce-${pass_padded}" "$stderr_file"
    # v1.5 Phase 3: mark this bounce pass as STARTING (matches the bounce-NN
    # name write_state_phase records on completion).
    begin_state_phase "$STATE_JSON" "bounce-${pass_padded}"
    # v1.5: composer turns get the composer seat's model/effort; reviewer (the
    # bounce counterparty) turns use globals only (the `bounce` seat is a no-op
    # arm in apply_seat_env). No-op overall when no per-seat env is set.
    if [[ "$role" == "composer" ]]; then
      apply_seat_env composer "$current_agent"
    else
      apply_seat_env bounce "$current_agent"
    fi
    invoke_agent_with_timeout "$current_agent" "$prompt_file" "$output_file" "$stderr_file" "$(phase_is_writable bounce)"
    abort_on_timeout "bounce-${pass_padded}" "$bounce_pass_start"
    ensure_valid_plan_output "bounce pass ${pass}" "$current_agent" "$prompt_file" "$output_file" "$stderr_file" "$retry_stderr_file" "$PLAN_PATH" "bounce" || return $?

    cp "$output_file" "$RUN_DIR/pass-${pass}-${role}-${current_agent}-raw.md"
    strip_human_summary "$output_file" "$clean_file"
    mv "$clean_file" "$output_file"
    cp "$output_file" "$PLAN_PATH"

    # Structural signal for downstream verification (PRTP-04, UPSTREAM-MESSAGE.md item 6).
    # Distinguishes "bounce converged in 0 passes" from "bounce step was skipped entirely."
    # File is persisted under outputs/ so `cleanup_runtime_artifacts` (maxdepth 1) does not delete it.
    # (pass_padded already set earlier in loop for abort_on_timeout.)
    cp "$output_file" "$RUN_DIR/outputs/bounce-${pass_padded}.txt"

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
    final_contested="$contested"
    final_clarify="$clarify"

    # RNPT-04: Per-pass bounce-NN entry in state.json.
    bounce_pass_end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [[ -n "${STATE_JSON:-}" ]]; then
      write_state_phase "$STATE_JSON" "bounce-${pass_padded}" "ok" 0 "$bounce_pass_start" "$bounce_pass_end"
    fi

    if [[ "$auto_converge" == "true" && "$total_markers" -eq 0 ]]; then
      log "Plan converged after $pass passes (no open markers)."
      log ""
      break
    fi
  done

  if (( final_markers > 0 )); then
    if [[ "$auto_converge" == "true" ]]; then
      log "WARNING: bounce limit reached with ${final_contested} [CONTESTED] and ${final_clarify} [CLARIFY] markers still open. Manual arbitration is required before execution."
      log ""
      return 2
    fi

    log "WARNING: $final_markers unresolved markers remain after the bounce phase."
    log ""
  fi

  if verify_bounce_ran "$RUN_DIR"; then
    log " Bounce artifacts: ${BOUNCE_ARTIFACT_COUNT} pass file(s) in outputs/"
  else
    log " Bounce artifacts: none written (structural signal: bounce loop did not execute a pass)"
  fi
  log ""

  return 0
}

run_execute_phase() {
  # FIX-WR-03: accept phase start timestamp explicitly (see run_compose_phase comment).
  local phase_start="${1:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local plan_content
  local execute_prompt
  local execute_prompt_file="$RUN_DIR/.execute-prompt.md"
  local execute_output_file="$RUN_DIR/execute-output.md"
  local execute_stderr_file="$RUN_DIR/execute-stderr.log"
  local status_output=""

  if [[ "$IN_GIT" == "true" ]]; then
    PRE_EXECUTE_SHA=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || true)
  fi

  # v1.5 Phase 3: record the workdir HEAD just before the executor runs so a
  # reviewer can pin the exact pre-change commit. Non-git / detached / failed
  # rev-parse yields an empty PRE_EXECUTE_SHA → write null (never die).
  if [[ -n "${STATE_JSON:-}" ]]; then
    if [[ -n "$PRE_EXECUTE_SHA" ]]; then
      write_state_field "$STATE_JSON" ".pre_execute_sha" "string" "$PRE_EXECUTE_SHA"
    else
      write_state_field "$STATE_JSON" ".pre_execute_sha" "null"
    fi
  fi

  # RNPT-03: Capture pre-execute baseline hash of every workdir file.
  # Delta computed post-execute and written into state.json.
  if [[ -n "${STATE_JSON:-}" && -n "${BASELINE_HASHES_JSON:-}" ]]; then
    snapshot_workdir_hashes "$WORKDIR" "$BASELINE_HASHES_JSON"
    write_state_field "$STATE_JSON" ".baseline_hashes" "rawfile" "$BASELINE_HASHES_JSON"
  fi

  plan_content=$(cat "$PLAN_PATH")
  # RTUX-03: Thread REVISE_FEEDBACK_JSON through to build_execution_prompt. On
  # pass 1 the main-flow loop unsets this, yielding v1.0-identical prompt output.
  # On pass 2+ the loop exports the captured verdict JSON, which triggers the
  # SUBSEQUENT_PASS conditional block (see build_execution_prompt).
  execute_prompt=$(build_execution_prompt "$EXECUTOR" "$plan_content" "${REVISE_FEEDBACK_JSON:-}")
  write_text_file "$execute_prompt_file" "$execute_prompt"

  # RNPT-05: timeout-wrapped. abort_on_timeout uses _execute_phase_start from main flow.
  # RTUX-01: Live-tail window for execute phase (no-op unless --live).
  maybe_launch_live_window "execute" "$execute_stderr_file"
  # v1.5: layer the executor seat's model/effort. The in-phase empty-output retry
  # below inherits these exported values (no second apply needed). No-op when no
  # per-seat env is set.
  apply_seat_env executor "$EXECUTOR"
  invoke_agent_with_timeout "$EXECUTOR" "$execute_prompt_file" "$execute_output_file" "$execute_stderr_file" "$(phase_is_writable execute)"
  abort_on_timeout "execute" "$phase_start"

  if agent_auth_failed "$EXECUTOR" "$execute_output_file" "$execute_stderr_file"; then
    return 2
  fi

  if [[ ! -s "$execute_output_file" ]]; then
    log "WARNING: ${EXECUTOR} returned empty output. Retrying once..."
    invoke_agent_with_timeout "$EXECUTOR" "$execute_prompt_file" "$execute_output_file" "$execute_stderr_file" "$(phase_is_writable execute-retry)"
    abort_on_timeout "execute-retry" "$phase_start"
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

    # v1.5 Phase 3: record the workdir HEAD just after change detection so a
    # reviewer can see whether the executor committed (pre != post) or left the
    # tree dirty (pre == post). Empty rev-parse → null (never die).
    if [[ -n "${STATE_JSON:-}" ]]; then
      if [[ -n "$POST_EXECUTE_SHA" ]]; then
        write_state_field "$STATE_JSON" ".post_execute_sha" "string" "$POST_EXECUTE_SHA"
      else
        write_state_field "$STATE_JSON" ".post_execute_sha" "null"
      fi
    fi

    # RNPT-03: Post-execute delta (runs regardless of "no changes" branch below
    # so Phase 8 scorer sees an empty delta rather than a missing field).
    if [[ -n "${STATE_JSON:-}" && -n "${CURRENT_HASHES_JSON:-}" && -n "${EXECUTE_DELTA_JSON:-}" ]]; then
      snapshot_workdir_hashes "$WORKDIR" "$CURRENT_HASHES_JSON"
      compute_execute_delta   "$BASELINE_HASHES_JSON" "$CURRENT_HASHES_JSON" "$EXECUTE_DELTA_JSON"
      write_state_field "$STATE_JSON" ".execute_delta" "rawfile" "$EXECUTE_DELTA_JSON"
    fi

    if [[ "$PRE_EXECUTE_SHA" == "$POST_EXECUTE_SHA" && "$status_output" == "$INITIAL_GIT_STATUS" ]]; then
      log "WARNING: no changes detected after execute phase. Review the executor output manually."
      return 2
    fi

    # Diffstat scope depends on how the executor committed:
    #   clean start  → diff vs baseline SHA (captures committed + uncommitted)
    #   new commits  → range diff (committed changes only)
    #   fallback     → diff vs HEAD (uncommitted only)
    if [[ "$INITIAL_GIT_DIRTY" != "true" && -n "$PRE_EXECUTE_SHA" ]]; then
      git -C "$WORKDIR" diff --stat "$PRE_EXECUTE_SHA" > "$RUN_DIR/execute-diffstat.txt" || true
    elif [[ "$PRE_EXECUTE_SHA" != "$POST_EXECUTE_SHA" ]]; then
      git -C "$WORKDIR" diff --stat "${PRE_EXECUTE_SHA}..${POST_EXECUTE_SHA}" > "$RUN_DIR/execute-diffstat.txt" || true
    else
      git -C "$WORKDIR" diff --stat HEAD > "$RUN_DIR/execute-diffstat.txt" || true
    fi
  fi

  return 0
}

run_verify_phase() {
  # FIX-WR-03: accept phase start timestamp explicitly (see run_compose_phase comment).
  local phase_start="${1:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local verifier
  local diff_file="$RUN_DIR/verify-diff.txt"
  local diff_stat_file="$RUN_DIR/verify-diffstat.txt"
  local review_prompt_file="$RUN_DIR/.review-prompt.md"
  local review_stderr_file="$RUN_DIR/review-stderr.log"
  local verdict_file="$RUN_DIR/verdict.json"
  local normalized_verdict_file="$RUN_DIR/.verdict-normalized.json"
  local plan_content
  local diff_content
  local diff_stat
  local review_prompt
  local review_status=""
  local verdict_data=""
  local untracked_files=""

  if [[ "$IN_GIT" != "true" ]]; then
    log "WARNING: verification skipped - workdir is not a git repo."
    return 0
  fi

  if [[ "$INITIAL_GIT_DIRTY" == "true" ]]; then
    log "WARNING: verification skipped - workdir had pre-existing uncommitted changes, so this run's diff cannot be isolated."
    return 2
  fi

  untracked_files=$(git -C "$WORKDIR" ls-files --others --exclude-standard)
  if [[ -n "$untracked_files" ]]; then
    log "WARNING: verification skipped - run left untracked files that cannot be diffed automatically."
    return 2
  fi

  if [[ -n "$PRE_EXECUTE_SHA" ]]; then
    git -C "$WORKDIR" diff "$PRE_EXECUTE_SHA" > "$diff_file"
    git -C "$WORKDIR" diff --stat "$PRE_EXECUTE_SHA" > "$diff_stat_file"
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
  # v1.5: layer the verifier seat's model/effort, AFTER the verifier agent is
  # resolved (the seat env keys off the agent type). Covers both the codex-schema
  # and opus branches below. No-op when no per-seat env is set.
  apply_seat_env verifier "$verifier"

  plan_content=$(cat "$PLAN_PATH")
  diff_content=$(cat "$diff_file")
  diff_stat=$(cat "$diff_stat_file")
  review_prompt=$(build_review_prompt "$verifier" "$plan_content" "$diff_content" "$diff_stat")
  write_text_file "$review_prompt_file" "$review_prompt"

  # RTUX-01: Single live-tail window covers both codex and opus verifier branches.
  maybe_launch_live_window "verify" "$review_stderr_file"

  if [[ "$verifier" == "codex" ]]; then
    # Codex verify uses --output-schema (JSON verdict). This path intentionally
    # bypasses invoke_agent because invoke_codex_schema has distinct semantics
    # (schema-bound output file). RNPT-01 scopes the dispatcher to free-text phases.
    # RNPT-05: wrap invoke_codex_schema in timeout too — hang protection applies.
    local _verify_cmd_start
    _verify_cmd_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # FIX-WR-01: reset before the conditional so that a successful run leaves 0
    # (the `|| LAST_INVOKE_EXIT_CODE=$?` branch only fires on non-zero exit).
    LAST_INVOKE_EXIT_CODE=0
    if command -v timeout >/dev/null 2>&1; then
      timeout --foreground "${PHASE_TIMEOUT:-1800}s" \
        bash -c 'cd "$1" && source "$2/lib/co-evolution.sh"; invoke_codex_schema "$3" "$4" "$5" "$6"' _ \
        "$PWD" "$REPO_ROOT" "$review_prompt_file" "$verdict_file" "$review_stderr_file" "${REPO_ROOT}/skills/dev-review/schemas/review-verdict.json" \
        || LAST_INVOKE_EXIT_CODE=$?
    else
      invoke_codex_schema "$review_prompt_file" "$verdict_file" "$review_stderr_file" "${REPO_ROOT}/skills/dev-review/schemas/review-verdict.json"
    fi
    abort_on_timeout "verify" "$phase_start"
  else
    invoke_agent_with_timeout "$verifier" "$review_prompt_file" "$verdict_file" "$review_stderr_file" "$(phase_is_writable review)"
    abort_on_timeout "verify" "$phase_start"
  fi

  if agent_auth_failed "$verifier" "$verdict_file" "$review_stderr_file"; then
    return 2
  fi

  if file_contains_error_payload "$review_stderr_file"; then
    log "WARNING: verifier returned an error payload. Review manually."
    return 2
  fi

  if [[ ! -s "$verdict_file" ]]; then
    log "WARNING: verifier did not return a verdict. Review manually."
    return 2
  fi

  if ! verdict_data=$(normalize_json_artifact "$verdict_file" "$normalized_verdict_file"); then
    # v1.5: claude verifiers (no --output-schema) sometimes wrap the verdict in
    # prose, which normalize_json_artifact rejects. Try a brace-block extraction
    # (same idiom as evals/judge-bounce.sh:149) before giving up. codex verdicts
    # come from --output-schema and never hit this branch (they normalize clean).
    sed -n '/^{/,/^}/p' "$verdict_file" > "$normalized_verdict_file"
    if [[ ! -s "$normalized_verdict_file" ]]; then
      log "WARNING: verifier output was unusable: ${verdict_data}. Review manually."
      return 2
    fi
  fi

  verdict_data=$(validate_review_verdict "$normalized_verdict_file") || {
    log "WARNING: verifier output was unusable: ${verdict_data}. Review manually."
    return 2
  }

  # v1.5: persist the normalized verdict back to the contract path so downstream
  # consumers (evals/score-run.sh jq-parses verdict.json raw; mapping unparseable
  # -> FAIL) read clean JSON. Byte-no-op for codex --output-schema verdicts, which
  # are already clean. The dot-prefixed .verdict-normalized.json copy stays for the
  # revise-loop read; cleanup_runtime_artifacts sweeps it but verdict.json (plain
  # path, no leading dot) survives as the contract artifact.
  cp "$normalized_verdict_file" "$verdict_file"

  eval "$verdict_data"

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
    --preset)
      # v1.5: expand a named seat preset. Applied in-parser so flags placed
      # AFTER --preset override it (last-wins) and pre-set model/effort env vars
      # win over the preset's fill-if-empty defaults. See apply_preset().
      [[ $# -gt 1 ]] || die "--preset requires a value"
      PRESET="$2"
      apply_preset "$2"
      shift 2
      ;;
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
      # v1.5 (fixes B1): export so the `bash -c` child inside
      # invoke_agent_with_timeout inherits it (mirrors the --timeout arm). Without
      # export, CODEX_MODEL never reached invoke_codex in the dispatched child.
      export CODEX_MODEL="$2"
      shift 2
      ;;
    --verifier)
      [[ $# -gt 1 ]] || die "--verifier requires a value"
      # v1.5: normalize so `claude` maps to the opus seat name the rest of the
      # script uses; reject anything normalize_agent doesn't accept.
      VERIFIER_OVERRIDE=$(normalize_agent "$2") || die "Unsupported verifier: $2"
      shift 2
      ;;
    --claude-model)
      [[ $# -gt 1 ]] || die "--claude-model requires a value"
      # v1.5: resolve friendly alias (fable -> claude-fable-5) else passthrough.
      CLAUDE_MODEL=$(resolve_claude_model_alias "$2")
      shift 2
      ;;
    --workdir)
      [[ $# -gt 1 ]] || die "--workdir requires a value"
      WORKDIR="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -gt 1 ]] || die "--timeout requires a value"
      if ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" == "0" ]]; then
        die "--timeout value must be a positive integer (got: $2)"
      fi
      # export so bash -c subshell inside invoke_agent_with_timeout inherits it
      export PHASE_TIMEOUT="$2"
      shift 2
      ;;
    --revise-loop)
      # RTUX-03: Extra REVISE retry passes. 0 allowed (disabled). Mirror --timeout's
      # integer validation but permit zero, since zero is the documented "off" value.
      [[ $# -gt 1 ]] || die "--revise-loop requires a value"
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        die "--revise-loop value must be a non-negative integer (got: $2)"
      fi
      REVISE_LOOP_MAX="$2"
      shift 2
      ;;
    --live)
      # RTUX-01: Enable live mode — visible Windows terminal per wrapped phase.
      # Boolean flag; CLI presence wins over env. Default off = v1.1 byte-parity.
      LIVE_MODE=true
      shift
      ;;
    --branch)
      # RTUX-02: Branch spec — `auto` derives `dev-review/auto-<ts>-<slug>`, or
      # use NAME verbatim. Empty string allowed (no-op + WARNING from helper).
      [[ $# -gt 1 ]] || die "--branch requires a value"
      BRANCH_SPEC="$2"
      shift 2
      ;;
    --worktree)
      # RTUX-02: Worktree spec — `auto` derives `<parent>/<base>-dr-<ts>`, or
      # use PATH verbatim. Empty string allowed (no-op + WARNING from helper).
      [[ $# -gt 1 ]] || die "--worktree requires a value"
      WORKTREE_SPEC="$2"
      shift 2
      ;;
    --parent-run)
      # v1.5 Phase 3: orchestration lineage. Validate as a safe filesystem-ish
      # token (alnum, _, -, .) so a malicious id can't traverse paths or inject
      # shell-meta when echoed downstream (mirrors validate_lab_mode's posture,
      # plus '.' since run ids carry dotted timestamps). Lineage only — no
      # behavior change beyond the state.orchestration.parent_run_id write.
      [[ $# -gt 1 ]] || die "--parent-run requires a value"
      if ! [[ "$2" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "${#2}" -gt 128 ]]; then
        die "--parent-run must be a safe token [A-Za-z0-9._-]{1,128} (got: $2)"
      fi
      PARENT_RUN_ID="$2"
      shift 2
      ;;
    --lab)
      # Phase 3 LAB-01: opt-in routing to lab/<MODE>/entry.sh.
      # Arm sits BEFORE the `--` argv-terminator so args after `--` remain
      # positional (T-03-02-04 argv-position invariant).
      [[ $# -gt 1 ]] || die "--lab requires a mode"
      LAB_MODE="$2"
      shift 2
      ;;
    --target)
      [[ $# -gt 1 ]] || die "--target requires a value"
      TARGET="$2"
      shift 2
      ;;
    --tier)
      [[ $# -gt 1 ]] || die "--tier requires a value"
      case "$2" in
        template|policy|code) TIER="$2" ;;
        *) die "--tier must be template|policy|code (got: $2)" ;;
      esac
      shift 2
      ;;
    --pr-branch)
      [[ $# -gt 1 ]] || die "--pr-branch requires a value"
      PR_BRANCH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --budget)
      [[ $# -gt 1 ]] || die "--budget requires a value"
      [[ "$2" =~ ^[0-9]+$ ]] || die "--budget must be a positive integer (got: $2)"
      BUDGET_USD="$2"
      shift 2
      ;;
    --yes)
      AUTO_YES=true
      shift
      ;;
    --flavor)
      [[ $# -gt 1 ]] || die "--flavor requires a value"
      case "$2" in
        bug-catcher|faster-converger|blind-spot-surfacer|general) FLAVOR_OVERRIDE="$2" ;;
        *) die "--flavor must be one of bug-catcher|faster-converger|blind-spot-surfacer|general (got: $2)" ;;
      esac
      shift 2
      ;;
    --run-dir)
      [[ $# -gt 1 ]] || die "--run-dir requires a value"
      # Path-traversal guard — no '..' anywhere. Harness-side already sanitizes per
      # evals/run-evals.sh path policy; this is defense in depth.
      [[ "$2" != *..* ]] || die "--run-dir must not contain '..': $2"
      RUN_DIR_OVERRIDE="$2"
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

# RTUX-02: Branch and worktree are mutually exclusive — enforce BEFORE any
# side effect (RUN_DIR creation, state.json init, git ops). Fails fast with die.
if [[ -n "$BRANCH_SPEC" && -n "$WORKTREE_SPEC" ]]; then
  die "--branch and --worktree are mutually exclusive"
fi

# Phase 3 LAB-01: opt-in lab routing. Dispatch BEFORE any side effects
# (RUN_DIR creation, git ops, agent-CLI require checks). Byte-parity
# invariant (L-03): LAB_MODE empty → no-op. L-04: unknown-mode fail-fast
# is handled inside dispatch_lab_mode.
#
# Argv contract (v1.2, W-3): "$TASK" here is the concatenated task string
# produced by the existing parser. Lab inhabitants receive it as a
# single argv slot — i.e. entry.sh's $1 is the whole task string.
# See lab/README.md §How-to-add for the v1.2 contract. If a lab inhabitant
# needs multi-slot argv, it must split $1 itself.
# Phase 8: when routing to pel-proposer, rebuild argv from the parsed
# flag variables so the emitter sees them. For other lab modes, preserve
# Phase 3 behavior (pass $TASK as sole trailing arg).
if [[ "$LAB_MODE" == "pel-proposer" ]]; then
  # IN-04: $TARGET is forwarded verbatim. The pr-emitter requires a
  # repo-relative forward-slash path (matches allowlist.txt format). WSL users
  # passing `C:\...` paths will fail the allowlist check downstream — that's
  # the documented contract (see --target help text above).
  lab_tail=()
  [[ -n "$TARGET" ]] && lab_tail+=("--target" "$TARGET")
  [[ -n "$TIER" ]] && lab_tail+=("--tier" "$TIER")
  [[ -n "$PR_BRANCH" ]] && lab_tail+=("--pr-branch" "$PR_BRANCH")
  [[ "$DRY_RUN" == "true" ]] && lab_tail+=("--dry-run")
  [[ "$BUDGET_USD" != "25" ]] && lab_tail+=("--budget" "$BUDGET_USD")
  [[ "$AUTO_YES" == "true" ]] && lab_tail+=("--yes")
  [[ -n "$FLAVOR_OVERRIDE" ]] && lab_tail+=("--flavor" "$FLAVOR_OVERRIDE")
  [[ -n "$TASK" ]] && lab_tail+=("--" "$TASK")
  # REPO_ROOT is set at the top of this script (line 6); lab/ is at repo root.
  dispatch_lab_mode "$LAB_MODE" "$REPO_ROOT/lab" "${lab_tail[@]}"
  # dispatch_lab_mode exec's — unreachable on success.
elif [[ -n "$LAB_MODE" ]]; then
  # REPO_ROOT is set at the top of this script (line 6); lab/ is at repo root.
  dispatch_lab_mode "$LAB_MODE" "$REPO_ROOT/lab" "$TASK"
  # dispatch_lab_mode exec's — unreachable on success.
fi

WORKDIR=$(normalize_path_for_bash "$WORKDIR")
if [[ -n "$PLAN_SOURCE" ]]; then
  PLAN_SOURCE=$(normalize_path_for_bash "$PLAN_SOURCE")
fi

WORKDIR="$(cd "$WORKDIR" && pwd)"
# v1.5 (fixes B3): export WORKDIR so the `bash -c` child inside
# invoke_agent_with_timeout (and the verify-codex `bash -c` block) inherits it;
# otherwise ${WORKDIR:-$PWD} in invoke_claude/invoke_codex falls back to the
# child's launch cwd. The export attribute persists across the later worktree-mode
# reassignment of WORKDIR (~line 1300), so the worktree path is exported too.
export WORKDIR

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

# v1.5 per-seat env layer. Snapshot the post-parse base model/effort values (set
# by globals / --model / --claude-model / CLAUDE_EFFORT / CODEX_REASONING_EFFORT),
# then apply_seat_env layers an optional per-seat override before each invocation.
# Byte-parity: with no COMPOSER_/EXECUTOR_/VERIFIER_ envs set, every seat resolves
# to its base, so exported CLAUDE_MODEL/CLAUDE_EFFORT/CODEX_MODEL/CODEX_REASONING_EFFORT
# match what the unlayered globals already were — argv is unchanged.
CLAUDE_MODEL_BASE="$CLAUDE_MODEL"; CODEX_MODEL_BASE="${CODEX_MODEL:-}"
CLAUDE_EFFORT_BASE="${CLAUDE_EFFORT:-}"; CODEX_EFFORT_BASE="${CODEX_REASONING_EFFORT:-}"

# Export is load-bearing: invoke_agent_with_timeout crosses a `timeout bash -c`
# process boundary; only exported values survive it.
apply_seat_env() {
  local seat="$1" agent="$2" model="" effort=""
  case "$seat" in
    composer) model="${COMPOSER_MODEL:-}"; effort="${COMPOSER_EFFORT:-}" ;;
    executor) model="${EXECUTOR_MODEL:-}"; effort="${EXECUTOR_EFFORT:-}" ;;
    verifier) model="${VERIFIER_MODEL:-}"; effort="${VERIFIER_EFFORT:-}" ;;
    *) : ;;  # bounce counterparty: globals only
  esac
  if [[ "$agent" == "codex" ]]; then
    export CODEX_MODEL="${model:-$CODEX_MODEL_BASE}"
    export CODEX_REASONING_EFFORT="${effort:-$CODEX_EFFORT_BASE}"
  else
    export CLAUDE_MODEL="$(resolve_claude_model_alias "${model:-$CLAUDE_MODEL_BASE}")"
    export CLAUDE_EFFORT="${effort:-$CLAUDE_EFFORT_BASE}"
  fi
}

# v1.5: resolve a seat's "agent:model@effort" descriptor using the SAME model/
# effort precedence apply_seat_env uses, but without mutating the exported env.
# Feeds the startup banner and the optional state.json seat_models fields.
# model defaults to "(default)" when unpinned (codex's executor seat under the
# codex-build preset); effort defaults to "(default)" when no effort is set.
resolve_seat_model_string() {
  local seat="$1" agent="$2" model="" effort="" model_str="" effort_str=""
  case "$seat" in
    composer) model="${COMPOSER_MODEL:-}"; effort="${COMPOSER_EFFORT:-}" ;;
    executor) model="${EXECUTOR_MODEL:-}"; effort="${EXECUTOR_EFFORT:-}" ;;
    verifier) model="${VERIFIER_MODEL:-}"; effort="${VERIFIER_EFFORT:-}" ;;
    *) : ;;
  esac
  if [[ "$agent" == "codex" ]]; then
    model_str="${model:-$CODEX_MODEL_BASE}"
    effort_str="${effort:-$CODEX_EFFORT_BASE}"
  else
    model_str="$(resolve_claude_model_alias "${model:-$CLAUDE_MODEL_BASE}")"
    effort_str="${effort:-$CLAUDE_EFFORT_BASE}"
  fi
  printf '%s:%s@%s' "$agent" "${model_str:-(default)}" "${effort_str:-(default)}"
}

# Phase 8.1 WR-04: honor --run-dir when set; otherwise preserve v1.2 default (byte-parity).
if [[ -n "$RUN_DIR_OVERRIDE" ]]; then
  RUN_DIR="$RUN_DIR_OVERRIDE"
else
  RUN_DIR="${REPO_ROOT}/runs/dev-review-${TIMESTAMP}"
fi
mkdir -p "$RUN_DIR"
mkdir -p "$RUN_DIR/outputs"
PLAN_PATH="${RUN_DIR}/plan.md"
LOG_FILE="${RUN_DIR}/run.log"

# RNPT-03/04: state.json lifecycle — permanent per-run record + intermediate
# hash manifests used for delta tracking. Dot-prefixed intermediates are swept
# by cleanup_runtime_artifacts; state.json itself has no leading dot and
# survives cleanup as the permanent ground-truth record.
STATE_JSON="${RUN_DIR}/state.json"
BASELINE_HASHES_JSON="${RUN_DIR}/.baseline-hashes.json"
CURRENT_HASHES_JSON="${RUN_DIR}/.current-hashes.json"
EXECUTE_DELTA_JSON="${RUN_DIR}/.execute-delta.json"
RUN_ID="dev-review-${TIMESTAMP}"
init_state_json "$STATE_JSON" "$RUN_ID" "$TASK" "$COMPOSER" "$EXECUTOR" "$REVIEWER"

# v1.5 Phase 3: observability — record the runner's PID once so a status reader
# can probe liveness via `kill -0`. Written as a number (jq accepts $$ verbatim).
write_state_field "$STATE_JSON" ".runner_pid" "number" "$$"

# v1.5 Phase 3: lineage — when this run was re-kicked by an orchestrator under a
# parent run, record the parent's id (validated at parse time). Lineage only;
# no other behavior. Omitted (left absent) when --parent-run was not passed.
if [[ -n "$PARENT_RUN_ID" ]]; then
  write_state_field "$STATE_JSON" ".orchestration.parent_run_id" "string" "$PARENT_RUN_ID"
fi

# v1.5: resolve the verifier seat and per-seat model/effort descriptors for the
# banner + observability fields. _VERIFIER_SEAT reflects --verifier / executor
# derivation (select_verifier); the seat strings reflect whatever the seats
# resolve to under the per-seat env layer (apply_seat_env precedence).
_VERIFIER_SEAT=$(select_verifier)
_SEAT_COMPOSER=$(resolve_seat_model_string composer "$COMPOSER")
_SEAT_EXECUTOR=$(resolve_seat_model_string executor "$EXECUTOR")
_SEAT_VERIFIER=$(resolve_seat_model_string verifier "$_VERIFIER_SEAT")

# v1.5: optional seat_models observability — records what each seat resolves to.
# Unconditional + additive (no existing sim asserts an exact state.json key set,
# so this does not break shape); cheap, and reflects the actual resolved seats.
write_state_field "$STATE_JSON" ".seat_models.composer" "string" "$_SEAT_COMPOSER"
write_state_field "$STATE_JSON" ".seat_models.executor" "string" "$_SEAT_EXECUTOR"
write_state_field "$STATE_JSON" ".seat_models.verifier" "string" "$_SEAT_VERIFIER"

log "============================================"
log " DEV-REVIEW SESSION"
log "============================================"
log " Task:      $TASK"
log " Preset:    ${PRESET:-<none>}"
log " Composer:  $COMPOSER"
log " Executor:  $EXECUTOR"
log " Verifier:  $_VERIFIER_SEAT"
log " Bounces:   $BOUNCES"
log " Verify:    $VERIFY"
log " Workdir:   $WORKDIR"
log " Run dir:   $RUN_DIR"
log " Timeout:   ${PHASE_TIMEOUT}s per phase"
log " Live mode: $LIVE_MODE"
log " Branch:    ${BRANCH_SPEC:-<empty>}"
log " Worktree:  ${WORKTREE_SPEC:-<empty>}"
log " Composer model: $_SEAT_COMPOSER"
log " Executor model: $_SEAT_EXECUTOR"
log " Verifier model: $_SEAT_VERIFIER"
log "============================================"
log ""

if [[ "$SKIP_PLAN" == "true" ]]; then
  cp "$PLAN_SOURCE" "$PLAN_PATH"
else
  PLAN_EXIT=0

  # RNPT-04: wrap compose with phase timing + state.json record.
  # FIX-WR-03: pass phase start timestamp explicitly (was previously read via
  # enclosing-scope global _compose_phase_start — hidden coupling removed).
  _compose_phase_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  run_compose_phase "$_compose_phase_start" || PLAN_EXIT=$?
  _phase_end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  _phase_status=$([[ "${PLAN_EXIT:-0}" -eq 0 ]] && echo "ok" || echo "error")
  write_state_phase "$STATE_JSON" "compose" "$_phase_status" "${PLAN_EXIT:-0}" "$_compose_phase_start" "$_phase_end"

  if [[ "$PLAN_EXIT" -eq 0 ]]; then
    # RNPT-04: bounce — per-pass entries written from inside run_bounce_phase.
    _phase_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    run_bounce_phase "$MAX_BOUNCES" "$AUTO_CONVERGE" || PLAN_EXIT=$?
    _phase_end=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update marker counts in state.json (from the final plan).
    if [[ -s "$PLAN_PATH" ]]; then
      _contested=$(count_markers "$PLAN_PATH" "[CONTESTED]")
      _clarify=$(count_markers "$PLAN_PATH" "[CLARIFY]")
      write_state_field "$STATE_JSON" ".marker_counts.contested" "number" "${_contested:-0}"
      write_state_field "$STATE_JSON" ".marker_counts.clarify"   "number" "${_clarify:-0}"
    fi
  fi
fi

if [[ "$PLAN_ONLY" == "true" ]]; then
  if [[ -s "$PLAN_PATH" ]]; then
    if [[ "${PLAN_EXIT:-0}" -eq 0 ]]; then
      log "Plan saved to: $PLAN_PATH"
    else
      log "Latest valid plan saved to: $PLAN_PATH"
    fi
  fi
  # RNPT-04: record completion even on plan-only exit so Phase 8 eval sees a
  # terminated run rather than one that looks crashed mid-phase.
  write_state_field "$STATE_JSON" ".completed_at" "string" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # v1.5 Phase 3: plan-only runs also reach a clean terminal — clear the in-flight
  # phase so a status reader does not see a stale compose/bounce as "still running".
  write_state_field "$STATE_JSON" ".current_phase" "null"
  cleanup_runtime_artifacts
  if [[ "${PLAN_EXIT:-0}" -eq 2 ]]; then
    exit 2
  fi
  if [[ "${PLAN_EXIT:-0}" -ne 0 ]]; then
    exit 1
  fi
  exit 0
fi

# RTUX-02: Branch / worktree setup. Runs AFTER plan+bounce land on the parent
# branch (so plan artifacts stay reviewable pre-merge) and BEFORE execute.
# PLAN_ONLY exits earlier (above) and never reaches this block — by design,
# `--branch auto --plan-only` is a silent no-op on the branching side because
# plan artifacts intentionally stay on the parent branch.
# Mutually exclusive: parser already rejected both-set; only one path fires.
if [[ -n "$BRANCH_SPEC" ]]; then
  BRANCH_CREATED=$(maybe_setup_branch "$WORKDIR" "$BRANCH_SPEC" "$TASK")
  if [[ -n "$BRANCH_CREATED" ]]; then
    write_state_field "$STATE_JSON" ".branch_created" "string" "$BRANCH_CREATED"
  fi
elif [[ -n "$WORKTREE_SPEC" ]]; then
  _new_wt=$(maybe_setup_worktree "$WORKDIR" "$WORKTREE_SPEC" "$TASK")
  if [[ -n "$_new_wt" ]]; then
    WORKTREE_PATH="$_new_wt"
    WORKDIR="$_new_wt"   # execute/verify phases now operate inside the worktree
    write_state_field "$STATE_JSON" ".worktree_path" "string" "$WORKTREE_PATH"
  fi
  unset _new_wt
fi

# FIX-WR-04: Capture WORKDIR's git state AFTER any --worktree reassignment
# above so worktree mode sees the worktree's status, not the parent repo's.
# Previously this block ran BEFORE the worktree reassignment — a dirty parent
# + clean worktree would make verify silently skip even though the worktree
# was actually fine. Moved here so execute/verify see the real workdir state.
if git -C "$WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=true
  INITIAL_GIT_STATUS=$(git -C "$WORKDIR" status --short)
  if [[ -n "$INITIAL_GIT_STATUS" ]]; then
    INITIAL_GIT_DIRTY=true
  fi
fi

# RTUX-03: REVISE auto-loop. Default REVISE_LOOP_MAX=0 runs exactly one pass
# with bare "execute"/"verify" phase names — byte-identical to v1.0 behavior.
# N>=1 allows up to N additional passes on a REVISE verdict, each recorded as
# "execute-2"/"verify-2" etc. The loop body is extracted into _run_revise_loop
# so tests/revise-loop-simulation.sh can exercise the same implementation.
if [[ "$REVISE_LOOP_MAX" -gt 0 ]]; then
  log "REVISE auto-loop enabled: up to $REVISE_LOOP_MAX extra pass(es) on REVISE verdict"
fi

EXECUTE_EXIT=0
VERIFY_EXIT=0

_run_revise_loop() {
  local current_pass=1
  local max_pass=$((REVISE_LOOP_MAX + 1))
  local exec_name verify_name
  local _execute_phase_start _verify_phase_start _phase_end _phase_status

  while [[ "$current_pass" -le "$max_pass" ]]; do
    # Phase names: pass 1 uses bare "execute"/"verify" for backwards compat;
    # pass 2+ uses "execute-N"/"verify-N" (N = current_pass). Matches the
    # ^execute-[0-9]+$ gate in phase_is_writable so retry passes remain writable.
    if [[ "$current_pass" -eq 1 ]]; then
      exec_name="execute"
      verify_name="verify"
    else
      exec_name="execute-${current_pass}"
      verify_name="verify-${current_pass}"
    fi

    # ---- execute ----
    if [[ "${PLAN_EXIT:-0}" -ne 0 ]]; then
      EXECUTE_EXIT="${PLAN_EXIT:-0}"
      return 0
    fi

    # RTUX-03: Feedback handshake with Task 3's build_execution_prompt. On pass 1
    # REVISE_FEEDBACK_JSON must be unset so the conditional block is stripped and
    # the prompt is byte-identical to v1.0. On pass 2+ it carries the prior verdict.
    if [[ "$current_pass" -gt 1 ]]; then
      export REVISE_FEEDBACK_JSON="${REVISE_FEEDBACK_JSON:-}"
    else
      unset REVISE_FEEDBACK_JSON
    fi

    _execute_phase_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    EXECUTE_EXIT=0
    # v1.5 Phase 3: mark execute (or execute-N on a revise pass) as STARTING,
    # using the same name write_state_phase records on completion below.
    begin_state_phase "$STATE_JSON" "$exec_name"
    run_execute_phase "$_execute_phase_start" || EXECUTE_EXIT=$?
    _phase_end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _phase_status=$([[ "$EXECUTE_EXIT" -eq 0 ]] && echo "ok" || echo "error")
    write_state_phase "$STATE_JSON" "$exec_name" "$_phase_status" "$EXECUTE_EXIT" "$_execute_phase_start" "$_phase_end"
    [[ "$EXECUTE_EXIT" -ne 0 ]] && return 0

    # ---- verify (only when requested) ----
    if [[ "$VERIFY" != "true" ]]; then
      return 0
    fi
    _verify_phase_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    VERIFY_EXIT=0
    # Clear prior verdict globals so a hung/empty verify pass can't leak them.
    unset VERDICT CONFIDENCE SUMMARY
    # v1.5 Phase 3: mark verify (or verify-N on a revise pass) as STARTING.
    begin_state_phase "$STATE_JSON" "$verify_name"
    run_verify_phase "$_verify_phase_start" || VERIFY_EXIT=$?
    _phase_end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _phase_status=$([[ "$VERIFY_EXIT" -eq 0 ]] && echo "ok" || echo "error")
    write_state_phase "$STATE_JSON" "$verify_name" "$_phase_status" "$VERIFY_EXIT" "$_verify_phase_start" "$_phase_end"
    if [[ -n "${VERDICT:-}" ]]; then
      write_state_field "$STATE_JSON" ".verify_verdict" "string" "$VERDICT"
    fi

    # ---- loop decision ----
    # APPROVED (VERIFY_EXIT=0) → done.
    # REVISE (VERIFY_EXIT=2, VERDICT=REVISE, budget remaining) → retry.
    # Anything else (auth/timeout/empty/not-a-git-repo) → non-retryable, exit.
    if [[ "$VERIFY_EXIT" -eq 0 ]]; then
      return 0
    fi
    if [[ "$VERIFY_EXIT" -eq 2 && "${VERDICT:-}" == "REVISE" && "$current_pass" -lt "$max_pass" ]]; then
      # T-02-06 mitigation: capture verdict JSON into memory BEFORE the retry
      # loop advances. cleanup_runtime_artifacts only runs after _run_revise_loop
      # returns, but being explicit here removes any TOCTOU ambiguity.
      REVISE_FEEDBACK_JSON=$(cat "$RUN_DIR/.verdict-normalized.json" 2>/dev/null || printf '%s' '{}')
      export REVISE_FEEDBACK_JSON
      current_pass=$((current_pass + 1))
      continue
    fi
    return 0
  done
}

_run_revise_loop
unset REVISE_FEEDBACK_JSON

# Phase 8.1 WR-01 / D-02: derive terminal .status from exit bands (mirrors the
# final-exit switch at lines 1420-1428). Values per evals/RUNNER-CONTRACT.md §1.
if [[ "$EXECUTE_EXIT" -eq 0 && "$VERIFY_EXIT" -eq 0 ]]; then
  _run_status="completed"
elif [[ "$EXECUTE_EXIT" -eq 2 || "$VERIFY_EXIT" -eq 2 ]]; then
  _run_status="partial"
else
  _run_status="failed"
fi

# Shared end-of-run ISO8601 timestamp — reused for both .completed_at and .updated_at
# so the scorer's wall-clock calc (score-run.sh:261) reads a consistent value.
_run_end_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_state_field "$STATE_JSON" ".status"       "string" "$_run_status"
# RNPT-04: run completion timestamp (before cleanup sweeps transient dotfiles).
write_state_field "$STATE_JSON" ".completed_at" "string" "$_run_end_ts"
# Phase 8.1 WR-02 supporting: .updated_at feeds Cost dimension (score-run.sh:261).
write_state_field "$STATE_JSON" ".updated_at"   "string" "$_run_end_ts"
# v1.5 Phase 3: the run reached EOF — no phase is in flight. The status reader
# treats a non-null .current_phase on a non-terminal run as "still in <phase>";
# clearing it here is the in-band "phases done" signal.
write_state_field "$STATE_JSON" ".current_phase" "null"

# Phase 8.1 / D-01: mirror phases[] into history[] (canonical contract name).
# Field-rename transition posture — phases[] stays as legacy alias for one
# minor version; scorer's .history[] reads (score-run.sh:338) get populated.
if command -v jq >/dev/null 2>&1; then
  _tmp_history=$(mktemp)
  if jq '.history = (.phases | map({phase: .name, status: .status, detail: "", timestamp: .completed_at}))' \
       "$STATE_JSON" > "$_tmp_history"; then
    mv "$_tmp_history" "$STATE_JSON"
  else
    rm -f "$_tmp_history"
    log "WARNING: jq failed mirroring phases -> history — state.json unchanged (.history will read as [])"
  fi
  unset _tmp_history
fi
unset _run_status _run_end_ts

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
log " Branch:    ${BRANCH_CREATED:-<none>}"
log " Worktree:  ${WORKTREE_PATH:-<none>}"
log "============================================"

if [[ "$EXECUTE_EXIT" -eq 2 || "$VERIFY_EXIT" -eq 2 ]]; then
  exit 2
fi

if [[ "$EXECUTE_EXIT" -ne 0 || "$VERIFY_EXIT" -ne 0 ]]; then
  exit 1
fi

exit 0
