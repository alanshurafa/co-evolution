#!/usr/bin/env bash
# evals/score-run.sh
# Port of runners/codex-ps/evals/score-run.ps1 (BASH-EVAL-01 Plan 02-02).
# Scores a single co-evolution run against a case spec across 7 dimensions.
# Emits scores.json to --output-dir (default: --run-dir).
#
# Dimensions (PS analog lines in score-run.ps1):
#   robustness         (234-251)  — state.status + UnhandledException grep in outputs/*.log
#   convergence        (253-301)  — marker_counts.total + bounce structural check
#   plan_quality       (303-320)  — plan.md word count + heading group match
#   execution_fidelity (322-337)  — Jaccard of plan-declared paths vs state.changed_files
#   verify_accuracy    (339-378)  — verdict.json presence + allow_verdict / must_catch_issue
#   cost               (380-402)  — wall-clock state.started_at -> .updated_at vs max
#   cross_ai_diversity (404-426)  — Levenshtein(compose.txt, bounce-01.txt) when composer != reviewer
#
# Dependencies: bash, jq, yq, awk, grep, find, wc, date. Per D-03 all mandatory.
#
# Determinism contract (D-02): byte-identical output across repeated invocations on
# the same input, stripping .scored_at. Must NOT use environment-random or sub-second
# clock sources (per plan_02-02 acceptance criteria).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/co-evolution.sh
source "${REPO_ROOT}/lib/co-evolution.sh"
# shellcheck source=./lib/co-evolution-evals.sh
source "${SCRIPT_DIR}/lib/co-evolution-evals.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: evals/score-run.sh --case-file PATH --run-dir PATH [OPTIONS]

Score a single co-evolution run across 7 dimensions and emit scores.json.

Required:
  --case-file PATH      Case YAML spec (merged with --defaults-file if given).
  --run-dir PATH        Captured run dir containing state.json, plan.md,
                        verdict.json, outputs/.

Optional:
  --defaults-file PATH  Defaults YAML merged under the case (default: none).
  --output-dir PATH     Where to write scores.json (default: --run-dir).
  --help                Show this help and exit 0.

Exit codes:
  0 on successful score emission
  1 on any fatal error (missing state.json, invalid JSON, jq failure, etc.)
EOF
}

# ---------------------------------------------------------------------------
# CLI parsing (ports score-run.ps1 param block 1:1)
# ---------------------------------------------------------------------------

CASE_FILE=""
RUN_DIR=""
DEFAULTS_FILE=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case-file)
      [[ $# -gt 1 ]] || die "--case-file requires a value"
      CASE_FILE="$2"
      shift 2
      ;;
    --run-dir)
      [[ $# -gt 1 ]] || die "--run-dir requires a value"
      RUN_DIR="$2"
      shift 2
      ;;
    --defaults-file)
      [[ $# -gt 1 ]] || die "--defaults-file requires a value"
      DEFAULTS_FILE="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -gt 1 ]] || die "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      die "Unknown flag: $1"
      ;;
    *)
      die "Unexpected positional arg: $1"
      ;;
  esac
done

[[ -n "$CASE_FILE" ]] || { usage >&2; die "--case-file is required"; }
[[ -n "$RUN_DIR" ]]   || { usage >&2; die "--run-dir is required"; }
[[ -f "$CASE_FILE" ]] || die "case file not found: $CASE_FILE"
[[ -d "$RUN_DIR" ]]   || die "run-dir not found: $RUN_DIR"
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="$RUN_DIR"
mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Load merged case spec (ports score-run.ps1:52-57)
# ---------------------------------------------------------------------------

if [[ -n "$DEFAULTS_FILE" && -f "$DEFAULTS_FILE" ]]; then
  case_json=$(merge_yaml_defaults "$DEFAULTS_FILE" "$CASE_FILE")
else
  case_json=$(read_yaml_file "$CASE_FILE")
fi

case_id=$(jq -r '.id // "unknown"' <<<"$case_json")
case_title=$(jq -r '.title // ""' <<<"$case_json")
composer=$(jq -r '(.runner.composer // "codex") | tostring' <<<"$case_json")
reviewer=$(jq -r '(.runner.reviewer // "codex") | tostring' <<<"$case_json")
executor=$(jq -r '(.runner.executor // "codex") | tostring' <<<"$case_json")

# ---------------------------------------------------------------------------
# Load run artifacts (ports score-run.ps1:79-100)
# ---------------------------------------------------------------------------

state_json_path="$RUN_DIR/state.json"
[[ -f "$state_json_path" ]] || die "state.json not found at: $state_json_path"
jq -e . "$state_json_path" >/dev/null 2>&1 || die "state.json is not valid JSON: $state_json_path"

plan_path="$RUN_DIR/plan.md"
plan_text=""
if [[ -f "$plan_path" ]]; then
  plan_text=$(<"$plan_path")
fi

verdict_path="$RUN_DIR/verdict.json"
verdict_state=''
load_json_or_sentinel "$verdict_path" verdict_state
# verdict_state is: "" (OK), "missing" (file absent), or "unparseable" (bad JSON)

outputs_dir="$RUN_DIR/outputs"

run_id=$(jq -r '.run_id // "unknown"' "$state_json_path")

# ---------------------------------------------------------------------------
# Dimension: Robustness (port score-run.ps1:234-251)
# state.status != "completed" -> FAIL. Exception regex in outputs/*.log -> PARTIAL.
# ---------------------------------------------------------------------------

status=$(jq -r '.status // "unknown"' "$state_json_path")
robust="PASS"
[[ "$status" != "completed" ]] && robust="FAIL"
had_exception=false
if [[ -d "$outputs_dir" ]]; then
  # Guard: the glob expands to nothing if no *.log files; redirect stderr to /dev/null
  # and explicitly handle grep's exit 1 on no-match via `|| true` pattern (avoid set -e).
  if grep -qiE '\bUnhandledException\b|\bFullyQualifiedErrorId\b.*\bRuntimeException\b' "$outputs_dir/"*.log 2>/dev/null; then
    had_exception=true
  fi
fi
if [[ "$had_exception" == "true" && "$robust" == "PASS" ]]; then
  robust="PARTIAL"
fi

# ---------------------------------------------------------------------------
# Dimension: Cost (port score-run.ps1:380-402)
# wall = updated_at - started_at. > max -> PARTIAL. > max*1.5 -> FAIL.
# ---------------------------------------------------------------------------

max_wall=$(jq -r '(.expectations.cost.max_wall_clock_seconds // 900) | tostring' <<<"$case_json")
started_at=$(jq -r '.started_at // ""' "$state_json_path")
updated_at=$(jq -r '.updated_at // ""' "$state_json_path")

wall_secs=0
if [[ -n "$started_at" && -n "$updated_at" && "$started_at" != "null" && "$updated_at" != "null" ]]; then
  # jq's fromdateiso8601 requires "%Y-%m-%dT%H:%M:%SZ" form; PS emits
  # fractional seconds + numeric timezone offsets (e.g. "2026-04-17T09:00:00.0000000-04:00").
  # parseiso trims the fractional part then splits the numeric offset, parses the
  # base with a Z suffix, and subtracts the offset in seconds to recover UTC epoch.
  # Character-class "[.]" avoids shell/jq escape collisions for the literal dot.
  wall_secs=$(jq -rn --arg s "$started_at" --arg e "$updated_at" '
    def trimfrac: sub("[.][0-9]+"; "");
    def parseiso:
      trimfrac as $t |
      if ($t | test("Z$")) then ($t | fromdateiso8601?)
      else
        (($t | capture("^(?<base>.+T[0-9:]+)(?<sign>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$")?) // null) as $m |
        if $m == null then null
        else
          (($m.h | tonumber) * 3600 + ($m.m | tonumber) * 60) as $offs |
          (if $m.sign == "-" then -$offs else $offs end) as $tzsec |
          (($m.base + "Z") | fromdateiso8601?) as $epoch |
          if $epoch == null then null else ($epoch - $tzsec) end
        end
      end;
    (($s | parseiso) // null) as $se |
    (($e | parseiso) // null) as $ee |
    if ($se != null and $ee != null) then ($ee - $se) else 0 end
  ')
fi

cost="PASS"
# Integer compare; ensure numeric. If either side non-numeric, default to 0 (PASS)
if [[ "$wall_secs" =~ ^[0-9]+$ && "$max_wall" =~ ^[0-9]+$ ]]; then
  if (( wall_secs > max_wall )); then
    cost="PARTIAL"
  fi
  threshold_hard=$(( max_wall * 3 / 2 ))  # max * 1.5
  if (( wall_secs > threshold_hard )); then
    cost="FAIL"
  fi
fi

# ---------------------------------------------------------------------------
# Dimension: Cross-AI diversity — N/A guard only in Task 1 scaffold
# Full Levenshtein-based comparison lands in Task 2.
# ---------------------------------------------------------------------------

cross_ai_diversity="N/A"
if [[ "$composer" != "$reviewer" ]]; then
  # Placeholder: Task 2 replaces with Levenshtein-based computation against
  # outputs/compose.txt vs outputs/bounce-01.txt.
  cross_ai_diversity="FAIL"
fi

# ---------------------------------------------------------------------------
# TASK-2 port targets — placeholder values so scores.json shape is complete.
# Replaced in Task 2 with full implementations.
# ---------------------------------------------------------------------------

convergence="FAIL"
plan_quality="FAIL"
execution_fidelity="FAIL"
verify_accuracy="FAIL"

# ---------------------------------------------------------------------------
# Scores object (fixed key order for determinism; jq -S re-sorts at final write)
# ---------------------------------------------------------------------------

scores_json=$(jq -n \
  --arg ca "$cross_ai_diversity" \
  --arg co "$convergence" \
  --arg pq "$plan_quality" \
  --arg ef "$execution_fidelity" \
  --arg va "$verify_accuracy" \
  --arg cs "$cost" \
  --arg rb "$robust" \
  '{cross_ai_diversity:$ca, convergence:$co, plan_quality:$pq, execution_fidelity:$ef, verify_accuracy:$va, cost:$cs, robustness:$rb}')

# ---------------------------------------------------------------------------
# Composite weighted mean (port score-run.ps1:428-446)
# Weights: robustness=2, all others=1. Values: PASS=1.0, PARTIAL=0.5, FAIL=0.0, N/A=excluded.
# Result rounded to 3 decimals via jq '*1000 | round / 1000'.
# ---------------------------------------------------------------------------

composite=$(jq -n --argjson scores "$scores_json" '
  {cross_ai_diversity:1, convergence:1, plan_quality:1, execution_fidelity:1, verify_accuracy:1, cost:1, robustness:2} as $W |
  {PASS:1.0, PARTIAL:0.5, FAIL:0.0, "N/A":null} as $V |
  ($scores | to_entries | map(
    ($W[.key]) as $w |
    ($V[.value]) as $v |
    if $v == null then null else {sum_w:$w, sum_s:($w * $v)} end
  ) | map(select(. != null))) as $rows |
  if ($rows | length) == 0 then 0
  else (($rows | map(.sum_s) | add) / ($rows | map(.sum_w) | add) * 1000 | round / 1000)
  end
')

# ---------------------------------------------------------------------------
# Details (sparse for Task 1; Task 2 expands per-dimension metadata)
# ---------------------------------------------------------------------------

details_json=$(jq -n \
  --arg status "$status" \
  --argjson had_exception "$had_exception" \
  --argjson wall_secs "$wall_secs" \
  --argjson max_wall "$max_wall" \
  --arg composer "$composer" \
  --arg reviewer "$reviewer" \
  '{
    robustness: {status: $status, had_exception: $had_exception},
    cost: {wall_clock_seconds: $wall_secs, max: $max_wall},
    cross_ai_diversity: {composer: $composer, reviewer: $reviewer}
  }')

scored_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build final JSON with fixed key order; jq -S sort keys for determinism.
jq -nS \
  --arg case_id "$case_id" \
  --arg title "$case_title" \
  --arg run_id "$run_id" \
  --argjson scores "$scores_json" \
  --argjson composite "$composite" \
  --argjson details "$details_json" \
  --arg scored_at "$scored_at" \
  '{case_id:$case_id, title:$title, run_id:$run_id, scores:$scores, composite:$composite, details:$details, scored_at:$scored_at}' \
  | atomic_json_write_stdin '.' "$OUTPUT_DIR/scores.json"

# Echo scores dict on stdout for CLI convenience (matches PS Write-Host line).
jq -S '.scores' "$OUTPUT_DIR/scores.json"
