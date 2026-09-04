#!/usr/bin/env bash

# benchmarks/tests/test-site-export.sh — contract tests for
# benchmarks/export-site-data.sh.
#
# Every number asserted here was computed by hand from the fixture batch under
# fixtures/site/, so a regression in the aggregation shows up as a mismatch
# against arithmetic rather than against the previous run's output.
#
# Fixture: 2 tasks (t1 medium, t2 easy) x 3 conditions (A, B, D) x 2 judges
# (fable, codex). Word counts A=100, B=200, D=150. Condition D leaks
# sanitization on t2, so both D pairs on t2 are unjudged for both judges.
#
#   judge  pair   t1              t2
#   fable  A-B    B wins          B wins
#   fable  A-D    A wins          sanitize-leak
#   fable  B-D    tie             sanitize-leak
#   codex  A-B    B wins          A wins
#   codex  A-D    D wins          sanitize-leak
#   codex  B-D    B wins          sanitize-leak
#
# Ties count half a win to each side and leaked pairs leave both the numerator
# and the denominator (PREREGISTRATION.md section 4), which gives:
#
#   fable  A 1.0/3 = 33.33%   B 2.5/3 = 83.33%   D 0.5/2 = 25.00%
#   codex  A 1.0/3 = 33.33%   B 2.0/3 = 66.67%   D 1.0/2 = 50.00%
#
#   captured cost   A 2 x 0.10 = 0.20   B 2 x 0.50 = 1.00   D 2 x 0.25 = 0.50
#   mean wall secs  A 10               B 60               D 40
#
# No model calls, no network. Exit 0 all scenarios pass, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
EXPORT="$BENCH_DIR/export-site-data.sh"
FIXTURE="$SCRIPT_DIR/fixtures/site"
SCHEMA="$REPO_ROOT/docs/data/schema.json"
VALIDATOR="$BENCH_DIR/lib/validate-schema.jq"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required"; exit 1; }
[[ -x "$EXPORT" || -f "$EXPORT" ]] || { echo "FAIL: $EXPORT not found"; exit 1; }

TEST_DIR=$(mktemp -d -t bench-site-test-XXXXXX) || { echo "FAIL: no temp dir"; exit 1; }
trap 'rm -rf -- "$TEST_DIR"' EXIT

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

check() { # description expected actual
  TOTAL=$((TOTAL + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (want '$2', got '$3')"; fi
}

q() { jq -r "$1" "$OUT"; }

# --- Scenario 1: the export runs clean on the fixture batch ------------------

OUT="$TEST_DIR/docs/data/fx1.json"
run_log="$TEST_DIR/export.log"
bash "$EXPORT" \
  --batch-dir "$FIXTURE/batch/fx1" \
  --docs-dir "$TEST_DIR/docs" \
  --corpus "$FIXTURE/corpus" \
  --conditions "$FIXTURE/conditions.yaml" \
  --judges fable,codex \
  --primary-judge fable > "$run_log" 2>&1
rc=$?

TOTAL=$((TOTAL + 1))
if (( rc == 0 )); then pass "export exits 0 on the fixture batch"
else fail "export exits 0 on the fixture batch (rc=$rc)"; sed 's/^/    /' "$run_log"; fi

TOTAL=$((TOTAL + 1))
if [[ -s "$OUT" ]]; then pass "batch data file is written"
else fail "batch data file is written"; echo "no $OUT — remaining assertions skipped"; exit 1; fi

# --- Scenario 2: output validates against the published schema ---------------

TOTAL=$((TOTAL + 1))
violations=$(jq -r -n --slurpfile schema "$SCHEMA" --slurpfile doc "$OUT" -f "$VALIDATOR" 2>&1)
if [[ -z "$violations" ]]; then pass "output validates against docs/data/schema.json"
else fail "output validates against docs/data/schema.json"; printf '    %s\n' "$violations"; fi

# The validator has to be able to fail, or scenario 2 proves nothing.
TOTAL=$((TOTAL + 1))
jq '.batch = 42 | .tasks[0].smuggled_prompt = "secret"' "$OUT" > "$TEST_DIR/broken.json"
broken=$(jq -r -n --slurpfile schema "$SCHEMA" --slurpfile doc "$TEST_DIR/broken.json" -f "$VALIDATOR" 2>&1)
if [[ "$broken" == *"expected type string"* && "$broken" == *"smuggled_prompt"* ]]; then
  pass "validator rejects a wrong type and an unexpected property"
else fail "validator rejects a wrong type and an unexpected property (got: $broken)"; fi

# --- Scenario 3: shape and coverage ------------------------------------------

check "schema tag"              "bench-site/1.0" "$(q '.schema')"
check "batch id from dir name"  "fx1"            "$(q '.batch')"
check "task count"              "2"              "$(q '.completeness.tasks')"
check "condition count"         "3"              "$(q '.completeness.conditions')"
check "expected pairs / judge"  "6"              "$(q '.completeness.expected_pairs_per_judge')"
check "all cells complete"      "true"           "$(q '.completeness.generation_cells_complete')"
check "no degraded cells"       "0"              "$(q '.completeness.degraded_cells | length')"
check "fable verdicts on disk"  "6"              "$(q '.completeness.per_judge[] | select(.judge=="fable") | .verdict_files')"
check "fable unjudged"          "0"              "$(q '.completeness.per_judge[] | select(.judge=="fable") | .unjudged')"
check "excluded document"       "t2/D/sanitize-leak" \
      "$(q '.completeness.excluded_documents[] | [.task,.condition,.why] | join("/")')"

# --- Scenario 4: per-judge win rates -----------------------------------------

check "fable A win rate" "33.33" "$(q '.conditions[]|select(.id=="A").per_judge.fable.score')"
check "fable B win rate" "83.33" "$(q '.conditions[]|select(.id=="B").per_judge.fable.score')"
check "fable D win rate" "25"    "$(q '.conditions[]|select(.id=="D").per_judge.fable.score')"
check "codex A win rate" "33.33" "$(q '.conditions[]|select(.id=="A").per_judge.codex.score')"
check "codex B win rate" "66.67" "$(q '.conditions[]|select(.id=="B").per_judge.codex.score')"
check "codex D win rate" "50"    "$(q '.conditions[]|select(.id=="D").per_judge.codex.score')"

check "fable B wins (tie = half)" "2.5" "$(q '.conditions[]|select(.id=="B").per_judge.fable.wins')"
check "fable B comparisons"       "3"   "$(q '.conditions[]|select(.id=="B").per_judge.fable.comparisons')"
check "leaked pairs leave the denominator" "2" \
      "$(q '.conditions[]|select(.id=="D").per_judge.fable.comparisons')"
check "leaked pairs counted as excluded"   "2" \
      "$(q '.conditions[]|select(.id=="D").per_judge.fable.excluded')"
check "fable B-vs-D matrix cell" "0.5/1" \
      "$(q '.conditions[]|select(.id=="B").per_judge.fable.vs.D | "\(.wins)/\(.n)"')"

# Bradley-Terry is an iterative fixed point, so the test pins its ordering and
# its normalization rather than digits nothing can check by hand.
check "BT strengths normalize to 1 (fable)" "1" \
      "$(q '[.conditions[].per_judge.fable.bt_strength] | add | . * 1000 | round / 1000')"
check "BT order tracks win rate for fable" "B,A,D" \
      "$(q '[.conditions[] | {id, s: .per_judge.fable.bt_strength}] | sort_by(-.s) | map(.id) | join(",")')"
check "BT order tracks win rate for codex" "B,D,A" \
      "$(q '[.conditions[] | {id, s: .per_judge.codex.bt_strength}] | sort_by(-.s) | map(.id) | join(",")')"

# --- Scenario 5: process stats and captured cost -----------------------------

check "A captured cost" "0.2" "$(q '.conditions[]|select(.id=="A").captured_cost_usd')"
check "B captured cost" "1"   "$(q '.conditions[]|select(.id=="B").captured_cost_usd')"
check "D captured cost" "0.5" "$(q '.conditions[]|select(.id=="D").captured_cost_usd')"
check "B mean wall secs" "60" "$(q '.conditions[]|select(.id=="B").mean_wall_secs')"
check "B mean words"    "200" "$(q '.conditions[]|select(.id=="B").mean_words')"
check "B converged"       "2" "$(q '.conditions[]|select(.id=="B").converged')"

# --- Scenario 6: condition manifest parsing ----------------------------------
# --agents "claude,codex" carries the same comma the inline YAML list uses as
# its separator, and reviewers is an unquoted inline sequence. Both have broken
# naive parsers before.

check "B seats"  "claude,codex"                        "$(q '.conditions[]|select(.id=="B").seats|join(",")')"
check "B models" "claude-fable-5,codex CLI default"    "$(q '.conditions[]|select(.id=="B").models|join(",")')"
check "D models" "claude-fable-5,claude-fable-5"       "$(q '.conditions[]|select(.id=="D").models|join(",")')"
check "A models" "claude-fable-5"                      "$(q '.conditions[]|select(.id=="A").models|join(",")')"

# An empty `effort` must not shift the fields after it.
check "codex judge model"  "fixture-codex" "$(q '.suite.judges[]|select(.id=="codex").model')"
check "codex judge effort" ""              "$(q '.suite.judges[]|select(.id=="codex").effort')"
check "codex model assert" "verified"      "$(q '.suite.judges[]|select(.id=="codex").model_assert')"

# --- Scenario 7: pre-registered comparisons ----------------------------------

check "B-vs-A is primary"          "true" "$(q '.preregistered[]|select(.treatment=="B" and .baseline=="A").primary')"
check "B-vs-A fable wins"          "2"    "$(q '.preregistered[]|select(.baseline=="A").per_judge[]|select(.judge=="fable").treatment_wins')"
check "B-vs-A codex wins"          "1"    "$(q '.preregistered[]|select(.baseline=="A").per_judge[]|select(.judge=="codex").treatment_wins')"
check "B-vs-A codex losses"        "1"    "$(q '.preregistered[]|select(.baseline=="A").per_judge[]|select(.judge=="codex").baseline_wins')"
check "B-vs-D fable non-decisive"  "2"    "$(q '.preregistered[]|select(.baseline=="D").per_judge[]|select(.judge=="fable").non_decisive')"
check "sign test outcome"  "no-evidence"  "$(q '.preregistered[]|select(.baseline=="A").sign_test.outcome')"
check "sign test flags the short N" "true" "$(q '.preregistered[]|select(.baseline=="A").sign_test.n_caveat')"
check "B-vs-D carries no sign test" "null" "$(q '.preregistered[]|select(.baseline=="D").sign_test')"
check "per-task verdict passes non-decisive through" "sanitize-leak" \
      "$(q '.preregistered[]|select(.baseline=="D").per_task[]|select(.task=="t2").verdict')"
check "difficulty cut, easy" "1/1/0" \
      "$(q '.preregistered[]|select(.baseline=="A").per_difficulty[]|select(.difficulty=="easy")|"\(.tasks)/\(.treatment_wins)/\(.baseline_wins)"')"

# --- Scenario 8: integrity, agreement, length bias ---------------------------

check "fable decisive"      "3" "$(q '.integrity[]|select(.judge=="fable").decisive')"
check "fable ties"          "1" "$(q '.integrity[]|select(.judge=="fable").ties')"
check "fable sanitize-leak" "2" "$(q '.integrity[]|select(.judge=="fable").sanitize_leak')"
check "codex decisive"      "4" "$(q '.integrity[]|select(.judge=="codex").decisive')"

check "comparable pairs"     "6" "$(q '.agreement.comparable_pairs')"
check "unanimous pairs"      "3" "$(q '.agreement.unanimous')"
check "unanimous + decisive" "1" "$(q '.agreement.unanimous_decisive')"

check "fable longer-doc wins" "2/3" "$(q '.length_bias[]|select(.judge=="fable")|"\(.longer_won)/\(.comparable_decisive)"')"
check "codex longer-doc wins" "3/4" "$(q '.length_bias[]|select(.judge=="codex")|"\(.longer_won)/\(.comparable_decisive)"')"

# --- Scenario 9: task drill-down ---------------------------------------------

check "task difficulty"      "medium" "$(q '.tasks[]|select(.id=="t1").difficulty')"
check "pairs per task"       "3"      "$(q '.tasks[]|select(.id=="t1").pairs|length')"
check "t1 A-B winner (fable)" "B"     "$(q '.tasks[]|select(.id=="t1").pairs[]|select(.x=="A" and .y=="B").judges.fable.winner')"
check "t1 B-D outcome (fable)" "tie"  "$(q '.tasks[]|select(.id=="t1").pairs[]|select(.x=="B" and .y=="D").judges.fable.outcome')"
check "t2 A-D outcome" "sanitize-leak" "$(q '.tasks[]|select(.id=="t2").pairs[]|select(.x=="A" and .y=="D").judges.codex.outcome')"
check "cell cost is per-cell, not per-condition" "0.5" \
      "$(q '.tasks[]|select(.id=="t1").cells.B.cost_usd')"

# --- Scenario 10: nothing publishable-by-mistake ------------------------------
# The verdict files carry judge reasons and verbatim quotes from the plans, and
# the cells carry the plan text itself. None of it may reach docs/.

TOTAL=$((TOTAL + 1))
leaks=$(jq -r '[paths(scalars) | map(tostring) | .[]] | map(ascii_downcase)
               | map(select(. == "reasons" or . == "quote" or . == "evidence"
                            or . == "raw" or . == "trials" or . == "prompt"
                            or . == "final" or . == "transcript" or . == "detail"))
               | unique | join(", ")' "$OUT")
if [[ -z "$leaks" ]]; then pass "no prompt, plan or transcript field in the export"
else fail "no prompt, plan or transcript field in the export (found: $leaks)"; fi

# Searched through jq rather than grep: the export is one long UTF-8 line, and
# jq walks the parsed strings instead of the raw bytes.
TOTAL=$((TOTAL + 1))
bodies=$(jq -r '[.. | strings | select(test("Fixture task body|Fixture plan|Body for t"))] | length' "$OUT")
if [[ "$bodies" == "0" ]]; then pass "no corpus or plan body text in the export"
else fail "no corpus or plan body text in the export ($bodies string(s) matched)"; fi

# --- Scenario 11: the index ---------------------------------------------------

IDX="$TEST_DIR/docs/data/index.json"
TOTAL=$((TOTAL + 1))
if [[ -s "$IDX" ]]; then pass "index file is written"; else fail "index file is written"; fi
check "index schema"        "bench-site-index/1.0" "$(jq -r '.schema' "$IDX")"
check "index lists fx1"     "fx1"                  "$(jq -r '.batches[0].batch' "$IDX")"
check "index default batch" "fx1"                  "$(jq -r '.default_batch' "$IDX")"
check "index points at the data file" "data/fx1.json" "$(jq -r '.batches[0].file' "$IDX")"

# --- Scenario 12: a missing batch fails loudly --------------------------------

TOTAL=$((TOTAL + 1))
if bash "$EXPORT" --batch-dir "$TEST_DIR/no-such-batch" --docs-dir "$TEST_DIR/docs" >/dev/null 2>&1; then
  fail "a nonexistent batch dir exits nonzero"
else pass "a nonexistent batch dir exits nonzero"; fi

# -----------------------------------------------------------------------------

printf '\n%d/%d checks passed\n' "$PASSED" "$TOTAL"
(( PASSED == TOTAL )) || exit 1
exit 0
