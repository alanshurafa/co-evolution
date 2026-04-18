#!/usr/bin/env bash
# tests/revise-loop-simulation.sh
# Self-contained simulation of the REVISE auto-loop (RTUX-03). Runs without
# network, codex/claude CLIs, or a real git repo. Mocks run_execute_phase
# (always returns 0) and run_verify_phase (scripted verdict sequence per
# scenario) and exercises the real _run_revise_loop function extracted from
# dev-review/codex/dev-review.sh.
#
# Scenarios:
#   S1: REVISE → APPROVED with budget 1 — loop runs 2 passes; phases[] is
#       ["execute","verify","execute-2","verify-2"]; final verdict APPROVED.
#   S2: REVISE with budget 0 (v1.0 parity) — loop runs exactly 1 pass;
#       phases[] is ["execute","verify"]; bare names, no numbered suffix.
#   S3: REVISE cap at max — budget 3, all verifies return REVISE; loop runs
#       4 passes; phases[] ends with ["execute-4","verify-4"].
#   S4: Prompt byte-identity — build_execution_prompt "PLAN" produces the
#       same output as build_execution_prompt "PLAN" "" (third arg omitted
#       vs empty string). Protects v1.0 backwards-compat invariant.
#
# Deviation note (Task 4, plan Rule 1): The plan's jq asserts used '.phase',
# but write_state_phase writes the field as '.name'. Test uses '.name' to
# match the real state.json schema.

set -euo pipefail

TEST_DIR=$(mktemp -d -t revise-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/co-evolution.sh"

# ---- shared harness state ----
STATE_JSON="$TEST_DIR/state.json"
RUN_DIR="$TEST_DIR/run"
mkdir -p "$RUN_DIR"

VERIFY=true
PLAN_EXIT=0
PLAN_PATH="$RUN_DIR/plan.md"
echo "stub plan" > "$PLAN_PATH"

# Mock state
EXECUTE_CALLS=0
VERIFY_CALLS=0
VERDICT_SEQUENCE=()
verdict_seq_idx=0

# ---- mock phase runners ----
# Match the real signatures and global effects that _run_revise_loop depends on.
run_execute_phase() {
  EXECUTE_CALLS=$((EXECUTE_CALLS + 1))
  # Real run_execute_phase writes an output file; mirror that so any future
  # sanity check in the loop does not fail on a missing artifact.
  echo "stub execute output pass ${EXECUTE_CALLS}" > "$RUN_DIR/execute-output.md"
  return 0
}

run_verify_phase() {
  VERIFY_CALLS=$((VERIFY_CALLS + 1))
  VERDICT="${VERDICT_SEQUENCE[$verdict_seq_idx]:-APPROVED}"
  verdict_seq_idx=$((verdict_seq_idx + 1))
  # Real run_verify_phase writes the normalized verdict JSON which the retry
  # loop reads to populate REVISE_FEEDBACK_JSON. Produce a realistic shape so
  # the capture path is exercised rather than falling back to '{}'.
  cat > "$RUN_DIR/.verdict-normalized.json" <<JSON
{"verdict":"$VERDICT","confidence":80,"summary":"sim pass $VERIFY_CALLS","issues":[{"severity":"HIGH","description":"sim issue"}]}
JSON
  if [[ "$VERDICT" == "REVISE" ]]; then
    return 2
  fi
  return 0
}

# write_state_field is sourced from lib/co-evolution.sh (real impl).
# _run_revise_loop is sourced from dev-review.sh (real impl — see below).

# ---- extract the real _run_revise_loop function from dev-review.sh ----
# sed range anchors on the opening signature and the matching closing brace at
# column 0. If the function layout changes, update both ends together.
# shellcheck disable=SC1090
source <(sed -n '/^_run_revise_loop() {/,/^}$/p' "$REPO_ROOT/dev-review/codex/dev-review.sh")

if ! declare -F _run_revise_loop >/dev/null; then
  echo "FAIL: _run_revise_loop not sourced — simulation cannot continue"
  exit 1
fi

# ---- scenario runner ----
reset_harness() {
  local label="$1"
  EXECUTE_CALLS=0
  VERIFY_CALLS=0
  verdict_seq_idx=0
  # Fresh state.json per scenario so phases[] assertions are scoped.
  init_state_json "$STATE_JSON" "sim-$label" "sim task" "codex" "codex" "opus"
  unset REVISE_FEEDBACK_JSON VERDICT CONFIDENCE SUMMARY
}

# ------------------------------------------------------------------
# Scenario 1: REVISE → APPROVED with budget 1
# ------------------------------------------------------------------
REVISE_LOOP_MAX=1
VERDICT_SEQUENCE=(REVISE APPROVED)
reset_harness s1
_run_revise_loop

[[ "$EXECUTE_CALLS" -eq 2 ]] || { echo "S1 FAIL: executes=$EXECUTE_CALLS (expected 2)"; exit 1; }
[[ "$VERIFY_CALLS"  -eq 2 ]] || { echo "S1 FAIL: verifies=$VERIFY_CALLS (expected 2)"; exit 1; }
jq -e '.phases | map(.name) == ["execute","verify","execute-2","verify-2"]' "$STATE_JSON" >/dev/null \
  || { echo "S1 FAIL: unexpected phases[]"; jq '.phases | map(.name)' "$STATE_JSON"; exit 1; }
[[ "$(jq -r '.verify_verdict' "$STATE_JSON")" = "APPROVED" ]] \
  || { echo "S1 FAIL: final verdict $(jq -r '.verify_verdict' "$STATE_JSON") (expected APPROVED)"; exit 1; }
echo "S1 OK"

# ------------------------------------------------------------------
# Scenario 2: REVISE with budget 0 — v1.0 parity, single pass, bare names
# ------------------------------------------------------------------
REVISE_LOOP_MAX=0
VERDICT_SEQUENCE=(REVISE)
reset_harness s2
_run_revise_loop

[[ "$EXECUTE_CALLS" -eq 1 ]] || { echo "S2 FAIL: executes=$EXECUTE_CALLS (expected 1)"; exit 1; }
[[ "$VERIFY_CALLS"  -eq 1 ]] || { echo "S2 FAIL: verifies=$VERIFY_CALLS (expected 1)"; exit 1; }
jq -e '.phases | map(.name) == ["execute","verify"]' "$STATE_JSON" >/dev/null \
  || { echo "S2 FAIL: phases[] not bare names"; jq '.phases | map(.name)' "$STATE_JSON"; exit 1; }
echo "S2 OK"

# ------------------------------------------------------------------
# Scenario 3: REVISE cap at max — budget 3, four passes, execute-4/verify-4
# ------------------------------------------------------------------
REVISE_LOOP_MAX=3
VERDICT_SEQUENCE=(REVISE REVISE REVISE REVISE)
reset_harness s3
_run_revise_loop

[[ "$EXECUTE_CALLS" -eq 4 ]] || { echo "S3 FAIL: executes=$EXECUTE_CALLS (expected 4)"; exit 1; }
[[ "$VERIFY_CALLS"  -eq 4 ]] || { echo "S3 FAIL: verifies=$VERIFY_CALLS (expected 4)"; exit 1; }
jq -e '.phases | map(.name) | .[-2:] == ["execute-4","verify-4"]' "$STATE_JSON" >/dev/null \
  || { echo "S3 FAIL: cap not reached"; jq '.phases | map(.name)' "$STATE_JSON"; exit 1; }
jq -e '.phases | length == 8' "$STATE_JSON" >/dev/null \
  || { echo "S3 FAIL: expected 8 phase entries, got $(jq '.phases | length' "$STATE_JSON")"; exit 1; }
echo "S3 OK"

# ------------------------------------------------------------------
# Scenario 4: Prompt byte-identity invariant
# ------------------------------------------------------------------
export TASK="smoke" RUN_DIR
# shellcheck disable=SC1090
source <(sed -n '/^build_reviewer_feedback_summary()/,/^}$/p; /^build_issues_list_markdown()/,/^}$/p; /^build_execution_prompt()/,/^}$/p' "$REPO_ROOT/dev-review/codex/dev-review.sh")

out_a=$(build_execution_prompt codex "PLAN")
out_b=$(build_execution_prompt codex "PLAN" "")
[[ "$out_a" = "$out_b" ]] || { echo "S4 FAIL: optional arg changed default output"; exit 1; }
if echo "$out_a" | grep -q 'Fix These Issues'; then
  echo "S4 FAIL: first-pass leaked conditional block"
  exit 1
fi

# Same invariant for the opus template — backwards compat for both executors.
out_c=$(build_execution_prompt opus "PLAN")
out_d=$(build_execution_prompt opus "PLAN" "")
[[ "$out_c" = "$out_d" ]] || { echo "S4 FAIL: opus optional arg changed default output"; exit 1; }
echo "S4 OK"

echo "ALL PASS"
