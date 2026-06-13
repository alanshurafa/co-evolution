#!/usr/bin/env bash
# tests/status-reader-simulation.sh
# Hermetic gate for v1.5 Phase 3: dev-review/codex/dev-review-status.sh.
#
# Fabricates synthetic run dirs (state.json + stderr heartbeat logs, contract-
# shaped per evals/tests/fake-runner.sh) under a throwaway CO_EVOLVE_RUNS_DIR
# and asserts the status reader's liveness assessment, exit codes, --json keys,
# and --list output. No runner, no agents, no network.
#
# Exit-code contract under test (dev-review-status.sh):
#   0 terminal-completed · 2 terminal-partial · 5 still-running ·
#   4 presumed-dead · 3 not found / no state.json
#
# House final-line convention: "N/N scenarios passed".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS="$REPO_ROOT/dev-review/codex/dev-review-status.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required for this gate" >&2; exit 1; }

TEST_DIR="$(mktemp -d -t status-reader-sim-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
RUNS="$TEST_DIR/runs"
mkdir -p "$RUNS"
export CO_EVOLVE_RUNS_DIR="$RUNS"

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; }

# Run the reader; capture stdout + the exit code it returns.
run_status() {
  STATUS_OUT=""
  STATUS_RC=0
  STATUS_OUT=$(bash "$STATUS" "$@" 2>&1) || STATUS_RC=$?
}

# Fabricate a run dir. Args: <id> <status-json-literal> <current_phase-name-or-empty>
# Writes a contract-shaped state.json with runner_pid + (optional) current_phase.
# Extra knobs via env: FAB_PID, FAB_VERDICT.
fabricate() {
  local id="$1" status="$2" phase="$3"
  local dir="$RUNS/$id"
  mkdir -p "$dir/outputs"
  local pid="${FAB_PID:-$$}"
  local cur="null"
  if [[ -n "$phase" ]]; then
    cur=$(jq -n --arg n "$phase" '{name: $n, started_at: "2026-06-12T00:00:00Z"}')
  fi
  jq -n \
    --arg id "$id" \
    --arg status "$status" \
    --argjson pid "$pid" \
    --argjson cur "$cur" \
    --arg verdict "${FAB_VERDICT:-}" \
    '{
      run_id: $id,
      task: "synthetic status-reader probe task that is fairly long to test truncation behavior in the reader output line",
      composer: "opus", executor: "codex", reviewer: "opus",
      phases: [
        {name: "compose", started_at: "2026-06-12T00:00:00Z", completed_at: "2026-06-12T00:00:01Z", status: "ok", exit_code: 0}
      ],
      marker_counts: {contested: 1, clarify: 2},
      verify_verdict: (if $verdict == "" then null else $verdict end),
      runner_pid: $pid,
      current_phase: (if $status == "null" then $cur else $cur end),
      started_at: "2026-06-12T00:00:00Z",
      completed_at: null,
      status: (if $status == "null" then null else $status end),
      updated_at: "2026-06-12T00:00:00Z"
    }' > "$dir/state.json"
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Scenario 1: still-running — alive pid ($$) + fresh execute stderr -> exit 5
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
d1=$(FAB_PID="$$" fabricate "dev-review-0001-running" null "execute")
# Fresh heartbeat: execute-stderr.log just touched (mtime = now).
printf 'executor working...\nstill going...\n' > "$d1/execute-stderr.log"
run_status "dev-review-0001-running"
if [[ "$STATUS_RC" -eq 5 ]] && grep -q 'RUNNING' <<<"$STATUS_OUT"; then
  pass "S1: still-running (alive pid + fresh heartbeat) -> exit 5"
else
  fail "S1: rc=$STATUS_RC out=<<$STATUS_OUT>>"
fi

# ---------------------------------------------------------------------------
# Scenario 2: presumed-dead — bogus pid + stale stderr + non-terminal -> exit 4
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
d2=$(FAB_PID=999999 fabricate "dev-review-0002-dead" null "execute")
printf 'executor started\n' > "$d2/execute-stderr.log"
# Make the heartbeat stale (>120s old).
touch -t 202001010000 "$d2/execute-stderr.log" 2>/dev/null || true
run_status "dev-review-0002-dead"
if [[ "$STATUS_RC" -eq 4 ]] && grep -q 'DEAD' <<<"$STATUS_OUT"; then
  pass "S2: presumed-dead (pid gone + stale heartbeat) -> exit 4"
else
  fail "S2: rc=$STATUS_RC out=<<$STATUS_OUT>>"
fi

# ---------------------------------------------------------------------------
# Scenario 3: completed -> exit 0
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
d3=$(FAB_VERDICT="APPROVED" fabricate "dev-review-0003-done" completed "")
jq -n '{verdict:"APPROVED",confidence:90,summary:"ok",issues:[]}' > "$d3/verdict.json"
run_status "dev-review-0003-done"
if [[ "$STATUS_RC" -eq 0 ]] && grep -q 'DONE' <<<"$STATUS_OUT"; then
  pass "S3: completed -> exit 0"
else
  fail "S3: rc=$STATUS_RC out=<<$STATUS_OUT>>"
fi

# ---------------------------------------------------------------------------
# Scenario 4: partial -> exit 2
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
d4=$(fabricate "dev-review-0004-partial" partial "")
run_status "dev-review-0004-partial"
if [[ "$STATUS_RC" -eq 2 ]] && grep -q 'PARTIAL' <<<"$STATUS_OUT"; then
  pass "S4: partial -> exit 2"
else
  fail "S4: rc=$STATUS_RC out=<<$STATUS_OUT>>"
fi

# ---------------------------------------------------------------------------
# Scenario 5: missing run -> exit 3
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
run_status "dev-review-9999-nope"
if [[ "$STATUS_RC" -eq 3 ]]; then
  pass "S5: missing run -> exit 3"
else
  fail "S5: rc=$STATUS_RC out=<<$STATUS_OUT>>"
fi

# ---------------------------------------------------------------------------
# Scenario 6: --json parses with jq and has the expected keys
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
json_rc=0
json_out=$(bash "$STATUS" --json "dev-review-0001-running" 2>/dev/null) || json_rc=$?
j_ok=true
if ! jq -e . <<<"$json_out" >/dev/null 2>&1; then j_ok=false; fi
for key in run_id status runner_pid runner_alive current_phase heartbeat marker_counts assess exit_code phases; do
  jq -e "has(\"$key\")" <<<"$json_out" >/dev/null 2>&1 || { j_ok=false; echo "  missing key: $key" >&2; }
done
# current_phase.name and heartbeat.age_secs must be populated for the running run.
if [[ "$j_ok" == true ]]; then
  jq -e '.current_phase.name == "execute"' <<<"$json_out" >/dev/null 2>&1 || j_ok=false
  jq -e '.heartbeat.age_secs != null' <<<"$json_out" >/dev/null 2>&1 || j_ok=false
  jq -e '.exit_code == 5' <<<"$json_out" >/dev/null 2>&1 || j_ok=false
fi
# --json still returns the assessment exit code.
[[ "$json_rc" -eq 5 ]] || j_ok=false
if [[ "$j_ok" == true ]]; then
  pass "S6: --json is valid JSON with expected keys + populated current_phase/heartbeat"
else
  fail "S6: json_rc=$json_rc out=<<$json_out>>"
fi

# ---------------------------------------------------------------------------
# Scenario 7: --list shows the active (non-terminal) run + recent terminal ones
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
list_out=$(bash "$STATUS" --list 2>&1) || true
if grep -q 'ACTIVE' <<<"$list_out" \
   && grep -q 'dev-review-0001-running' <<<"$list_out" \
   && grep -q 'dev-review-0003-done' <<<"$list_out"; then
  pass "S7: --list shows the active run and recent terminal runs"
else
  fail "S7: out=<<$list_out>>"
fi

# ---------------------------------------------------------------------------
# Scenario 8: no positional arg -> latest run by mtime (the dead one we touched
# oldest is NOT latest; ensure default resolution returns *some* run cleanly).
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
# Touch a brand-new completed run so it is unambiguously newest.
d8=$(fabricate "dev-review-0008-latest" completed "")
touch "$d8/state.json"
run_status   # no arg
if [[ "$STATUS_RC" -eq 0 ]] && grep -q 'dev-review-0008-latest' <<<"$STATUS_OUT"; then
  pass "S8: no-arg resolves the newest run by mtime"
else
  fail "S8: rc=$STATUS_RC out=<<$STATUS_OUT>>"
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
