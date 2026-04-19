#!/usr/bin/env bash
# evals/tests/scorer-verification.sh
# Combined verification gate for the Bash eval harness.
#
#   Tier 1: Golden-fixture regression (10 fixtures)       — D-09 Tier 1.
#   Tier 3: Determinism sanity check (1 scenario)         — D-09 Tier 3.
#   Tier 2: Hermetic end-to-end smoke via fake runner     — D-09 Tier 2.
#           (2 scenarios: FAKE_MODE=pass and fail-robustness).
#   Tier 4: Real-runner contract smoke (1 scenario)       — D-07 contract gate.
#           Exercises dev-review/codex/dev-review.sh end-to-end with PATH-stubbed
#           claude + codex CLIs. Regression barrier for WR-01/WR-02/WR-04.
#
# Satisfies ROADMAP SC-3 (multi-platform CI simulation) on any Bash + jq + yq
# environment without pwsh.
#
# Total scenarios: 10 + 1 + 2 + 1 = 14. Success: exit 0, final stdout line
# exactly '14/14 scenarios passed'. Leaves no side effects in evals/reports/.
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

# ---------------------------------------------------------------------------
# Tier 4: Real-runner contract smoke — D-07 of 08.1-CONTEXT.md.
# Exercises the REAL dev-review/codex/dev-review.sh end-to-end via run-evals.sh
# with PATH-stubbed claude + codex CLIs. This is the regression barrier that
# would have caught WR-01 / WR-02 / WR-04 before ship-time review.
#
# Why this scenario exists: Tier 2 uses fake-runner.sh which DOES emit the full
# contract shape — so a missing .status or missing outputs/compose.txt in the
# REAL runner slipped through every pre-ship gate. Tier 4 closes that gap.
#
# Assertions (see evals/RUNNER-CONTRACT.md for field semantics):
#   1. state.json top-level .status in {completed, partial, failed} and NOT
#      stuck at the 'pending' init sentinel (WR-01 / D-02).
#   2. outputs/compose.txt exists and is non-empty (WR-02 / D-03).
#   3. run dir was discovered under $fixture/.co-evolution/runs/ — harness did
#      NOT emit "no run artifacts found" (WR-04 / D-05).
#   4. Contract field names split into SCORER-READ (7, both runner-write
#      surface AND score-run.sh) + RUNNER-ONLY (6, runner-write surface only).
#      Runner-write surface = lib/co-evolution.sh + dev-review/codex/dev-review.sh
#      because init_state_json lives in the sourced library. D-08 poor-man's
#      lint per CONTEXT.md §decisions D-08.
#   5. scorer produced non-null, non-FAIL Robustness (proves // "unknown"
#      fallback did NOT fire — real runner wrote a real .status).
# ---------------------------------------------------------------------------

run_tier4_real_runner() {
  TOTAL=$((TOTAL + 1))

  local t4_dir="$TEST_DIR/tier4-real-runner"
  mkdir -p "$t4_dir/bin"

  # PATH-stub claude: drains stdin with a read-loop (NOT `cat >/dev/null`) to
  # avoid SIGPIPE against the runner's stdin producer. `cat` closing stdin
  # prematurely can propagate a broken pipe that crashes the producer on
  # strict-mode bash. The claude stub is present even though 01-trivial-task
  # runs codex-only — dev-review.sh's require_agent_cli probes claude when any
  # role is claude-based, and defense-in-depth dictates a claude stub on PATH
  # for future cases.
  cat > "$t4_dir/bin/claude" <<'STUB'
#!/usr/bin/env bash
# Version-probe fast-path (dev-review.sh's require_agent_cli does `command -v`
# which needs the binary present; some invocations pass --version).
for arg in "$@"; do
  case "$arg" in
    --version|-v|version)
      echo "claude 1.0.0 (tier4-stub)"
      exit 0
      ;;
  esac
done
# Drain stdin via read-loop to avoid SIGPIPE against the runner producer.
while IFS= read -r _line; do :; done
# Default: emit a minimal plan satisfying plan_quality heading regex + word
# count (01-trivial-task sets min_word_count=40). claude writes to stdout.
cat <<'PLAN'
# Tier 4 Contract Smoke Plan

## Approach

This is a hermetic stub plan emitted by the scorer-verification Tier 4
real-runner contract smoke test. It exists solely to satisfy the plan_quality
heading regex plus the min_word_count threshold; it is not a real plan.

## Files to Change

- (no file changes)

## Risks

- None identified. Stubbed CLI produces a fixed plan with no side effects.
PLAN
STUB
  chmod +x "$t4_dir/bin/claude"

  # PATH-stub codex: dev-review.sh invokes `codex exec ... -o OUTPUT_FILE`
  # (see lib/co-evolution.sh::invoke_codex). The stub must:
  #   (1) drain stdin via read-loop (no SIGPIPE),
  #   (2) parse args to find `-o FILE` and write the plan there,
  #   (3) handle `--version` / `-v` fast-path for require_agent_cli probes.
  cat > "$t4_dir/bin/codex" <<'STUB'
#!/usr/bin/env bash
# Version-probe fast-path.
for arg in "$@"; do
  case "$arg" in
    --version|-v|version)
      echo "codex 0.117.0 (tier4-stub)"
      exit 0
      ;;
  esac
done

# Parse args to find -o FILE (codex exec writes output to this path).
output_file=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    output_file="$arg"
    prev=""
    continue
  fi
  prev="$arg"
done

# Drain stdin via read-loop to avoid SIGPIPE against the runner producer.
while IFS= read -r _line; do :; done

# Produce a minimal valid plan. If -o was given, write to that file;
# otherwise emit to stdout as a fallback (some codex invocations omit -o).
plan_content=$(cat <<'PLAN'
# Tier 4 Contract Smoke Plan

## Approach

This is a hermetic stub plan emitted by the scorer-verification Tier 4
real-runner contract smoke test. It exists solely to satisfy the plan_quality
heading regex plus the min_word_count threshold; it is not a real plan.

## Files to Change

- (no file changes)

## Risks

- None identified. Stubbed codex produces a fixed plan with no side effects.
PLAN
)

if [[ -n "$output_file" ]]; then
  printf '%s\n' "$plan_content" > "$output_file"
else
  printf '%s\n' "$plan_content"
fi
exit 0
STUB
  chmod +x "$t4_dir/bin/codex"

  # Pre-listing snapshot for report-dir discovery (matches Tier 2 pattern).
  local reports_dir="$REPO_ROOT/evals/reports"
  mkdir -p "$reports_dir"
  local pre_listing="$t4_dir/pre.txt"
  local post_listing="$t4_dir/post.txt"
  ls -1 "$reports_dir" 2>/dev/null | sort > "$pre_listing" || : > "$pre_listing"

  # Invoke real runner through the harness with an explicit 120s timeout.
  # Expected runtime <30s; the wrapper is belt-and-suspenders against runner
  # hang (e.g. stuck REVISE loop) — we own our own timeout rather than
  # inheriting CI's outer bound. Exit code 124 = timeout hit.
  local rc=0
  PATH="$t4_dir/bin:$PATH" timeout 120 bash "$REPO_ROOT/evals/run-evals.sh" \
    --case 01-trivial-task \
    --runner-path "$REPO_ROOT/dev-review/codex/dev-review.sh" \
    > "$t4_dir/run-evals.stdout" 2> "$t4_dir/run-evals.stderr" || rc=$?

  if [[ "$rc" -eq 124 ]]; then
    fail "Tier 4: run-evals.sh exceeded 120s timeout — runner hang suspected (see $t4_dir/run-evals.stderr)"
    return
  fi

  ls -1 "$reports_dir" 2>/dev/null | sort > "$post_listing" || : > "$post_listing"
  local new_report
  new_report=$(comm -13 "$pre_listing" "$post_listing" | tail -1)
  if [[ -z "$new_report" ]]; then
    fail "Tier 4: no new report dir created under $reports_dir (runner or harness failed; see $t4_dir/run-evals.stderr)"
    return
  fi
  local report_abs="$reports_dir/$new_report"
  # Track for cleanup alongside Tier 2 (reuse the same cleanup list).
  echo "$report_abs" >> "$TEST_DIR/tier2-reports-to-cleanup.txt"

  # --- Assertion 3 (WR-04): harness found the run dir under fixture subtree ---
  if grep -q "no run artifacts found" "$t4_dir/run-evals.stdout" \
     || grep -q "no run artifacts found" "$t4_dir/run-evals.stderr"; then
    fail "Tier 4 / WR-04 regression: harness logged 'no run artifacts found' — real runner wrote outside \$fixture/.co-evolution/runs/"
    return
  fi

  # Discover the per-case run subdir (matches run-evals.sh:291 naming). If not
  # found, dump the report tree for debugging — silent "not found" would leave
  # debugging blind (Warning #8 guard against layout drift in run-evals.sh).
  local run_subdir
  run_subdir=$(find "$report_abs/runs" -maxdepth 2 -mindepth 1 -type d -name '01-trivial-task-*' 2>/dev/null | head -1)
  if [[ -z "$run_subdir" || ! -d "$run_subdir" ]]; then
    echo "FAIL: Tier 4: per-case run subdir not found under $report_abs/runs/" >&2
    ls -la "$report_abs/runs/" 2>&1 >&2 || true
    find "$report_abs" -maxdepth 3 -type d 2>&1 >&2 || true
    fail "Tier 4: per-case run subdir not found under $report_abs/runs/ (see stderr for tree dump)"
    return
  fi

  # --- Assertion 1 (WR-01): state.json .status is a concrete value ---
  if [[ ! -f "$run_subdir/state.json" ]]; then
    fail "Tier 4 / WR-01 regression: state.json missing at $run_subdir/state.json"
    return
  fi
  if ! jq -e '.status | IN("completed", "partial", "failed")' "$run_subdir/state.json" >/dev/null 2>&1; then
    fail "Tier 4 / WR-01 regression: .status is '$(jq -r .status "$run_subdir/state.json")' — expected one of completed|partial|failed"
    return
  fi
  # Additionally guard against .status stuck at the 'pending' init sentinel
  # (means run-end writeback never fired).
  local state_status
  state_status=$(jq -r '.status' "$run_subdir/state.json")
  if [[ "$state_status" == "pending" || "$state_status" == "unknown" ]]; then
    fail "Tier 4 / WR-01 regression: .status stuck at '$state_status' — run-end writeback didn't fire"
    return
  fi

  # --- Assertion 2 (WR-02): outputs/compose.txt exists and is non-empty ---
  if [[ ! -s "$run_subdir/outputs/compose.txt" ]]; then
    fail "Tier 4 / WR-02 regression: outputs/compose.txt missing or empty at $run_subdir/outputs/compose.txt"
    return
  fi

  # --- Assertion 5: scorer consumed real state without null-fallback masking ---
  # Intent: prove the scorer actually read real runner state (no missing fields
  # silently null'd). A non-null robustness value — PASS, PARTIAL, or FAIL — all
  # demonstrate the scorer reached state.status. FAIL is a legitimate outcome
  # under Tier 4's stubs (the stubbed codex can't emit a real verdict, so VERIFY
  # exits non-zero → .status = "failed" → robustness = FAIL). What we're guarding
  # against is null-from-missing-field, which would indicate contract drift.
  if [[ ! -f "$report_abs/raw-scores.json" ]]; then
    fail "Tier 4: raw-scores.json missing — scorer did not run against real state"
    return
  fi
  if ! jq -e '.[0].scores.robustness != null' \
         "$report_abs/raw-scores.json" >/dev/null 2>&1; then
    fail "Tier 4 / contract regression: scorer produced null robustness — missing contract field (see evals/RUNNER-CONTRACT.md §1)"
    return
  fi

  # --- Assertion 4 (D-08 grep-pin): contract fields split into two subsets ---
  # SCORER-READ fields (7): appear in BOTH the runner-write surface
  # (lib/co-evolution.sh + dev-review/codex/dev-review.sh — init_state_json
  # lives in the sourced library) AND evals/score-run.sh.
  # RUNNER-ONLY fields (6): appear in runner-write surface only; score-run.sh
  # does not consume them directly (verify_verdict is read from verdict.json,
  # not state.json; completed_at is a runner bookkeeping field).
  # This is the poor-man's lint per CONTEXT.md D-08 — v1.2 posture, defers to
  # AST lint in v1.3. Field subsets sourced from evals/RUNNER-CONTRACT.md §1.
  local field_drift=""
  local runner_write_surface="$REPO_ROOT/lib/co-evolution.sh $REPO_ROOT/dev-review/codex/dev-review.sh"
  # 7 scorer-read fields — both sides (runner-write surface + score-run.sh).
  # Grep pattern widened to cover .field (jq path refs) OR "field": (JSON-key
  # literals in jq -n payloads) OR field: (jq shorthand keys) — the init
  # helper in lib/co-evolution.sh uses all three shapes.
  for field in run_id status started_at updated_at marker_counts changed_files history; do
    if ! grep -qE "(\\.${field}\\b|\"${field}\":|[^A-Za-z_]${field}:)" $runner_write_surface 2>/dev/null; then
      field_drift="$field_drift runner-write-missing:${field}"
    fi
    if ! grep -qE "\\.${field}\\b" "$REPO_ROOT/evals/score-run.sh" 2>/dev/null; then
      field_drift="$field_drift score-run.sh-missing:${field}"
    fi
  done
  # 6 runner-only fields — runner-write surface only. mode is excluded per
  # contract §1 ("Runner-owned metadata — NOT written by the shared
  # init_state_json library"); task/composer/executor/reviewer/completed_at/
  # verify_verdict are all present in the init_state_json jq payload.
  for field in task composer executor reviewer completed_at verify_verdict; do
    if ! grep -qE "(\\.${field}\\b|\"${field}\":|[^A-Za-z_]${field}:)" $runner_write_surface 2>/dev/null; then
      field_drift="$field_drift dev-review.sh-missing-runner-only:${field}"
    fi
  done
  if [[ -n "$field_drift" ]]; then
    fail "Tier 4 / D-08 contract drift:$field_drift"
    return
  fi

  pass "Tier 4 / real-runner-smoke (status=$state_status, compose.txt non-empty, no drift)"
}
run_tier4_real_runner

# Cleanup Tier 2 + Tier 4 report dirs so the test leaves no on-disk artifacts
# in the real reports tree.
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
