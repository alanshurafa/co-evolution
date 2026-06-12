#!/usr/bin/env bash
# dev-review/codex/dev-review-status.sh
# v1.5 Phase 3 — read-only status reader for dev-review runner runs.
#
# A Claude Code session kicks the runner via a background Bash task and ENDS
# ITS TURN. On wake (or via a cheap watcher, or a human) it must reconstruct
# run state purely from disk. This script does exactly that — it writes NOTHING
# and never touches the runner. It reports run summary, phase progress, a
# heartbeat derived from the in-flight phase's stderr-log mtime/size, marker
# counts, verdict, diffstat, and a liveness assessment with an actionable line.
#
# Usage:
#   dev-review-status.sh [--json] [--list] [RUN_ID|RUN_DIR]
#     (no positional)  → latest runs/dev-review-* by mtime
#     --list           → one summary line per non-terminal run + 3 newest terminal
#     RUN_ID           → resolved against <repo>/runs/RUN_ID
#     RUN_DIR          → an absolute/relative dir path, used as-is
#
# Exit codes (liveness assessment):
#   0  terminal-completed   (status=completed)
#   2  terminal-partial     (status=partial/failed)
#   5  still-running        (non-terminal + pid alive OR heartbeat fresh <120s)
#   4  presumed-dead        (non-terminal + pid gone + heartbeat stale)
#   3  run not found / no state.json / bad argument
#
# Reader, not runner: requires jq and dies (exit 3) without it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root: dev-review/codex/ -> repo (two levels up).
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNS_DIR="${CO_EVOLVE_RUNS_DIR:-$REPO_ROOT/runs}"

HEARTBEAT_FRESH_SECS=120

die() { printf 'dev-review-status: %s\n' "$1" >&2; exit 3; }

command -v jq >/dev/null 2>&1 || die "jq is required (this is a reader, not the runner)"

# --- portable file mtime (epoch) --------------------------------------------
# Feature-detect GNU stat (supports --version) vs BSD stat, mirroring the
# GNU-find detection convention in lib/co-evolution.sh (list_available_lab_modes).
if stat --version >/dev/null 2>&1; then
  _file_mtime() { stat -c %Y "$1" 2>/dev/null; }   # GNU
else
  _file_mtime() { stat -f %m "$1" 2>/dev/null; }   # BSD/macOS
fi

now_epoch() { date +%s; }

# --- argument parsing --------------------------------------------------------
JSON=false
LIST=false
ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=true; shift ;;
    --list) LIST=true; shift ;;
    -h|--help)
      sed -n '5,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --*) die "unknown flag: $1" ;;
    *)   ARG="$1"; shift ;;
  esac
done

# --- run-dir resolution ------------------------------------------------------
# A value containing a slash (or that resolves to an existing dir) is a path;
# otherwise treat it as a RUN_ID under $RUNS_DIR.
resolve_run_dir() {
  local arg="$1"
  if [[ -z "$arg" ]]; then
    ls -dt "$RUNS_DIR"/dev-review-* 2>/dev/null | head -1
    return 0
  fi
  if [[ -d "$arg" ]]; then
    printf '%s' "$arg"
    return 0
  fi
  if [[ "$arg" == */* ]]; then
    # Looks like a path but does not exist.
    printf '%s' "$arg"
    return 0
  fi
  printf '%s' "$RUNS_DIR/$arg"
}

# --- map a phase name to its stderr-log path (heartbeat source) --------------
# Mirrors the exact filenames the runner writes:
#   compose      -> compose-stderr.log
#   bounce-NN    -> pass-N-stderr.log   (N un-padded; runner names the file with
#                                        the raw pass int, the phase with NN)
#   execute[-N]  -> execute-stderr.log  (reused across revise passes)
#   verify[-N]   -> review-stderr.log   (reused across revise passes)
phase_stderr_file() {
  local run_dir="$1" phase="$2"
  case "$phase" in
    compose)      printf '%s' "$run_dir/compose-stderr.log" ;;
    bounce-*)
      local nn="${phase#bounce-}"
      nn=$((10#$nn))   # strip leading zero: bounce-01 -> 1
      printf '%s' "$run_dir/pass-${nn}-stderr.log"
      ;;
    execute|execute-*) printf '%s' "$run_dir/execute-stderr.log" ;;
    verify|verify-*)   printf '%s' "$run_dir/review-stderr.log" ;;
    *) printf '' ;;
  esac
}

# --- one-line summary for --list ---------------------------------------------
summarize_one() {
  local run_dir="$1"
  local state="$run_dir/state.json"
  local id status phase
  id=$(jq -r '.run_id // "?"' "$state" 2>/dev/null)
  status=$(jq -r '.status // "null"' "$state" 2>/dev/null)
  phase=$(jq -r '.current_phase.name // "-"' "$state" 2>/dev/null)
  printf '%-32s  status=%-9s  phase=%s\n' "$id" "$status" "$phase"
}

if [[ "$LIST" == true ]]; then
  shopt -s nullglob
  dirs=("$RUNS_DIR"/dev-review-*)
  shopt -u nullglob
  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "(no dev-review runs under $RUNS_DIR)"
    exit 3
  fi
  # newest first. bash-3.2 portable (macOS /bin/bash has no mapfile); read the
  # ls -t output line by line into the array.
  sorted=()
  while IFS= read -r _d; do
    [[ -n "$_d" ]] && sorted+=("$_d")
  done < <(ls -dt "$RUNS_DIR"/dev-review-* 2>/dev/null)
  echo "ACTIVE (non-terminal: pending/null):"
  active_found=false
  for d in "${sorted[@]}"; do
    [[ -f "$d/state.json" ]] || continue
    st=$(jq -r '.status // "null"' "$d/state.json" 2>/dev/null)
    if [[ "$st" == "pending" || "$st" == "null" ]]; then
      summarize_one "$d"; active_found=true
    fi
  done
  [[ "$active_found" == false ]] && echo "  (none)"
  echo
  echo "RECENT (3 newest terminal):"
  shown=0
  for d in "${sorted[@]}"; do
    [[ -f "$d/state.json" ]] || continue
    st=$(jq -r '.status // "null"' "$d/state.json" 2>/dev/null)
    if [[ "$st" != "pending" && "$st" != "null" ]]; then
      summarize_one "$d"; shown=$((shown + 1))
      [[ "$shown" -ge 3 ]] && break
    fi
  done
  [[ "$shown" -eq 0 ]] && echo "  (none)"
  exit 0
fi

RUN_DIR=$(resolve_run_dir "$ARG")
[[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || die "run not found: ${ARG:-<latest>} (looked under $RUNS_DIR)"
STATE="$RUN_DIR/state.json"
[[ -f "$STATE" ]] || die "no state.json in $RUN_DIR"
jq -e . "$STATE" >/dev/null 2>&1 || die "state.json is not valid JSON: $STATE"

# --- read fields -------------------------------------------------------------
RUN_ID=$(jq -r '.run_id // "?"' "$STATE")
STATUS=$(jq -r '.status // "null"' "$STATE")
TASK=$(jq -r '.task // ""' "$STATE" | head -c 100)
RUNNER_PID=$(jq -r '.runner_pid // empty' "$STATE")
CUR_PHASE=$(jq -r '.current_phase.name // empty' "$STATE")
CUR_STARTED=$(jq -r '.current_phase.started_at // empty' "$STATE")
PARENT_RUN=$(jq -r '.orchestration.parent_run_id // empty' "$STATE")
VERDICT=$(jq -r '.verify_verdict // empty' "$STATE")
PRE_SHA=$(jq -r '.pre_execute_sha // empty' "$STATE")
POST_SHA=$(jq -r '.post_execute_sha // empty' "$STATE")
M_CONTESTED=$(jq -r '.marker_counts.contested // 0' "$STATE")
M_CLARIFY=$(jq -r '.marker_counts.clarify // 0' "$STATE")

# --- runner liveness via kill -0 ---------------------------------------------
# yes  = pid present and alive; no = pid present and gone; unknown = no pid.
RUNNER_ALIVE="unknown"
if [[ -n "$RUNNER_PID" ]]; then
  if kill -0 "$RUNNER_PID" 2>/dev/null; then
    RUNNER_ALIVE="yes"
  else
    RUNNER_ALIVE="no"
  fi
fi

# --- heartbeat from the in-flight phase's stderr log -------------------------
HB_AGE=""        # seconds since last write (empty if no current phase / no file)
HB_LINES=""      # line count of the stderr file
HB_FILE=""
if [[ -n "$CUR_PHASE" ]]; then
  HB_FILE=$(phase_stderr_file "$RUN_DIR" "$CUR_PHASE")
  if [[ -n "$HB_FILE" && -f "$HB_FILE" ]]; then
    mt=$(_file_mtime "$HB_FILE")
    if [[ -n "$mt" ]]; then
      HB_AGE=$(( $(now_epoch) - mt ))
    fi
    HB_LINES=$(wc -l < "$HB_FILE" | tr -d ' ')
  fi
fi

# --- liveness assessment + exit code -----------------------------------------
# Terminal states short-circuit. Non-terminal: alive pid OR fresh heartbeat
# => still-running; pid gone + stale/absent heartbeat => presumed-dead.
ASSESS=""
EXIT_CODE=0
case "$STATUS" in
  completed)
    ASSESS="DONE: run completed cleanly."
    EXIT_CODE=0
    ;;
  partial|failed)
    ASSESS="PARTIAL: run reached a terminal non-completed status ($STATUS) — review verdict/diffstat before acting."
    EXIT_CODE=2
    ;;
  *)
    # Non-terminal (pending / null / unexpected). Decide running vs dead.
    hb_fresh=false
    if [[ -n "$HB_AGE" && "$HB_AGE" -lt "$HEARTBEAT_FRESH_SECS" ]]; then
      hb_fresh=true
    fi
    if [[ "$RUNNER_ALIVE" == "yes" || "$hb_fresh" == true ]]; then
      ASSESS="RUNNING: runner alive ($RUNNER_ALIVE) / heartbeat ${HB_AGE:-?}s — in phase ${CUR_PHASE:-?}. Leave it; re-check on wake."
      EXIT_CODE=5
    else
      ASSESS="DEAD: runner gone mid-phase (${CUR_PHASE:-?}) — escalate or re-kick with --skip-plan --plan ${RUN_DIR}/plan.md"
      EXIT_CODE=4
    fi
    ;;
esac

# --- diffstat tail + execute stderr tail (paths) -----------------------------
DIFFSTAT_FILE="$RUN_DIR/execute-diffstat.txt"
EXEC_STDERR="$RUN_DIR/execute-stderr.log"
VERDICT_JSON="$RUN_DIR/verdict.json"

# ============================================================================
# JSON mode — one machine-readable object for the orchestrating skill.
# ============================================================================
if [[ "$JSON" == true ]]; then
  diffstat_tail=""
  [[ -f "$DIFFSTAT_FILE" ]] && diffstat_tail=$(tail -5 "$DIFFSTAT_FILE")
  exec_tail=""
  [[ -f "$EXEC_STDERR" ]] && exec_tail=$(tail -5 "$EXEC_STDERR")
  verdict_present=false
  [[ -f "$VERDICT_JSON" ]] && verdict_present=true

  jq -n \
    --arg run_id "$RUN_ID" \
    --arg run_dir "$RUN_DIR" \
    --arg status "$STATUS" \
    --arg task "$TASK" \
    --arg runner_pid "${RUNNER_PID:-}" \
    --arg runner_alive "$RUNNER_ALIVE" \
    --arg current_phase "${CUR_PHASE:-}" \
    --arg current_started "${CUR_STARTED:-}" \
    --arg heartbeat_age "${HB_AGE:-}" \
    --arg heartbeat_lines "${HB_LINES:-}" \
    --arg heartbeat_file "${HB_FILE:-}" \
    --arg parent_run "${PARENT_RUN:-}" \
    --arg verdict "${VERDICT:-}" \
    --arg verdict_json "$([[ -f "$VERDICT_JSON" ]] && printf '%s' "$VERDICT_JSON")" \
    --argjson verdict_present "$verdict_present" \
    --arg pre_sha "${PRE_SHA:-}" \
    --arg post_sha "${POST_SHA:-}" \
    --argjson contested "$M_CONTESTED" \
    --argjson clarify "$M_CLARIFY" \
    --arg diffstat_tail "$diffstat_tail" \
    --arg execute_stderr_tail "$exec_tail" \
    --arg assess "$ASSESS" \
    --argjson exit_code "$EXIT_CODE" \
    --slurpfile phases <(jq '.phases // []' "$STATE") \
    '{
      run_id: $run_id,
      run_dir: $run_dir,
      status: $status,
      task: $task,
      runner_pid: (if $runner_pid == "" then null else ($runner_pid|tonumber) end),
      runner_alive: $runner_alive,
      current_phase: (if $current_phase == "" then null else {name: $current_phase, started_at: $current_started} end),
      heartbeat: {
        age_secs: (if $heartbeat_age == "" then null else ($heartbeat_age|tonumber) end),
        lines: (if $heartbeat_lines == "" then null else ($heartbeat_lines|tonumber) end),
        file: (if $heartbeat_file == "" then null else $heartbeat_file end)
      },
      orchestration: {parent_run_id: (if $parent_run == "" then null else $parent_run end)},
      verdict: (if $verdict == "" then null else $verdict end),
      verdict_json: (if $verdict_json == "" then null else $verdict_json end),
      verdict_present: $verdict_present,
      pre_execute_sha: (if $pre_sha == "" then null else $pre_sha end),
      post_execute_sha: (if $post_sha == "" then null else $post_sha end),
      marker_counts: {contested: $contested, clarify: $clarify},
      phases: $phases[0],
      diffstat_tail: $diffstat_tail,
      execute_stderr_tail: $execute_stderr_tail,
      assess: $assess,
      exit_code: $exit_code
    }'
  exit "$EXIT_CODE"
fi

# ============================================================================
# Human mode.
# ============================================================================
printf '== dev-review run: %s ==\n' "$RUN_ID"
printf 'run dir:       %s\n' "$RUN_DIR"
printf 'status:        %s\n' "$STATUS"
printf 'runner pid:    %s (alive: %s)\n' "${RUNNER_PID:-<none>}" "$RUNNER_ALIVE"
[[ -n "$PARENT_RUN" ]] && printf 'parent run:    %s\n' "$PARENT_RUN"
printf 'task:          %s\n' "$TASK"

if [[ -n "$CUR_PHASE" ]]; then
  printf 'current phase: %s (started %s)\n' "$CUR_PHASE" "${CUR_STARTED:-?}"
  if [[ -n "$HB_AGE" ]]; then
    printf 'heartbeat:     %ss ago, %s lines (%s)\n' "$HB_AGE" "${HB_LINES:-0}" "$HB_FILE"
  else
    printf 'heartbeat:     (no stderr activity yet for %s)\n' "$CUR_PHASE"
  fi
else
  printf 'current phase: <none in flight>\n'
fi

# Completed phases table.
phase_rows=$(jq -r '.phases // [] | .[] | "  \(.name)\t\(.status)\texit=\(.exit_code)\t\(.completed_at // "")"' "$STATE" 2>/dev/null)
if [[ -n "$phase_rows" ]]; then
  printf 'phases:\n%s\n' "$phase_rows"
else
  printf 'phases:        (none recorded yet)\n'
fi

printf 'markers:       contested=%s clarify=%s\n' "$M_CONTESTED" "$M_CLARIFY"

if [[ -n "$PRE_SHA" || -n "$POST_SHA" ]]; then
  printf 'execute SHAs:  pre=%s post=%s\n' "${PRE_SHA:-<none>}" "${POST_SHA:-<none>}"
fi

if [[ -n "$VERDICT" ]]; then
  printf 'verdict:       %s' "$VERDICT"
  [[ -f "$VERDICT_JSON" ]] && printf '  (%s)' "$VERDICT_JSON"
  printf '\n'
elif [[ -f "$VERDICT_JSON" ]]; then
  printf 'verdict:       (verdict.json present: %s)\n' "$VERDICT_JSON"
fi

if [[ -f "$DIFFSTAT_FILE" ]]; then
  printf 'diffstat (tail):\n'
  tail -5 "$DIFFSTAT_FILE" | sed 's/^/  /'
fi

if [[ -f "$EXEC_STDERR" ]]; then
  printf 'execute stderr (last 5 lines):\n'
  tail -5 "$EXEC_STDERR" | sed 's/^/  /'
fi

printf 'ASSESS: %s\n' "$ASSESS"
exit "$EXIT_CODE"
