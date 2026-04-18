#!/usr/bin/env bash
# evals/run-evals.sh
# Port of runners/codex-ps/evals/run-evals.ps1 (BASH-EVAL-01 Plan 02-03 Task 1).
#
# Orchestrates the eval harness:
#   1. Select case YAMLs from evals/cases/ (all except defaults.yaml).
#   2. For each case: create an isolated fixture under a shared mktemp root.
#   3. Seed declared files (case.setup.seed_files) and copy_from pairs.
#   4. Invoke the runner (default dev-review/codex/dev-review.sh; overridable
#      via --runner-path for hermetic Tier 2 testing via evals/tests/fake-runner.sh).
#   5. Capture .co-evolution/runs/<id>/ into reports/<ts>/runs/<case-id-iter>/.
#   6. Score each captured run via evals/score-run.sh.
#   7. Emit a single raw-scores.json + human-readable report.md under reports/<ts>/.
#
# Exit 0 iff every case PASSes on the Robustness dimension; 1 otherwise
# (matches run-evals.ps1:275-287).
#
# Security posture (v1.2 Plan 02-03):
#   T-02-03-01  case.id and case filename must match ^[A-Za-z0-9_-]+$ — path-traversal guard.
#   T-02-03-02  runner flags passed via explicit argv, never string-concat + eval.
#   T-02-03-03  tmp fixture dirs cleaned on EXIT via trap (unless --keep-fixtures).
#   T-02-03-06  report-dir name collision resolved by -N suffix bump.
#   T-02-03-10  --runner-path resolved to abs path + logged so misuse is visible.
#
# Dependencies: bash >=4, jq, yq (mikefarah), coreutils. No pwsh required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/co-evolution.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/co-evolution-evals.sh"

# ---------------------------------------------------------------------------
# Usage / CLI
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: evals/run-evals.sh [OPTIONS]

Run the eval harness across cases and emit a scored report.

Options:
  --case NAME           Run only the named case (id matching).
  --cases NAME,...      Run a comma-separated list of cases.
  --validate            Validate all case YAMLs parse + merge; do NOT invoke runner.
  --keep-fixtures       Do not delete fixture tmp dirs after run (debug aid).
  --skip-scoring        Run cases but skip scoring.
  --repeat N            Run each selected case N times. Default 1.
  --runner-path PATH    Override the runner binary path. Default:
                        dev-review/codex/dev-review.sh. Used by Tier 2
                        hermetic testing (evals/tests/fake-runner.sh).
  --help, -h            Show this help and exit 0.

Exit 0 iff every case PASSes Robustness; 1 otherwise.
EOF
}

CASE_SELECTOR=""
VALIDATE_ONLY=false
KEEP_FIXTURES=false
SKIP_SCORING=false
REPEAT=1
RUNNER_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case)           [[ $# -gt 1 ]] || die "--case requires a value";         CASE_SELECTOR="$2"; shift 2 ;;
    --cases)          [[ $# -gt 1 ]] || die "--cases requires a value";        CASE_SELECTOR="$2"; shift 2 ;;
    --validate)       VALIDATE_ONLY=true;  shift ;;
    --keep-fixtures)  KEEP_FIXTURES=true;  shift ;;
    --skip-scoring)   SKIP_SCORING=true;   shift ;;
    --repeat)         [[ $# -gt 1 ]] || die "--repeat requires a value";       REPEAT="$2";        shift 2 ;;
    --runner-path)    [[ $# -gt 1 ]] || die "--runner-path requires a value";  RUNNER_PATH="$2";   shift 2 ;;
    --help|-h)        usage; exit 0 ;;
    -*)               die "Unknown flag: $1" ;;
    *)                die "Unexpected positional arg: $1" ;;
  esac
done

# --repeat must be a positive integer.
printf -v _r '%d' "$REPEAT" 2>/dev/null || die "--repeat must be an integer; got: $REPEAT"
(( REPEAT >= 1 )) || die "--repeat must be >= 1; got: $REPEAT"

# Default runner path if unset; validate the resolved path.
if [[ -z "$RUNNER_PATH" ]]; then
  RUNNER_PATH="$REPO_ROOT/dev-review/codex/dev-review.sh"
fi
[[ -f "$RUNNER_PATH" ]] || die "--runner-path file not found: $RUNNER_PATH"
# Resolve to absolute path for logging + consistent invocation.
RUNNER_PATH_ABS="$(cd "$(dirname "$RUNNER_PATH")" && pwd)/$(basename "$RUNNER_PATH")"

# ---------------------------------------------------------------------------
# Constants (port run-evals.ps1:57-63)
# ---------------------------------------------------------------------------

EVALS_ROOT="$SCRIPT_DIR"
CASES_DIR="$EVALS_ROOT/cases"
REPORTS_DIR="$EVALS_ROOT/reports"
DEFAULTS_FILE="$CASES_DIR/defaults.yaml"
TEMPLATE_FILE="$EVALS_ROOT/report-template.md"

[[ -d "$CASES_DIR" ]]          || die "Cases dir not found: $CASES_DIR"
[[ -f "$DEFAULTS_FILE" ]]      || die "Defaults YAML not found: $DEFAULTS_FILE"
[[ -f "$SCRIPT_DIR/score-run.sh" ]] || die "score-run.sh not found at: $SCRIPT_DIR/score-run.sh"

log "Using runner: $RUNNER_PATH_ABS"

# ---------------------------------------------------------------------------
# Case discovery (port run-evals.ps1:70-86, using glob + sort)
# ---------------------------------------------------------------------------

mapfile -t all_case_files < <(find "$CASES_DIR" -maxdepth 1 -name '*.yaml' ! -name 'defaults.yaml' -type f | sort)
(( ${#all_case_files[@]} > 0 )) || die "No case YAMLs found under $CASES_DIR"

declare -a selected_case_files=()
if [[ -n "$CASE_SELECTOR" ]]; then
  IFS=',' read -r -a wanted <<<"$CASE_SELECTOR"
  for cf in "${all_case_files[@]}"; do
    case_id_raw=$(basename "$cf" .yaml)
    for w in "${wanted[@]}"; do
      # Trim whitespace on both ends.
      w_trim="${w#"${w%%[![:space:]]*}"}"
      w_trim="${w_trim%"${w_trim##*[![:space:]]}"}"
      [[ -z "$w_trim" ]] && continue
      if [[ "$case_id_raw" == "$w_trim" || "$case_id_raw" == "$w_trim"* ]]; then
        selected_case_files+=("$cf")
        break
      fi
    done
  done
else
  selected_case_files=("${all_case_files[@]}")
fi
(( ${#selected_case_files[@]} > 0 )) || die "No cases matched selector: $CASE_SELECTOR"

# ---------------------------------------------------------------------------
# --validate mode: parse + merge every selected case, emit OK line, exit 0/1.
# (Port run-evals.ps1's -Validate switch semantics: no runner invocation.)
# ---------------------------------------------------------------------------

if [[ "$VALIDATE_ONLY" == "true" ]]; then
  log "Validating ${#selected_case_files[@]} case YAML(s)..."
  fail_count=0
  for cf in "${selected_case_files[@]}"; do
    if merged=$(merge_yaml_defaults "$DEFAULTS_FILE" "$cf" 2>&1); then
      if ! echo "$merged" | jq -e 'has("id") and .runner.task and .runner.composer and .runner.executor' >/dev/null 2>&1; then
        log "FAIL: $cf — missing required fields (id, runner.task, runner.composer, runner.executor)"
        fail_count=$((fail_count + 1))
        continue
      fi
      case_id=$(echo "$merged" | jq -r '.id')
      # T-02-03-01: id must be path-safe.
      if [[ ! "$case_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        log "FAIL: $cf — case.id contains invalid characters: $case_id"
        fail_count=$((fail_count + 1))
        continue
      fi
      log "validated: $cf"
    else
      log "FAIL: $cf — parse/merge error: $merged"
      fail_count=$((fail_count + 1))
    fi
  done
  if (( fail_count > 0 )); then
    die "Validation failed on $fail_count case(s)"
  fi
  log "OK: ${#selected_case_files[@]} cases validated"
  exit 0
fi

# ---------------------------------------------------------------------------
# Report dir setup + fixture root + trap (T-02-03-03, T-02-03-06)
# ---------------------------------------------------------------------------

mkdir -p "$REPORTS_DIR"
ts=$(date -u +"%Y%m%d-%H%M%S")
report_dir="$REPORTS_DIR/$ts"
suffix=2
while [[ -e "$report_dir" ]]; do
  report_dir="$REPORTS_DIR/$ts-$suffix"
  suffix=$((suffix + 1))
done
mkdir -p "$report_dir/runs"
log "Report directory: $report_dir"

FIXTURE_ROOT=$(mktemp -d -t evals-fixture-XXXXXX)
cleanup_fixtures() {
  if [[ "$KEEP_FIXTURES" == "true" ]]; then
    log "Keeping fixtures at $FIXTURE_ROOT"
  else
    rm -rf "$FIXTURE_ROOT"
  fi
}
trap cleanup_fixtures EXIT

# ---------------------------------------------------------------------------
# Per-case iteration loop (port run-evals.ps1:105-252)
# ---------------------------------------------------------------------------

raw_records_file=$(mktemp)
echo '[]' > "$raw_records_file"

for iteration in $(seq 1 "$REPEAT"); do
  for cf in "${selected_case_files[@]}"; do
    case_id_raw=$(basename "$cf" .yaml)
    # T-02-03-01: filename-derived id must be path-safe.
    [[ "$case_id_raw" =~ ^[A-Za-z0-9_-]+$ ]] || die "case filename produces invalid id: $case_id_raw"

    merged=$(merge_yaml_defaults "$DEFAULTS_FILE" "$cf")

    case_id=$(echo "$merged" | jq -r --arg fallback "$case_id_raw" '.id // $fallback')
    # T-02-03-01: declared id must also be path-safe.
    [[ "$case_id" =~ ^[A-Za-z0-9_-]+$ ]] || die "case.id contains invalid characters: $case_id"

    task=$(echo "$merged" | jq -r '.runner.task')
    composer=$(echo "$merged" | jq -r '.runner.composer // "codex"')
    executor=$(echo "$merged" | jq -r '.runner.executor // "codex"')
    bounces=$(echo "$merged" | jq -r '.runner.bounces // 2')
    verify=$(echo "$merged" | jq -r '.runner.verify // false')
    autonomous=$(echo "$merged" | jq -r '.runner.autonomous // false')

    log "Running case: $case_id (iteration $iteration / $REPEAT)"

    fixture="$FIXTURE_ROOT/${case_id}-${iteration}"
    mkdir -p "$fixture"

    # Initialize the fixture as a minimal git repo (port Fixture.ps1:45-56).
    (
      cd "$fixture"
      git -c init.defaultBranch=main init -q
      git -c user.email=harness@example.test -c user.name="Eval Harness" commit --allow-empty -q -m "eval harness init"
    )

    # Seed files (port Fixture.ps1:61-74). Reject '..' anywhere in the path (T-02-03-01 related).
    seed_count=$(echo "$merged" | jq -r '.setup.seed_files // [] | length')
    for ((si = 0; si < seed_count; si++)); do
      s_path=$(echo "$merged" | jq -r --argjson i "$si" '.setup.seed_files[$i].path')
      s_content=$(echo "$merged" | jq -r --argjson i "$si" '.setup.seed_files[$i].content // ""')
      [[ "$s_path" == *..* ]] && die "seed_files path must not contain '..': $s_path"
      mkdir -p "$fixture/$(dirname "$s_path")"
      printf '%s' "$s_content" > "$fixture/$s_path"
    done

    # Copy-from (port Fixture.ps1:78-94).
    copy_count=$(echo "$merged" | jq -r '.setup.copy_from // [] | length')
    for ((ci = 0; ci < copy_count; ci++)); do
      src=$(echo "$merged" | jq -r --argjson i "$ci" '.setup.copy_from[$i].src')
      dst=$(echo "$merged" | jq -r --argjson i "$ci" '.setup.copy_from[$i].dst')
      [[ "$dst" == *..* ]] && die "copy_from dst must not contain '..': $dst"
      src_abs="$REPO_ROOT/$src"
      [[ -e "$src_abs" ]] || die "copy_from src not found: $src_abs"
      mkdir -p "$fixture/$(dirname "$dst")"
      cp -R "$src_abs" "$fixture/$dst"
    done

    stdout_path="$fixture/runner.stdout.log"
    stderr_path="$fixture/runner.stderr.log"

    # Invoke the runner in a subshell scoped to the fixture dir. We avoid
    # string-concat + eval by passing explicit flags (T-02-03-02).
    # -- terminator prevents the task from being parsed as a flag (FIX-WR-05).
    exit_code=0
    verify_flag=""
    [[ "$verify" == "true" ]] && verify_flag="--verify"
    autonomous_flag=""
    [[ "$autonomous" == "true" ]] && autonomous_flag="--autonomous"

    (
      cd "$fixture"
      bash "$RUNNER_PATH_ABS" \
        --composer "$composer" \
        --executor "$executor" \
        --bounces "$bounces" \
        $verify_flag $autonomous_flag \
        -- "$task"
    ) > "$stdout_path" 2> "$stderr_path" || exit_code=$?

    # Capture the newest run dir produced by the runner.
    newest_run=""
    if [[ -d "$fixture/.co-evolution/runs" ]]; then
      newest_run=$(find "$fixture/.co-evolution/runs" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)
    fi
    dest_run="$report_dir/runs/$case_id-$iteration"
    mkdir -p "$dest_run"
    if [[ -n "$newest_run" && -d "$newest_run" ]]; then
      cp -R "$newest_run"/. "$dest_run/"
    else
      log "WARNING: no run artifacts found at $fixture/.co-evolution/runs/ — runner may have failed early"
    fi
    cp "$stdout_path" "$dest_run/runner.stdout.log" 2>/dev/null || true
    cp "$stderr_path" "$dest_run/runner.stderr.log" 2>/dev/null || true

    # Build per-case record.
    if [[ "$SKIP_SCORING" == "true" ]]; then
      record=$(jq -n --arg id "$case_id" --argjson it "$iteration" --argjson ec "$exit_code" --arg status "skipped" \
        '{case_id:$id, iteration:$it, runner_exit_code:$ec, status:$status}')
    else
      if [[ -f "$dest_run/state.json" ]]; then
        if bash "$SCRIPT_DIR/score-run.sh" \
             --case-file "$cf" \
             --defaults-file "$DEFAULTS_FILE" \
             --run-dir "$dest_run" \
             --output-dir "$dest_run" >/dev/null 2>"$dest_run/scorer.stderr.log"; then
          scores_blob=$(cat "$dest_run/scores.json")
          record=$(jq -n --arg id "$case_id" --argjson it "$iteration" --argjson ec "$exit_code" \
                         --argjson blob "$scores_blob" --arg status "scored" \
            '$blob + {case_id:$id, iteration:$it, runner_exit_code:$ec, status:$status}')
        else
          record=$(jq -n --arg id "$case_id" --argjson it "$iteration" --argjson ec "$exit_code" --arg status "scorer-failed" \
            '{case_id:$id, iteration:$it, runner_exit_code:$ec, status:$status}')
        fi
      else
        record=$(jq -n --arg id "$case_id" --argjson it "$iteration" --argjson ec "$exit_code" --arg status "fail" \
          '{case_id:$id, iteration:$it, runner_exit_code:$ec, status:$status}')
      fi
    fi

    # Append record to raw-scores array atomically.
    tmp_records=$(mktemp)
    if jq --argjson r "$record" '. + [$r]' "$raw_records_file" > "$tmp_records"; then
      mv "$tmp_records" "$raw_records_file"
    else
      rm -f "$tmp_records"
      die "raw-scores append failed for case $case_id (iteration $iteration)"
    fi
  done
done

# ---------------------------------------------------------------------------
# Raw-scores + report render (port run-evals.ps1:254-274)
# ---------------------------------------------------------------------------

cp "$raw_records_file" "$report_dir/raw-scores.json"
rm -f "$raw_records_file"

case_table=$(jq -r '
  "| Case | Iter | Robustness | Convergence | Plan | Exec | Verify | Cost | Cross-AI | Composite |",
  "|------|------|------------|-------------|------|------|--------|------|----------|-----------|",
  (.[] | "| \(.case_id) | \(.iteration // 1) | \(.scores.robustness // "?") | \(.scores.convergence // "?") | \(.scores.plan_quality // "?") | \(.scores.execution_fidelity // "?") | \(.scores.verify_accuracy // "?") | \(.scores.cost // "?") | \(.scores.cross_ai_diversity // "?") | \(.composite // "?") |")
' "$report_dir/raw-scores.json")

case_count=$(jq -r 'length' "$report_dir/raw-scores.json")
pass_count=$(jq -r '[.[] | select((.scores.robustness // "FAIL") == "PASS")] | length' "$report_dir/raw-scores.json")
fail_count=$((case_count - pass_count))
composite_avg=$(jq -r '
  [.[] | select(.composite != null) | .composite] as $cs |
  if ($cs | length) == 0 then "n/a"
  else (($cs | add) / ($cs | length) * 1000 | round / 1000 | tostring)
  end
' "$report_dir/raw-scores.json")

details="_Report generated $(date -u +"%Y-%m-%dT%H:%M:%SZ")_"

rendered=$(render_report "$TEMPLATE_FILE" \
  "TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  "CASE_COUNT=$case_count" \
  "PASS_COUNT=$pass_count" \
  "FAIL_COUNT=$fail_count" \
  "COMPOSITE_AVG=$composite_avg" \
  "CASE_TABLE=$case_table" \
  "DETAILS_SECTIONS=$details")
printf '%s' "$rendered" > "$report_dir/report.md"
log "Wrote: $report_dir/report.md"
log "Wrote: $report_dir/raw-scores.json"

# ---------------------------------------------------------------------------
# Exit-code policy (port run-evals.ps1:275-287).
# Exit 1 iff at least one case failed on Robustness. This branch MUST live in
# source (acceptance grep) AND MUST be exercised (Task 2b Tier 2 FAIL scenario).
# ---------------------------------------------------------------------------

robust_fails=$(jq -r '[.[] | select(.status == "fail" or .status == "scorer-failed" or (.scores.robustness // "FAIL") == "FAIL")] | length' "$report_dir/raw-scores.json")
if (( robust_fails > 0 )); then
  log "FAIL: $robust_fails case(s) failed on Robustness dimension"
  exit 1
fi
log "PASS: all cases succeeded on Robustness"
exit 0
