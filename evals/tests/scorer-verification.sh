#!/usr/bin/env bash
# evals/tests/scorer-verification.sh
# Combined verification gate for the Bash eval harness.
#
#   Tier 1: Golden-fixture regression (10 fixtures)       — D-09 Tier 1.
#   Tier 3: Determinism sanity check (1 scenario)         — D-09 Tier 3.
#   Tier 2: Hermetic end-to-end smoke via fake runner     — D-09 Tier 2.
#           (2 scenarios: FAKE_MODE=pass and fail-robustness).
#
# Satisfies ROADMAP SC-3 (multi-platform CI simulation) on any Bash + jq + yq
# environment without pwsh.
#
# Total scenarios: 10 + 1 + 2 = 13. Success: exit 0, final stdout line
# exactly '13/13 scenarios passed'. Leaves no side effects in evals/reports/.
#
# Dependencies: bash, jq, yq (indirectly via evals/score-run.sh + run-evals.sh).

set -euo pipefail

TEST_DIR=$(mktemp -d -t scorer-verify-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 2 levels deep (evals/tests/ -> repo root).
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_ROOT="$REPO_ROOT/runners/codex-ps/evals/tests/fixtures"
FAKE_RUNNER="$REPO_ROOT/evals/tests/fake-runner.sh"

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# Tier 1: iterate every fixture suite under runners/codex-ps/evals/tests/fixtures/
# (glob — NOT a hardcoded list). Score each and assert jq -S '.scores'
# string-equality against EXPECTED.json. T-02-03-08 mitigation.
# ---------------------------------------------------------------------------

for fixture_dir in "$FIXTURES_ROOT"/*/; do
  [[ -d "$fixture_dir" ]] || continue
  suite_name=$(basename "$fixture_dir")
  # T-02-03-01: reject path-unsafe suite names (defense-in-depth; fixture tree
  # is repo-controlled but we never trust directory names implicitly).
  [[ "$suite_name" =~ ^[A-Za-z0-9_-]+$ ]] || { fail "Suite name rejected: $suite_name"; continue; }
  TOTAL=$((TOTAL + 1))

  case_file="$fixture_dir/case.yaml"
  run_dir="$fixture_dir/run"
  expected_file="$fixture_dir/EXPECTED.json"
  out_dir="$TEST_DIR/$suite_name"

  [[ -f "$case_file" ]]     || { fail "Suite $suite_name: missing case.yaml";     continue; }
  [[ -d "$run_dir" ]]       || { fail "Suite $suite_name: missing run/";          continue; }
  [[ -f "$expected_file" ]] || { fail "Suite $suite_name: missing EXPECTED.json"; continue; }

  mkdir -p "$out_dir"
  if ! bash "$REPO_ROOT/evals/score-run.sh" \
         --case-file "$case_file" \
         --run-dir "$run_dir" \
         --output-dir "$out_dir" >/dev/null 2>"$out_dir/scorer.stderr.log"; then
    fail "Suite $suite_name: scorer exited non-zero (see $out_dir/scorer.stderr.log)"
    continue
  fi

  [[ -f "$out_dir/scores.json" ]] || { fail "Suite $suite_name: scores.json not produced"; continue; }

  actual=$(jq -S '.scores' "$out_dir/scores.json")
  expected=$(jq -S '.scores' "$expected_file")
  if [[ "$actual" == "$expected" ]]; then
    pass "Tier 1 / Suite $suite_name"
  else
    fail "Suite $suite_name: scores mismatch"
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    diff <(echo "$expected") <(echo "$actual") >&2 || true
  fi
done

# ---------------------------------------------------------------------------
# Tier 3: determinism check. Score fixture 01-all-pass twice, strip the
# non-deterministic .scored_at field, diff the normalized outputs.
# ---------------------------------------------------------------------------

det_fixture="$FIXTURES_ROOT/01-all-pass"
TOTAL=$((TOTAL + 1))
if [[ -d "$det_fixture" ]]; then
  det_runs_ok=true
  for i in 1 2; do
    out_det="$TEST_DIR/det-$i"
    mkdir -p "$out_det"
    if ! bash "$REPO_ROOT/evals/score-run.sh" \
           --case-file "$det_fixture/case.yaml" \
           --run-dir "$det_fixture/run" \
           --output-dir "$out_det" >/dev/null 2>"$out_det/scorer.stderr.log"; then
      fail "Determinism run $i: scorer exited non-zero"
      det_runs_ok=false
      break
    fi
    jq -S 'del(.scored_at)' "$out_det/scores.json" > "$TEST_DIR/det-$i.norm.json"
  done
  if [[ "$det_runs_ok" == "true" ]]; then
    if diff -q "$TEST_DIR/det-1.norm.json" "$TEST_DIR/det-2.norm.json" >/dev/null; then
      pass "Tier 3 / Determinism: two runs produced byte-identical output (after stripping scored_at)"
    else
      fail "Determinism: two runs produced different output"
      diff "$TEST_DIR/det-1.norm.json" "$TEST_DIR/det-2.norm.json" >&2 || true
    fi
  fi
else
  fail "Determinism fixture not found at: $det_fixture"
fi

# ---------------------------------------------------------------------------
# Tier 2: hermetic end-to-end smoke via the fake runner.
# run-evals.sh --case 01-trivial-task --runner-path evals/tests/fake-runner.sh
# is exercised twice:
#   PASS scenario: FAKE_MODE=pass -> exit 0, scored, robustness=PASS
#   FAIL scenario: FAKE_MODE=fail-robustness -> exit 1 (exercises the
#                  robust_fails>0 branch of run-evals.sh — W-02 execution gate).
# Both scenarios use a pre/post listing diff of evals/reports/ to find the new
# report dir (keeps run-evals.sh's CLI surface stable; orchestrator has no
# output-dir override flag).
# ---------------------------------------------------------------------------

[[ -f "$FAKE_RUNNER" ]] || fail "fake-runner.sh missing at $FAKE_RUNNER — Task 2a not complete"

run_tier2_scenario() {
  # Args: <scenario_name> <fake_mode> <expected_exit_code> <scores_assertion_jq>
  local scenario="$1"
  local fake_mode="$2"
  local expected_exit="$3"
  local scores_jq="$4"

  TOTAL=$((TOTAL + 1))

  local tier2_out="$TEST_DIR/tier2-$scenario"
  mkdir -p "$tier2_out"

  local reports_dir="$REPO_ROOT/evals/reports"
  mkdir -p "$reports_dir"
  local pre_listing="$tier2_out/pre.txt"
  local post_listing="$tier2_out/post.txt"
  ls -1 "$reports_dir" 2>/dev/null | sort > "$pre_listing" || : > "$pre_listing"

  local rc=0
  # Use `|| rc=$?` to capture non-zero exits without aborting under set -e.
  FAKE_MODE="$fake_mode" bash "$REPO_ROOT/evals/run-evals.sh" \
    --case 01-trivial-task \
    --runner-path "$FAKE_RUNNER" \
    > "$tier2_out/run-evals.stdout" 2> "$tier2_out/run-evals.stderr" || rc=$?

  ls -1 "$reports_dir" 2>/dev/null | sort > "$post_listing" || : > "$post_listing"
  local new_report
  new_report=$(comm -13 "$pre_listing" "$post_listing" | tail -1)
  if [[ -z "$new_report" ]]; then
    fail "Tier 2 / $scenario: no new report dir was created under $reports_dir"
    return
  fi
  local report_abs="$reports_dir/$new_report"

  # Track the report for cleanup once all Tier 2 scenarios have run so the
  # test leaves no artifacts in evals/reports/.
  echo "$report_abs" >> "$TEST_DIR/tier2-reports-to-cleanup.txt"

  # Exit-code assertion (expected_exit=0 for PASS, 1 for FAIL).
  if (( rc != expected_exit )); then
    fail "Tier 2 / $scenario: expected exit $expected_exit, got $rc (stderr: $tier2_out/run-evals.stderr)"
    return
  fi

  # D-09 Tier 2: "produced report exists, is non-empty".
  if [[ ! -s "$report_abs/report.md" ]]; then
    fail "Tier 2 / $scenario: report.md missing or empty at $report_abs/report.md"
    return
  fi

  # D-09 Tier 2: "matches schema via jq".
  if [[ ! -f "$report_abs/raw-scores.json" ]]; then
    fail "Tier 2 / $scenario: raw-scores.json missing"
    return
  fi
  if ! jq empty "$report_abs/raw-scores.json" >/dev/null 2>&1; then
    fail "Tier 2 / $scenario: raw-scores.json is not valid JSON"
    return
  fi

  # Exactly 1 record for a single-case invocation.
  local record_count
  record_count=$(jq 'length' "$report_abs/raw-scores.json")
  if [[ "$record_count" != "1" ]]; then
    fail "Tier 2 / $scenario: expected 1 record in raw-scores.json, got $record_count"
    return
  fi

  # Scenario-specific scores assertion.
  if ! jq -e "$scores_jq" "$report_abs/raw-scores.json" >/dev/null 2>&1; then
    fail "Tier 2 / $scenario: scores assertion failed ($scores_jq); record: $(jq -c '.[0]' "$report_abs/raw-scores.json")"
    return
  fi

  pass "Tier 2 / $scenario (exit $rc, report exists + non-empty, JSON valid, record count=1)"
}

# Scenario: PASS — fake-runner produces a completed run; orchestrator exits 0.
# record should be scored with robustness=PASS.
run_tier2_scenario "pass-e2e" "pass" 0 '.[0].status == "scored" and (.[0].scores.robustness == "PASS")'

# Scenario: FAIL — fake-runner produces a failed run; orchestrator's
# robust_fails > 0 branch fires and exits 1.
# Accept any of: scored+robustness=FAIL, scorer-failed, or fail.
run_tier2_scenario "fail-robustness-e2e" "fail-robustness" 1 '(.[0].status == "scored" and .[0].scores.robustness == "FAIL") or (.[0].status == "scorer-failed") or (.[0].status == "fail")'

# Cleanup Tier 2 report dirs so the test leaves no on-disk artifacts in the
# real reports tree.
if [[ -f "$TEST_DIR/tier2-reports-to-cleanup.txt" ]]; then
  while IFS= read -r r; do
    [[ -n "$r" && -d "$r" ]] && rm -rf "$r"
  done < "$TEST_DIR/tier2-reports-to-cleanup.txt"
fi

# ---------------------------------------------------------------------------
# Summary footer
# ---------------------------------------------------------------------------

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
