#!/usr/bin/env bash
# Hermetic smoke test for benchmarks/run-benchmark.sh.
#
# NO LIVE MODEL CALLS. The `claude` and `codex` CLIs are PATH-shadowed by the
# stubs in fixtures/orchestrator/bin/ (fake-runner pattern), and the panel
# harness is swapped out through BENCH_PANEL_SCRIPT. Everything else — the real
# co-evolve-bouncer.sh, the real benchmark-lib.sh, the real corpus linter —
# runs unmodified, which is the point: the orchestrator is exercised against
# the actual bouncer, not a mock of it.
#
# Covered:
#   1.  --check and --dry-run against the fixture corpus
#   2.  cell layout (in.md / final.md / meta.json) for A, B and D
#   3.  meta.json validates as bench-cell/1.0 with the expected field values
#   4.  A-vs-B compose-prompt byte parity (the experiment's core invariant)
#   5.  B reaches pass 2 on the codex seat (token phases prove it)
#   6.  resume does zero work on a second identical run
#   7.  panel cell: final.md copied up, kimi_status/degraded read, ledger debit
#   8.  panel failure -> status failed, exit 1
#   9.  GLM budget exhausted -> status pending-quota, exit 75
#   10. --allow-pending downgrades exit 75 to 0
#
# Usage: bash benchmarks/tests/smoke.sh
# Exit:  0 all assertions passed, 1 otherwise.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(cd "$TESTS_DIR/.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures/orchestrator"
RUNNER="$BENCH_DIR/run-benchmark.sh"

PASSES=0
FAILURES=0

pass() { PASSES=$((PASSES + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf '  FAIL %s\n' "$1"; [[ $# -lt 2 ]] || printf '       %s\n' "$2"; }

check_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$name"
  else
    fail "$name" "expected '$expected', got '$actual'"
  fi
}

check_file() {
  local name="$1" path="$2"
  if [[ -s "$path" ]]; then pass "$name"; else fail "$name" "missing or empty: $path"; fi
}

check_absent() {
  local name="$1" path="$2"
  if [[ ! -e "$path" ]]; then pass "$name"; else fail "$name" "should not exist: $path"; fi
}

# --- Environment -------------------------------------------------------------

command -v jq >/dev/null 2>&1 || { echo "smoke.sh requires jq" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "smoke.sh requires yq" >&2; exit 1; }

WORK=$(mktemp -d -t bench-smoke-XXXXXX) || { echo "smoke.sh: mktemp failed" >&2; exit 1; }
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT

# The stub bin dir is copied into the work tree so the executable bit can be
# set without mutating the checkout (git on Windows does not reliably carry it).
STUB_BIN="$WORK/bin"
mkdir -p "$STUB_BIN"
cp "$FIXTURES/bin/claude" "$FIXTURES/bin/codex" "$FIXTURES/bin/run-panel-stub.sh" "$STUB_BIN/"
chmod +x "$STUB_BIN/claude" "$STUB_BIN/codex" "$STUB_BIN/run-panel-stub.sh"

RESULTS="$WORK/results"
CALLS="$WORK/stub-calls.log"
: > "$CALLS"

export PATH="$STUB_BIN:$PATH"
export BENCH_STUB_CALLS="$CALLS"
export BENCH_PANEL_SCRIPT="$STUB_BIN/run-panel-stub.sh"

BATCH="s1"
BATCH_DIR="$RESULTS/$BATCH"

# Guard against a silent fallthrough to a real CLI: if PATH shadowing failed,
# every assertion below would still "pass" while spending real money.
resolved_claude=$(command -v claude || true)
check_eq "PATH shadows the claude CLI" "$STUB_BIN/claude" "$resolved_claude"
resolved_codex=$(command -v codex || true)
check_eq "PATH shadows the codex CLI" "$STUB_BIN/codex" "$resolved_codex"

run_bench() {
  bash "$RUNNER" \
    --corpus "$FIXTURES/corpus" \
    --results-root "$RESULTS" \
    --batch "$BATCH" \
    "$@"
}

stub_calls() { wc -l < "$CALLS" | tr -d '[:space:]'; }

# --- 1. --check and --dry-run ------------------------------------------------

echo "-- check / dry-run"
check_out=$(run_bench --conditions "$FIXTURES/conditions-mini.yaml" --check 2>&1); check_rc=$?
check_eq "--check exits 0 on the fixture corpus" "0" "$check_rc"
if [[ "$check_out" == *"CHECK: PASS"* ]]; then
  pass "--check reports PASS"
else
  fail "--check reports PASS" "$check_out"
fi

dry_out=$(run_bench --conditions "$FIXTURES/conditions-mini.yaml" --dry-run 2>&1); dry_rc=$?
check_eq "--dry-run exits 0" "0" "$dry_rc"
if [[ "$dry_out" == *"t1: A=absent B=absent D=absent"* ]]; then
  pass "--dry-run prints the task x condition matrix"
else
  fail "--dry-run prints the task x condition matrix" "$dry_out"
fi
if [[ "$dry_out" == *"Path guard: OK"* ]]; then
  pass "--dry-run runs the worst-case path guard"
else
  fail "--dry-run runs the worst-case path guard" "$dry_out"
fi
check_eq "--dry-run spends no model calls" "0" "$(stub_calls)"
check_absent "--dry-run creates no batch dir" "$BATCH_DIR"

# --- 2. First batch: A, B, D -------------------------------------------------

echo "-- batch run (A, B, D)"
run_out=$(run_bench --conditions "$FIXTURES/conditions-mini.yaml" 2>&1); run_rc=$?
check_eq "batch run exits 0" "0" "$run_rc"
if [[ "$run_out" == *"BENCH SUMMARY:"* ]]; then
  pass "batch run prints a summary line"
else
  fail "batch run prints a summary line" "$run_out"
fi

for cond in A B D; do
  cell="$BATCH_DIR/t1/$cond"
  check_file "cell t1/$cond has in.md"    "$cell/in.md"
  check_file "cell t1/$cond has final.md" "$cell/final.md"
  check_file "cell t1/$cond has meta.json" "$cell/meta.json"
done

# meta.json schema + values, per condition.
meta_field() { jq -r "$2" "$BATCH_DIR/t1/$1/meta.json" 2>/dev/null; }

for cond in A B D; do
  check_eq "t1/$cond meta schema"     "bench-cell/1.0" "$(meta_field "$cond" '.schema')"
  check_eq "t1/$cond meta status"     "complete"       "$(meta_field "$cond" '.status')"
  check_eq "t1/$cond meta task"       "t1"             "$(meta_field "$cond" '.task')"
  check_eq "t1/$cond meta condition"  "$cond"          "$(meta_field "$cond" '.condition')"
  check_eq "t1/$cond meta markers"    "0"              "$(meta_field "$cond" '.markers_final')"
  check_eq "t1/$cond meta glm_calls"  "0"              "$(meta_field "$cond" '.glm_calls')"
  check_eq "t1/$cond meta degraded"   "false"          "$(meta_field "$cond" '.degraded')"
  check_eq "t1/$cond meta error"      "null"           "$(meta_field "$cond" '.error')"
  check_eq "t1/$cond meta has every bench-cell/1.0 key" "true" \
    "$(meta_field "$cond" '[has("schema","batch","task","condition","kind","status","wall_secs","word_count","convergence_status","markers_final","glm_calls","kimi_status","degraded","tokens","error")] | all')"
  check_eq "t1/$cond meta wall_secs is a number" "number" "$(meta_field "$cond" '.wall_secs | type')"
  check_eq "t1/$cond meta tokens is an object"   "object" "$(meta_field "$cond" '.tokens | type')"
  if [[ "$(meta_field "$cond" '.word_count')" -gt 100 ]]; then
    pass "t1/$cond meta word_count is plausible"
  else
    fail "t1/$cond meta word_count is plausible" "got $(meta_field "$cond" '.word_count')"
  fi
done

check_eq "t1/A kind"                "solo"      "$(meta_field A '.kind')"
check_eq "t1/A convergence_status"  "null"      "$(meta_field A '.convergence_status')"
check_eq "t1/A captures claude cost" "0.0123"   "$(meta_field A '.tokens.totals.claude_cost_usd')"
check_eq "t1/B kind"                "bouncer"   "$(meta_field B '.kind')"
check_eq "t1/B convergence_status"  "converged" "$(meta_field B '.convergence_status')"
check_eq "t1/D convergence_status"  "converged" "$(meta_field D '.convergence_status')"

# The bouncer's seat semantics put AGENT_B on even passes, so a B cell that
# never reached pass 2 would silently be a same-model run. The codex-stderr
# token phase is the proof that the cross-vendor seat actually ran.
check_eq "t1/B reached the codex composer pass" "2048" \
  "$(meta_field B '.tokens.totals.codex_total_tokens')"
check_eq "t1/D never touched the codex seat" "0" \
  "$(meta_field D '.tokens.totals.codex_total_tokens')"

# --- 3. Compose-prompt parity ------------------------------------------------
#
# The experiment's central invariant: condition A must issue the byte-identical
# compose prompt the bouncer builds for condition B. Compare A's saved prompt
# against the .compose-prompt.md artifact the real bouncer wrote in B's run dir
# (co-evolve-bouncer.sh:772/787).

echo "-- A-vs-B compose prompt parity"
b_prompt=$(find "$BATCH_DIR/t1/B/run" -mindepth 2 -maxdepth 2 -name '.compose-prompt.md' | head -1)
if [[ -z "$b_prompt" ]]; then
  fail "found B's .compose-prompt.md artifact" "none under $BATCH_DIR/t1/B/run"
else
  pass "found B's .compose-prompt.md artifact"
  if cmp -s "$BATCH_DIR/t1/A/compose-prompt.md" "$b_prompt"; then
    pass "A's compose-prompt.md is byte-identical to B's bouncer compose prompt"
  else
    fail "A's compose-prompt.md is byte-identical to B's bouncer compose prompt" \
      "$(cmp "$BATCH_DIR/t1/A/compose-prompt.md" "$b_prompt" 2>&1)"
  fi
fi

# --- 4. Resume does zero work ------------------------------------------------

echo "-- resume"
calls_before=$(stub_calls)
metas_before=$(md5sum "$BATCH_DIR"/t1/*/meta.json | sort)

resume_out=$(run_bench --conditions "$FIXTURES/conditions-mini.yaml" 2>&1); resume_rc=$?
check_eq "resume run exits 0" "0" "$resume_rc"
check_eq "resume run makes no model calls" "$calls_before" "$(stub_calls)"

metas_after=$(md5sum "$BATCH_DIR"/t1/*/meta.json | sort)
check_eq "resume run leaves every meta.json untouched" "$metas_before" "$metas_after"
if [[ "$resume_out" == *"complete=3 (skipped=3)"* ]]; then
  pass "resume run reports 3 skipped cells"
else
  fail "resume run reports 3 skipped cells" "$resume_out"
fi

# --- 5. Panel cell -----------------------------------------------------------

echo "-- panel cell (stubbed harness)"
panel_out=$(run_bench --conditions "$FIXTURES/conditions-panel.yaml" --glm-budget 5 2>&1); panel_rc=$?
check_eq "panel run exits 0" "0" "$panel_rc"
check_file "cell t1/C has final.md" "$BATCH_DIR/t1/C/final.md"
check_eq "t1/C kind"        "panel"    "$(meta_field C '.kind')"
check_eq "t1/C status"      "complete" "$(meta_field C '.status')"
check_eq "t1/C kimi_status" "ok"       "$(meta_field C '.kimi_status')"
check_eq "t1/C degraded"    "false"    "$(meta_field C '.degraded')"
check_eq "t1/C glm_calls"   "1"        "$(meta_field C '.glm_calls')"
check_eq "GLM ledger debited once" "1" \
  "$(jq -r '.calls' "$BATCH_DIR/glm-ledger.json" 2>/dev/null)"

# --- 6. Panel failure --------------------------------------------------------

echo "-- panel failure"
fail_out=$(STUB_PANEL_RC=1 run_bench --conditions "$FIXTURES/conditions-panel.yaml" \
  --glm-budget 5 --force-cell t1/C 2>&1); fail_rc=$?
check_eq "failed cell exits 1" "1" "$fail_rc"
check_eq "t1/C status after failure" "failed" "$(meta_field C '.status')"
check_absent "failed cell writes no final.md" "$BATCH_DIR/t1/C/final.md"
if [[ "$(meta_field C '.error')" == *"exited 1"* ]]; then
  pass "failed cell records the error in meta.json"
else
  fail "failed cell records the error in meta.json" "$(meta_field C '.error')"
fi

# --- 7. GLM budget exhausted -> pending-quota, exit 75 -----------------------

echo "-- pending-quota"
calls_before=$(stub_calls)
quota_out=$(run_bench --conditions "$FIXTURES/conditions-panel.yaml" --glm-budget 0 2>&1); quota_rc=$?
check_eq "exhausted GLM budget exits 75" "75" "$quota_rc"
check_eq "t1/C status is pending-quota" "pending-quota" "$(meta_field C '.status')"
check_absent "pending-quota cell writes no final.md" "$BATCH_DIR/t1/C/final.md"
check_eq "pending-quota cell spends nothing" "$calls_before" "$(stub_calls)"
if [[ "$quota_out" == *"pending-quota=1"* ]]; then
  pass "summary counts the pending cell"
else
  fail "summary counts the pending cell" "$quota_out"
fi

allow_out=$(run_bench --conditions "$FIXTURES/conditions-panel.yaml" --glm-budget 0 --allow-pending 2>&1)
allow_rc=$?
check_eq "--allow-pending downgrades 75 to 0" "0" "$allow_rc"
check_eq "--allow-pending still records pending-quota" "pending-quota" "$(meta_field C '.status')"

# --- Result ------------------------------------------------------------------

echo ""
if (( FAILURES == 0 )); then
  echo "benchmarks/tests/smoke.sh: PASS ($PASSES assertions)"
  exit 0
fi
echo "benchmarks/tests/smoke.sh: $FAILURES FAILURE(S) of $((PASSES + FAILURES)) assertions"
exit 1
