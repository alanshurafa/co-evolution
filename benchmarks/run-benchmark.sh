#!/usr/bin/env bash
set -euo pipefail

# Task x condition orchestrator for the co-evolution benchmark suite.
#
# One "cell" = one corpus task run under one condition, materialised at
# benchmarks/results/<batch>/<task>/<cond>/. A cell is complete only once its
# meta.json carries status=="complete", and meta.json is written LAST — so a
# killed batch resumes without redoing finished work and never mistakes a
# half-written cell for a finished one.
#
# Contract notes:
# - This script CONSUMES co-evolve-bouncer.sh, lib/co-evolution.sh and
#   benchmarks/lib/benchmark-lib.sh. It never modifies them.
# - Conditions B/D hand the task to the bouncer as a STRING argument, never as
#   a file path. A path would flip the bouncer's INPUT_TYPE to "file"
#   (co-evolve-bouncer.sh:781) and select the "Review and improve the following
#   document" compose prompt instead of the "Respond to the following" one that
#   condition A replicates — silently destroying A-vs-B parity, which is the
#   whole point of the experiment. tests/smoke.sh asserts the parity byte-wise.
# - Exit codes are load-bearing here (deliberate deviation from the repo's
#   "signal lives in artifacts" convention): this orchestrator is meant to be
#   cron-driven, so exiting 0 on a half-finished batch would hide it.
#     0  every selected cell is complete
#     75 (EX_TEMPFAIL) some cells are pending-quota; re-run tomorrow
#        (--allow-pending downgrades this to 0)
#     1  hard failure (bad flags, failed lint, a cell that errored)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/benchmark-lib.sh
source "$SCRIPT_DIR/lib/benchmark-lib.sh"

# --- Defaults ---
CORPUS_DIR="$SCRIPT_DIR/corpus"
CONDITIONS_FILE="$SCRIPT_DIR/conditions.yaml"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
BANNED_FILE="$SCRIPT_DIR/lib/banned-tokens.txt"
RESULTS_ROOT="$SCRIPT_DIR/results"
BATCH="b$(date +%Y%m%d)"
ONLY_TASK=""
ONLY_CONDITION=""
FORCE_CELL=""
GLM_BUDGET=40
DRY_RUN=false
CHECK_ONLY=false
ALLOW_PENDING=false

# Test seams: the smoke test points these at hermetic stubs. Both default to
# the real scripts, so a normal invocation needs no environment at all.
: "${BENCH_BOUNCER_SCRIPT:=$REPO_ROOT/co-evolve-bouncer.sh}"
: "${BENCH_PANEL_SCRIPT:=$SCRIPT_DIR/run-panel.sh}"

# Schema version this orchestrator can read out of conditions.yaml.
BENCH_CONDITIONS_SCHEMA="bench-conditions/1.0"

usage() {
  cat <<'USAGE'
Usage: bash benchmarks/run-benchmark.sh [options]

  --corpus DIR            Corpus directory        (default: benchmarks/corpus)
  --conditions FILE       Condition manifest      (default: benchmarks/conditions.yaml)
  --batch NAME            Batch id                (default: b<YYYYMMDD>)
  --only-task ID          Restrict to one task id (e.g. t3)
  --only-condition ID     Restrict to one condition id (e.g. B)
  --force-cell TASK/COND  Wipe and re-run exactly one cell (e.g. t3/B)
  --glm-budget N          GLM calls allowed today (default: 40)
  --dry-run               Print the matrix, GLM estimates and the path-length
                          computation, then exit. Runs nothing.
  --check                 Lint the corpus and validate the condition manifest,
                          then exit. Runs nothing.
  --allow-pending         Exit 0 instead of 75 when cells are pending-quota
  -h, --help              This message

Exit: 0 all complete | 75 pending-quota remains | 1 hard failure
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --corpus)         CORPUS_DIR="${2:?--corpus requires a directory}"; shift 2 ;;
    --conditions)     CONDITIONS_FILE="${2:?--conditions requires a file}"; shift 2 ;;
    --batch)          BATCH="${2:?--batch requires a name}"; shift 2 ;;
    --only-task)      ONLY_TASK="${2:?--only-task requires a task id}"; shift 2 ;;
    --only-condition) ONLY_CONDITION="${2:?--only-condition requires a condition id}"; shift 2 ;;
    --force-cell)     FORCE_CELL="${2:?--force-cell requires TASK/COND}"; shift 2 ;;
    --glm-budget)     GLM_BUDGET="${2:?--glm-budget requires an integer}"; shift 2 ;;
    --results-root)   RESULTS_ROOT="${2:?--results-root requires a directory}"; shift 2 ;;
    --dry-run)        DRY_RUN=true; shift ;;
    --check)          CHECK_ONLY=true; shift ;;
    --allow-pending)  ALLOW_PENDING=true; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "run-benchmark.sh: unknown option '$1' (see --help)" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "run-benchmark.sh requires jq"
require_mikefarah_yq

[[ "$GLM_BUDGET" =~ ^[0-9]+$ ]] || die "--glm-budget must be a non-negative integer, got '$GLM_BUDGET'"
[[ "$BATCH" =~ ^[A-Za-z0-9._-]+$ ]] || die "--batch must be a filename-safe token, got '$BATCH'"
[[ -d "$CORPUS_DIR" ]] || die "corpus directory not found: $CORPUS_DIR"
[[ -f "$CONDITIONS_FILE" ]] || die "condition manifest not found: $CONDITIONS_FILE"

FORCE_TASK=""
FORCE_COND=""
if [[ -n "$FORCE_CELL" ]]; then
  [[ "$FORCE_CELL" == */* ]] || die "--force-cell wants TASK/COND (e.g. t3/B), got '$FORCE_CELL'"
  FORCE_TASK="${FORCE_CELL%%/*}"
  FORCE_COND="${FORCE_CELL#*/}"
  [[ -n "$FORCE_TASK" && -n "$FORCE_COND" && "$FORCE_COND" != */* ]] \
    || die "--force-cell wants exactly TASK/COND (e.g. t3/B), got '$FORCE_CELL'"
fi

# --- Condition manifest ------------------------------------------------------
#
# Parsed once into parallel arrays indexed by manifest position. yq is only
# invoked here, never inside the cell loop.

COND_IDS=()
COND_LABELS=()
COND_KINDS=()
COND_MODELS=()
COND_GLM=()
COND_ARGS_JSON=()

# _yq_scalar FILE EXPR → prints the scalar, mapping yq's "null" to the empty
# string so a missing key and an explicitly-null key read the same.
_yq_scalar() {
  local file="$1" expr="$2" value
  value=$(yq -r "$expr" "$file" 2>/dev/null) || value=""
  [[ "$value" == "null" ]] && value=""
  printf '%s' "$value"
}

# load_conditions FILE — fills COND_* and returns 1 (after logging every
# violation) when the manifest does not satisfy bench-conditions/1.0.
load_conditions() {
  local file="$1"
  local violations=0
  local schema count i id label kind model glm args_json reviewers_count seen

  COND_IDS=(); COND_LABELS=(); COND_KINDS=(); COND_MODELS=(); COND_GLM=(); COND_ARGS_JSON=()

  if ! yq -e '.' "$file" >/dev/null 2>&1; then
    log "CONDITIONS FAIL: $file is not parseable YAML"
    return 1
  fi

  schema=$(_yq_scalar "$file" '.schema')
  if [[ "$schema" != "$BENCH_CONDITIONS_SCHEMA" ]]; then
    log "CONDITIONS FAIL: schema is '${schema:-<missing>}', expected '$BENCH_CONDITIONS_SCHEMA'"
    violations=$((violations + 1))
  fi

  count=$(_yq_scalar "$file" '.conditions | length')
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  if (( count == 0 )); then
    log "CONDITIONS FAIL: .conditions is missing or empty"
    return 1
  fi

  for (( i = 0; i < count; i++ )); do
    id=$(_yq_scalar "$file" ".conditions[$i].id")
    label=$(_yq_scalar "$file" ".conditions[$i].label")
    kind=$(_yq_scalar "$file" ".conditions[$i].kind")
    model=$(_yq_scalar "$file" ".conditions[$i].model")
    glm=$(_yq_scalar "$file" ".conditions[$i].glm_calls_per_run")

    if [[ -z "$id" ]]; then
      log "CONDITIONS FAIL [#$i]: 'id' is missing or empty"
      violations=$((violations + 1))
      id="#$i"
    elif ! [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]]; then
      # The id becomes a directory name inside the cell path; anything with a
      # separator or space would silently reshape the results tree.
      log "CONDITIONS FAIL [$id]: id must match ^[A-Za-z0-9_-]+$ (it becomes a directory name)"
      violations=$((violations + 1))
    fi
    for seen in ${COND_IDS[@]+"${COND_IDS[@]}"}; do
      if [[ "$seen" == "$id" ]]; then
        log "CONDITIONS FAIL [$id]: duplicate condition id"
        violations=$((violations + 1))
      fi
    done

    [[ -n "$label" ]] || { log "CONDITIONS FAIL [$id]: 'label' is missing or empty"; violations=$((violations + 1)); }

    case "$kind" in
      solo)
        [[ -n "$model" ]] || { log "CONDITIONS FAIL [$id]: kind 'solo' requires a 'model'"; violations=$((violations + 1)); }
        ;;
      bouncer)
        if [[ "$(_yq_scalar "$file" ".conditions[$i].args | length")" =~ ^[1-9][0-9]*$ ]]; then :; else
          log "CONDITIONS FAIL [$id]: kind 'bouncer' requires a non-empty 'args' list"
          violations=$((violations + 1))
        fi
        ;;
      panel)
        reviewers_count=$(_yq_scalar "$file" ".conditions[$i].reviewers | length")
        if [[ "$reviewers_count" =~ ^[1-9][0-9]*$ ]]; then :; else
          log "CONDITIONS FAIL [$id]: kind 'panel' requires a non-empty 'reviewers' list"
          violations=$((violations + 1))
        fi
        ;;
      "")
        log "CONDITIONS FAIL [$id]: 'kind' is missing or empty (want solo|bouncer|panel)"
        violations=$((violations + 1))
        ;;
      *)
        log "CONDITIONS FAIL [$id]: unknown kind '$kind' (want solo|bouncer|panel)"
        violations=$((violations + 1))
        ;;
    esac

    if ! [[ "$glm" =~ ^[0-9]+$ ]]; then
      log "CONDITIONS FAIL [$id]: 'glm_calls_per_run' must be a non-negative integer, got '${glm:-<missing>}'"
      violations=$((violations + 1))
      glm=0
    fi

    # args are carried as a JSON array so an element containing whitespace
    # survives the trip into the cell loop intact.
    args_json=$(yq -o=json -I=0 ".conditions[$i].args // []" "$file" 2>/dev/null) || args_json="[]"
    [[ -n "$args_json" && "$args_json" != "null" ]] || args_json="[]"

    COND_IDS+=("$id")
    COND_LABELS+=("$label")
    COND_KINDS+=("$kind")
    COND_MODELS+=("$model")
    COND_GLM+=("$glm")
    COND_ARGS_JSON+=("$args_json")
  done

  if (( violations > 0 )); then
    log "CONDITIONS: $violations violation(s) in $file"
    return 1
  fi
  return 0
}

# --- Selection ---------------------------------------------------------------

TASK_IDS=()
TASK_FILES=()

load_tasks() {
  local file name
  TASK_IDS=(); TASK_FILES=()
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    name=$(basename "$file" .md)
    if [[ -n "$ONLY_TASK" && "$name" != "$ONLY_TASK" ]]; then
      continue
    fi
    TASK_IDS+=("$name")
    TASK_FILES+=("$file")
  done < <(find "$CORPUS_DIR" -maxdepth 1 -type f -name 't*.md' | sort)

  if (( ${#TASK_IDS[@]} == 0 )); then
    if [[ -n "$ONLY_TASK" ]]; then
      die "--only-task '$ONLY_TASK' matched no t*.md file under $CORPUS_DIR"
    fi
    die "no t*.md task files under $CORPUS_DIR"
  fi
}

# COND_ORDER holds manifest indices in execution order: every GLM-free
# condition first (manifest order), then the GLM-needing ones. A day that runs
# out of GLM quota therefore still finishes all the free cells before parking
# the expensive ones as pending-quota.
COND_ORDER=()

order_conditions() {
  local i matched=0
  COND_ORDER=()
  for (( i = 0; i < ${#COND_IDS[@]}; i++ )); do
    [[ -n "$ONLY_CONDITION" && "${COND_IDS[$i]}" != "$ONLY_CONDITION" ]] && continue
    (( COND_GLM[i] == 0 )) || continue
    COND_ORDER+=("$i")
    matched=$((matched + 1))
  done
  for (( i = 0; i < ${#COND_IDS[@]}; i++ )); do
    [[ -n "$ONLY_CONDITION" && "${COND_IDS[$i]}" != "$ONLY_CONDITION" ]] && continue
    (( COND_GLM[i] > 0 )) || continue
    COND_ORDER+=("$i")
    matched=$((matched + 1))
  done
  if (( matched == 0 )); then
    die "--only-condition '$ONLY_CONDITION' matched no condition in $CONDITIONS_FILE"
  fi
}

# --- MAX_PATH guard ----------------------------------------------------------

# worst_case_state_path BATCH_DIR → the longest state.json path this batch can
# produce. The bouncer builds its run dir as
#   <CO_EVOLVE_RUNS_DIR>/co-evolve-<RUN_LABEL>-<TIMESTAMP>/
# where RUN_LABEL is `echo "$TASK" | head -c 60 | tr ... ` (co-evolve-bouncer.sh
# :489) — head -c 60 caps it at 60 characters no matter how long the task is —
# and TIMESTAMP is generate_run_suffix() = YYYYmmdd-HHMMSS-<6 hex>
# (lib/co-evolution.sh:940). So the worst case is a 60-character label under the
# longest selected task id / condition id, and it is independent of the corpus
# text itself.
worst_case_state_path() {
  local batch_dir="$1"
  local i task cond longest_task="" longest_cond="" label

  for task in ${TASK_IDS[@]+"${TASK_IDS[@]}"}; do
    (( ${#task} > ${#longest_task} )) && longest_task="$task"
  done
  for i in ${COND_ORDER[@]+"${COND_ORDER[@]}"}; do
    cond="${COND_IDS[$i]}"
    (( ${#cond} > ${#longest_cond} )) && longest_cond="$cond"
  done

  label=$(printf 'x%.0s' $(seq 1 60))
  printf '%s/%s/%s/run/co-evolve-%s-20260829-235959-ffffff/state.json' \
    "$batch_dir" "$longest_task" "$longest_cond" "$label"
}

# --- Cell helpers ------------------------------------------------------------

# write_cell_meta — assembles and installs meta.json (bench-cell/1.0). Always
# the LAST write in a cell: it is the resume marker.
write_cell_meta() {
  local cell_dir="$1" task_id="$2" cond_id="$3" kind="$4" status="$5"
  local wall_secs="$6" word_count="$7" convergence="$8" markers="$9"
  local glm_calls="${10}" kimi_status="${11}" degraded="${12}"
  local tokens_json="${13}" error="${14}"
  local json

  printf '%s' "$tokens_json" | jq -e 'type == "object"' >/dev/null 2>&1 || tokens_json='{}'

  json=$(jq -n \
    --arg batch "$BATCH" \
    --arg task "$task_id" \
    --arg cond "$cond_id" \
    --arg kind "$kind" \
    --arg status "$status" \
    --argjson wall_secs "$wall_secs" \
    --argjson word_count "$word_count" \
    --arg convergence "$convergence" \
    --argjson markers "$markers" \
    --argjson glm_calls "$glm_calls" \
    --arg kimi_status "$kimi_status" \
    --argjson degraded "$degraded" \
    --argjson tokens "$tokens_json" \
    --arg error "$error" \
    --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      schema: "bench-cell/1.0",
      batch: $batch,
      task: $task,
      condition: $cond,
      kind: $kind,
      status: $status,
      wall_secs: $wall_secs,
      word_count: $word_count,
      convergence_status: (if $convergence == "" then null else $convergence end),
      markers_final: $markers,
      glm_calls: $glm_calls,
      kimi_status: (if $kimi_status == "" then null else $kimi_status end),
      degraded: $degraded,
      tokens: $tokens,
      error: (if $error == "" then null else $error end),
      finished_at: $finished
    }')

  bench_meta_write "$cell_dir" "$json"
}

# count_final_markers FILE → live [CONTESTED] + [CLARIFY] tokens in the cell's
# final document. Raw (fence-agnostic) counting on purpose: a marker hidden in
# a fence still makes the document unjudgeable.
count_final_markers() {
  local file="$1" contested clarify
  [[ -s "$file" ]] || { printf '0'; return 0; }
  contested=$(count_markers_raw "$file" "[CONTESTED]")
  clarify=$(count_markers_raw "$file" "[CLARIFY]")
  [[ "$contested" =~ ^[0-9]+$ ]] || contested=0
  [[ "$clarify" =~ ^[0-9]+$ ]] || clarify=0
  printf '%s' "$(( contested + clarify ))"
}

word_count_of() {
  local file="$1" n
  [[ -s "$file" ]] || { printf '0'; return 0; }
  n=$(wc -w < "$file" | tr -d '[:space:]')
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}

# write_cell_input CELL_DIR TASK_FILE — materialises <cell>/in.md, the task
# body with frontmatter removed and leading/trailing blank lines trimmed.
#
# Both A and B/D read THIS file, which is what makes the compose-prompt parity
# assertion in tests/smoke.sh hold by construction: condition A hands in.md to
# bench_run_solo_cell, conditions B/D hand `$(cat in.md)` to the bouncer as a
# string, and both sides then run the same strip_protocol_markers + template.
write_cell_input() {
  local cell_dir="$1" task_file="$2"

  bench_task_body "$task_file" > "$cell_dir/in.md"

  [[ -s "$cell_dir/in.md" ]] || die "task body for $task_file is empty after frontmatter removal"
}

# --- Cell runners ------------------------------------------------------------
#
# Each returns 0 on success and leaves <cell>/final.md in place. Anything else
# is a failure and final.md must NOT exist, so the resume path retries the cell
# rather than letting the judge score an error page as a plan.
#
# CELL_* are the per-cell outputs these fill in for write_cell_meta.

CELL_CONVERGENCE=""
CELL_KIMI_STATUS=""
CELL_DEGRADED="false"
CELL_TOKENS="{}"
CELL_ERROR=""
CELL_STATUS_OVERRIDE=""

reset_cell_outputs() {
  CELL_CONVERGENCE=""
  CELL_KIMI_STATUS=""
  CELL_DEGRADED="false"
  CELL_TOKENS="{}"
  CELL_ERROR=""
  CELL_STATUS_OVERRIDE=""
}

run_solo_cell() {
  local cell_dir="$1" model="$2"
  local usage="$cell_dir/compose-output.md.usage.json"
  local rc=0

  # Subshell: bench_run_solo_cell dies (exits) on an unusable cell directory,
  # and one bad cell must not take the whole batch down without a summary.
  ( bench_run_solo_cell "$cell_dir" "$cell_dir/in.md" "$model" ) || rc=$?
  if (( rc != 0 )); then
    CELL_ERROR="solo compose failed (rc=$rc); see $cell_dir/compose-stderr.log"
    return 1
  fi

  if [[ -f "$usage" ]]; then
    CELL_TOKENS=$(jq '{
        phases: { compose: . },
        totals: {
          claude_input:      (.input_tokens // 0),
          claude_output:     (.output_tokens // 0),
          claude_cache_read: (.cache_read_input_tokens // 0),
          claude_cost_usd:   (.total_cost_usd // 0),
          codex_total_tokens: 0
        }
      }' "$usage" 2>/dev/null) || CELL_TOKENS="{}"
    [[ -n "$CELL_TOKENS" ]] || CELL_TOKENS="{}"
  fi
  return 0
}

run_bouncer_cell() {
  local cell_dir="$1" args_json="$2"
  local run_parent="$cell_dir/run"
  local runner_log="$cell_dir/bouncer.log"
  local task_body final run_dir state rc=0
  local -a bounce_args=()

  [[ -f "$BENCH_BOUNCER_SCRIPT" ]] || { CELL_ERROR="bouncer not found: $BENCH_BOUNCER_SCRIPT"; return 1; }

  # NUL-delimited, not line-delimited: jq.exe under Git Bash writes CRLF, and a
  # line-based read would hand the bouncer `--vanilla\r`, which its flag parser
  # rejects as an unknown flag. NUL separators sidestep the translation (there
  # are no newlines left to translate) and also survive an argument containing
  # whitespace.
  while IFS= read -r -d '' arg; do
    bounce_args+=("$arg")
  done < <(printf '%s' "$args_json" | jq -j '.[] | (. + "\u0000")')

  mkdir -p "$run_parent" || { CELL_ERROR="could not create $run_parent"; return 1; }

  # The task goes in as a STRING (see the header note): a path argument would
  # select the bouncer's file-input compose prompt and break A-vs-B parity.
  task_body=$(cat "$cell_dir/in.md")

  CO_EVOLVE_RUNS_DIR="$run_parent" CO_EVOLVE_TOKEN_CAPTURE=1 \
    bash "$BENCH_BOUNCER_SCRIPT" ${bounce_args[@]+"${bounce_args[@]}"} "$task_body" \
    > "$runner_log" 2>&1 || rc=$?

  if (( rc != 0 )); then
    CELL_ERROR="co-evolve-bouncer.sh exited $rc; see $runner_log"
    return 1
  fi

  # Subshell so the library's die() on a malformed run tree becomes a cell
  # failure instead of a batch abort.
  final=$( bench_find_bouncer_final "$run_parent" 2>>"$runner_log" ) || {
    CELL_ERROR="no final document under $run_parent; see $runner_log"
    return 1
  }
  cp "$final" "$cell_dir/final.md" || { CELL_ERROR="could not copy $final"; return 1; }

  run_dir=$(dirname "$final")
  state="$run_dir/state.json"
  if [[ -f "$state" ]]; then
    # CO_EVOLVE_TOKEN_CAPTURE=1 makes invoke_claude drop per-call usage sidecars
    # and invoke_codex leave "tokens used" lines in its stderr logs, but — unlike
    # dev-review.sh:1230 — co-evolve-bouncer.sh never calls collect_token_usage,
    # so its state.json has no .tokens block. We fold the sidecars in here
    # instead of patching the bouncer (which this suite only consumes). The
    # function is offline, idempotent, and never fatal.
    collect_token_usage "$run_dir" "$state" >/dev/null 2>&1 || true

    CELL_CONVERGENCE=$(jq -r '.convergence_status // ""' "$state" 2>/dev/null) || CELL_CONVERGENCE=""
    [[ "$CELL_CONVERGENCE" == "null" ]] && CELL_CONVERGENCE=""
    CELL_TOKENS=$(jq -c '.tokens // {}' "$state" 2>/dev/null) || CELL_TOKENS="{}"
    [[ -n "$CELL_TOKENS" ]] || CELL_TOKENS="{}"
  else
    log " WARNING: no state.json under $run_dir; convergence and tokens unavailable"
  fi
  return 0
}

run_panel_cell() {
  local cell_dir="$1" task_file="$2"
  local run_parent="$cell_dir/run"
  local runner_log="$cell_dir/panel.log"
  local panel_state="$run_parent/panel-state.json"
  local rc=0

  [[ -f "$BENCH_PANEL_SCRIPT" ]] || { CELL_ERROR="panel harness not found: $BENCH_PANEL_SCRIPT"; return 1; }

  mkdir -p "$run_parent" || { CELL_ERROR="could not create $run_parent"; return 1; }

  bash "$BENCH_PANEL_SCRIPT" --task-file "$task_file" --out-dir "$run_parent" \
    > "$runner_log" 2>&1 || rc=$?

  # run-panel.sh contract: 0 = final.md written, 1 = compose/synthesis failure,
  # 4 = retryable quota/auth (park the cell, do not burn the batch).
  if (( rc == 4 )); then
    CELL_STATUS_OVERRIDE="pending-quota"
    CELL_ERROR="run-panel.sh reported a retryable quota/auth condition (rc=4); see $runner_log"
  elif (( rc != 0 )); then
    CELL_ERROR="run-panel.sh exited $rc; see $runner_log"
  fi

  if [[ -f "$panel_state" ]]; then
    CELL_KIMI_STATUS=$(jq -r '.kimi_status // ""' "$panel_state" 2>/dev/null) || CELL_KIMI_STATUS=""
    [[ "$CELL_KIMI_STATUS" == "null" ]] && CELL_KIMI_STATUS=""
    CELL_DEGRADED=$(jq -r 'if (.degraded // false) then "true" else "false" end' "$panel_state" 2>/dev/null) || CELL_DEGRADED="false"
    CELL_TOKENS=$(jq -c '.tokens // {}' "$panel_state" 2>/dev/null) || CELL_TOKENS="{}"
    [[ -n "$CELL_TOKENS" ]] || CELL_TOKENS="{}"
  fi

  (( rc == 0 )) || return 1

  if [[ ! -s "$run_parent/final.md" ]]; then
    CELL_ERROR="run-panel.sh exited 0 but wrote no final.md under $run_parent"
    return 1
  fi
  cp "$run_parent/final.md" "$cell_dir/final.md" || { CELL_ERROR="could not copy panel final.md"; return 1; }
  return 0
}

# --- Modes -------------------------------------------------------------------

do_check() {
  local rc=0

  log "CHECK: conditions -> $CONDITIONS_FILE"
  load_conditions "$CONDITIONS_FILE" || rc=1
  if (( rc == 0 )); then
    log "CHECK: ${#COND_IDS[@]} condition(s) OK (${COND_IDS[*]})"
  fi

  log "CHECK: corpus -> $CORPUS_DIR"
  bench_lint_corpus "$CORPUS_DIR" "$TEMPLATES_DIR" "$BANNED_FILE" || rc=1

  if (( rc == 0 )); then
    log "CHECK: PASS"
  else
    log "CHECK: FAIL"
  fi
  return $rc
}

do_dry_run() {
  local batch_dir="$RESULTS_ROOT/$BATCH"
  local i task_id cond_id status cell_dir worst
  local total_cells=0 total_glm=0 per_cond

  log "DRY RUN: batch '$BATCH' -> $batch_dir"
  log ""
  log "Conditions in execution order (GLM-needing last):"
  for i in "${COND_ORDER[@]}"; do
    log "  ${COND_IDS[$i]}  kind=${COND_KINDS[$i]}  label=${COND_LABELS[$i]}  glm/run=${COND_GLM[$i]}"
  done
  log ""
  log "Matrix (${#TASK_IDS[@]} task(s) x ${#COND_ORDER[@]} condition(s)):"
  local idx
  for (( idx = 0; idx < ${#TASK_IDS[@]}; idx++ )); do
    task_id="${TASK_IDS[$idx]}"
    local row="  $task_id:"
    for i in "${COND_ORDER[@]}"; do
      cond_id="${COND_IDS[$i]}"
      cell_dir=$(bench_cell_dir "$batch_dir" "$task_id" "$cond_id")
      status=$(bench_meta_status "$cell_dir")
      row+=" $cond_id=$status"
      total_cells=$((total_cells + 1))
      total_glm=$((total_glm + COND_GLM[i]))
    done
    log "$row"
  done
  log ""
  log "GLM call estimate (budget ${GLM_BUDGET}/day):"
  for i in "${COND_ORDER[@]}"; do
    per_cond=$(( COND_GLM[i] * ${#TASK_IDS[@]} ))
    log "  ${COND_IDS[$i]}: ${COND_GLM[$i]}/run x ${#TASK_IDS[@]} task(s) = $per_cond call(s)"
  done
  if (( GLM_BUDGET > 0 )); then
    log "  total: $total_glm call(s) -> at least $(( (total_glm + GLM_BUDGET - 1) / GLM_BUDGET )) day(s) at ${GLM_BUDGET}/day"
  else
    log "  total: $total_glm call(s) -> budget is 0, every GLM-needing cell parks as pending-quota"
  fi
  log ""
  worst=$(worst_case_state_path "$batch_dir")
  log "Worst-case bouncer state.json path (${#worst} chars, limit ${BENCH_MAX_PATH}):"
  log "  $worst"
  bench_path_guard "$worst"
  log "Path guard: OK"
  log ""
  log "DRY RUN: $total_cells cell(s) would be considered. Nothing ran."
}

do_batch() {
  local batch_dir="$RESULTS_ROOT/$BATCH"
  local idx i task_id task_file cond_id cond_kind cell_dir status
  local needed started elapsed rc worst
  local n_total=0 n_complete=0 n_skipped=0 n_pending=0 n_failed=0
  local forced

  mkdir -p "$batch_dir" || die "could not create batch dir $batch_dir"
  LOG_FILE="$batch_dir/run-benchmark.log"

  worst=$(worst_case_state_path "$batch_dir")
  bench_path_guard "$worst"

  log "BATCH $BATCH: ${#TASK_IDS[@]} task(s) x ${#COND_ORDER[@]} condition(s) -> $batch_dir"
  log " worst-case state.json path: ${#worst} chars (limit ${BENCH_MAX_PATH})"

  for (( idx = 0; idx < ${#TASK_IDS[@]}; idx++ )); do
    task_id="${TASK_IDS[$idx]}"
    task_file="${TASK_FILES[$idx]}"

    for i in "${COND_ORDER[@]}"; do
      cond_id="${COND_IDS[$i]}"
      cond_kind="${COND_KINDS[$i]}"
      needed="${COND_GLM[$i]}"
      cell_dir=$(bench_cell_dir "$batch_dir" "$task_id" "$cond_id")
      n_total=$((n_total + 1))

      forced=false
      if [[ -n "$FORCE_CELL" && "$task_id" == "$FORCE_TASK" && "$cond_id" == "$FORCE_COND" ]]; then
        forced=true
      fi

      if [[ "$forced" == "true" ]]; then
        log "[$task_id/$cond_id] --force-cell: wiping and re-running"
        rm -rf -- "$cell_dir" || die "could not wipe forced cell $cell_dir"
      else
        status=$(bench_meta_status "$cell_dir")
        if [[ "$status" == "complete" ]]; then
          n_complete=$((n_complete + 1))
          n_skipped=$((n_skipped + 1))
          continue
        fi
        # Any other prior state (failed, pending-quota, absent, half-written) is
        # redone from scratch: a partial cell must never be merged into a new
        # attempt, or a stale final.md could outlive a failed re-run.
        if [[ "$status" != "absent" ]]; then
          log "[$task_id/$cond_id] previous status '$status' — redoing from scratch"
          rm -rf -- "$cell_dir" || die "could not clear stale cell $cell_dir"
        fi
      fi

      mkdir -p "$cell_dir" || die "could not create cell dir $cell_dir"
      reset_cell_outputs

      # GLM quota gate runs BEFORE any work so a parked cell costs nothing.
      if (( needed > 0 )) && ! bench_glm_ledger_check "$batch_dir" "$needed" "$GLM_BUDGET"; then
        log "[$task_id/$cond_id] pending-quota: needs $needed GLM call(s), daily budget $GLM_BUDGET is spent"
        write_cell_meta "$cell_dir" "$task_id" "$cond_id" "$cond_kind" "pending-quota" \
          0 0 "" 0 0 "" false "{}" "GLM daily budget ($GLM_BUDGET) exhausted; re-run tomorrow"
        n_pending=$((n_pending + 1))
        continue
      fi

      log "[$task_id/$cond_id] running (kind=$cond_kind)"
      write_cell_input "$cell_dir" "$task_file"

      # Debit the ledger BEFORE dispatch. Over-counting costs an unused call;
      # under-counting costs a hard auth failure mid-batch (benchmark-lib.sh
      # makes the same trade in _bench_ledger_read).
      if (( needed > 0 )); then
        bench_glm_ledger_add "$batch_dir" "$needed"
      fi

      started=$(date +%s)
      rc=0
      case "$cond_kind" in
        solo)    run_solo_cell "$cell_dir" "${COND_MODELS[$i]}" || rc=$? ;;
        bouncer) run_bouncer_cell "$cell_dir" "${COND_ARGS_JSON[$i]}" || rc=$? ;;
        panel)   run_panel_cell "$cell_dir" "$task_file" || rc=$? ;;
        *)       CELL_ERROR="unknown condition kind '$cond_kind'"; rc=1 ;;
      esac
      elapsed=$(( $(date +%s) - started ))

      local cell_status="complete"
      if (( rc != 0 )); then
        cell_status="${CELL_STATUS_OVERRIDE:-failed}"
      fi

      local words markers
      words=$(word_count_of "$cell_dir/final.md")
      markers=$(count_final_markers "$cell_dir/final.md")

      if [[ "$cell_status" == "complete" && ! -s "$cell_dir/final.md" ]]; then
        cell_status="failed"
        CELL_ERROR="${CELL_ERROR:-runner reported success but wrote no final.md}"
      fi

      write_cell_meta "$cell_dir" "$task_id" "$cond_id" "$cond_kind" "$cell_status" \
        "$elapsed" "$words" "$CELL_CONVERGENCE" "$markers" "$needed" \
        "$CELL_KIMI_STATUS" "$CELL_DEGRADED" "$CELL_TOKENS" "$CELL_ERROR"

      case "$cell_status" in
        complete)
          n_complete=$((n_complete + 1))
          log "[$task_id/$cond_id] complete (${elapsed}s, ${words} words, markers=${markers}${CELL_CONVERGENCE:+, ${CELL_CONVERGENCE}})"
          ;;
        pending-quota)
          n_pending=$((n_pending + 1))
          log "[$task_id/$cond_id] pending-quota: $CELL_ERROR"
          ;;
        *)
          n_failed=$((n_failed + 1))
          log "[$task_id/$cond_id] FAILED: $CELL_ERROR"
          ;;
      esac
    done
  done

  local exit_code=0
  if (( n_failed > 0 )); then
    exit_code=1
  elif (( n_pending > 0 )) && [[ "$ALLOW_PENDING" != "true" ]]; then
    exit_code=75
  fi

  log "BENCH SUMMARY: batch=$BATCH cells=$n_total complete=$n_complete (skipped=$n_skipped) pending-quota=$n_pending failed=$n_failed exit=$exit_code"
  if (( n_pending > 0 )); then
    log "  $n_pending cell(s) pending on GLM quota — re-run the same command tomorrow to pick them up."
  fi
  return $exit_code
}

# --- Main --------------------------------------------------------------------

if [[ "$CHECK_ONLY" == "true" ]]; then
  do_check || exit 1
  exit 0
fi

load_conditions "$CONDITIONS_FILE" || die "condition manifest $CONDITIONS_FILE is invalid (run --check for the full list)"
load_tasks
order_conditions

if [[ "$DRY_RUN" == "true" ]]; then
  do_dry_run
  exit 0
fi

# A batch runs against a linted corpus, always. The lint is offline and takes
# well under a second; discovering a malformed task after 30 LLM calls is not
# a trade worth making.
bench_lint_corpus "$CORPUS_DIR" "$TEMPLATES_DIR" "$BANNED_FILE" \
  || die "corpus lint failed — fix the corpus before spending model calls (see --check)"

BATCH_RC=0
do_batch || BATCH_RC=$?
exit $BATCH_RC
