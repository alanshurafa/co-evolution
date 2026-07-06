#!/usr/bin/env bash
# tests/observability-lifecycle-simulation.sh
# Hermetic gate for v1.5 Phase 3: runner observability weave-in
# (dev-review/codex/dev-review.sh). Runs the REAL runner end-to-end with
# PATH-stubbed claude/codex (no agents, no network) and asserts the additive
# state.json fields the status reader depends on:
#
#   - .current_phase == null at a clean terminal (EOF clears the in-flight phase)
#   - .runner_pid present (number)
#   - .pre_execute_sha / .post_execute_sha present and 40-hex
#   - --parent-run abc-123 lands in .orchestration.parent_run_id
#   - a mid-run state.json capture shows .current_phase.name == "execute"
#
# Cheap shape: --skip-plan --plan <fixture> --bounces 0 --verify --verifier codex
# (codex executor + codex verifier via --output-schema, so a single codex stub
# drives both phases without needing a working claude-verdict path).
#
# House final-line convention: "N/N scenarios passed".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/dev-review/codex/dev-review.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required for this gate" >&2; exit 1; }

TEST_DIR="$(mktemp -d -t obs-lifecycle-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; }

# --- hermetic git env (mirrors tests/run-all.sh) ----------------------------
export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
cat > "$TEST_DIR/gitconfig" <<'GITCFG'
[user]
	name = obs-sim
	email = obs-sim@invalid.local
[init]
	defaultBranch = master
[core]
	autocrlf = false
[commit]
	gpgsign = false
GITCFG

# --- stubs ------------------------------------------------------------------
# codex stub handles BOTH phases the default-seat skip-plan run exercises:
#   - EXECUTE: prompt heading "Execution Instructions (Codex)" + a -C workdir →
#     append a line to the tracked file so the run produces a diff. Honors
#     OBS_EXECUTE_SLEEP (seconds) so the mid-run scenario has a polling window.
#   - VERIFY: argv carries --output-schema + -o FILE → write a valid verdict.
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in --version|-v|version) echo "codex 0.117.0 (obs-stub)"; exit 0 ;; esac
done
output_file=""; workdir=""; has_schema=false; prev=""
for arg in "$@"; do
  case "$prev" in
    -o) output_file="$arg" ;;
    -C) workdir="$arg" ;;
  esac
  [[ "$arg" == "--output-schema" ]] && has_schema=true
  prev="$arg"
done
stdin_capture=""
while IFS= read -r _line; do stdin_capture+="$_line"$'\n'; done

if [[ "$has_schema" == true ]]; then
  # VERIFY phase — emit a schema-shaped verdict to the -o file.
  printf '%s\n' '{"verdict":"APPROVED","confidence":90,"summary":"obs-stub approves the change.","issues":[],"scope_creep_detected":false,"iteration_notes":""}' > "$output_file"
  exit 0
fi

if [[ "$stdin_capture" == *"Execution Instructions (Codex)"* && -n "$workdir" && -f "$workdir/touched.txt" ]]; then
  # EXECUTE phase — optional dwell so a poller can observe current_phase=execute.
  if [[ -n "${OBS_EXECUTE_SLEEP:-}" ]]; then
    sleep "$OBS_EXECUTE_SLEEP"
  fi
  printf 'obs-stub-change\n' >> "$workdir/touched.txt"
fi
# Non-schema codex calls emit to -o (or stdout) so the runner sees non-empty output.
plan='obs stub output line one\nobs stub output line two\nobs stub output line three'
if [[ -n "$output_file" ]]; then
  printf '%b\n' "$plan" > "$output_file"
else
  printf '%b\n' "$plan"
fi
exit 0
STUB
chmod +x "$TEST_DIR/bin/codex"
# claude stub (unused by default seats, present for safety): emit a plan.
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in --version|-v|version) echo "claude 1.0.0 (obs-stub)"; exit 0 ;; esac
done
while IFS= read -r _line; do :; done
printf 'obs claude stub output\n'
STUB
chmod +x "$TEST_DIR/bin/claude"

# --- fixtures ---------------------------------------------------------------
make_scratch_repo() {
  local repo="$TEST_DIR/repo-$1"
  rm -rf "$repo"; mkdir -p "$repo"
  git -C "$repo" init -q
  printf 'baseline\n' > "$repo/touched.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm baseline
  printf '%s' "$repo"
}

PLAN_FIXTURE="$TEST_DIR/plan-fixture.md"
cat > "$PLAN_FIXTURE" <<'PLAN'
# Observability Lifecycle Fixture

## Approach

A pre-baked plan so the --skip-plan run bypasses compose and bounce and drives
only the execute and verify phases. It satisfies the plan heading regex, the
minimum word count, and the structural-line check. The executor stub appends one
harmless line to a tracked file so the run produces a diff for verify to score.

## Files to Change

- `touched.txt` — the executor stub appends a line.

## Risks

- None identified.
PLAN

# Explicit per-scenario run dirs (policy a) — avoids the `ls -dt runs/dev-review-*`
# newest-mtime race that cross-reads another concurrent suite's run dir. Each
# scenario passes --run-dir under this sim's own $TEST_DIR, so cleanup rides the
# existing TEST_DIR EXIT trap instead of a per-scenario rm -rf.

# ===========================================================================
# Scenario 1: full lifecycle — current_phase=null at EOF, runner_pid present,
# pre/post SHA 40-hex.
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo s1)
run1="$TEST_DIR/run-s1"
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  bash "$RUNNER" --skip-plan --plan "$PLAN_FIXTURE" --bounces 0 --verify --verifier codex \
    --run-dir "$run1" --workdir "$repo" --timeout 60 -- "obs lifecycle probe"
) > "$TEST_DIR/s1.out" 2>&1 || true
s1_state="$run1/state.json"
s1_ok=true
if [[ ! -f "$s1_state" ]]; then
  s1_ok=false
else
  jq -e '.current_phase == null' "$s1_state" >/dev/null 2>&1 || { s1_ok=false; echo "  current_phase not null" >&2; }
  jq -e '(.runner_pid | type) == "number"' "$s1_state" >/dev/null 2>&1 || { s1_ok=false; echo "  runner_pid missing/non-number" >&2; }
  jq -e '(.pre_execute_sha | test("^[0-9a-f]{40}$"))' "$s1_state" >/dev/null 2>&1 || { s1_ok=false; echo "  pre_execute_sha not 40-hex" >&2; }
  jq -e '(.post_execute_sha | test("^[0-9a-f]{40}$"))' "$s1_state" >/dev/null 2>&1 || { s1_ok=false; echo "  post_execute_sha not 40-hex" >&2; }
  jq -e '.verify_verdict == "APPROVED"' "$s1_state" >/dev/null 2>&1 || { s1_ok=false; echo "  verdict not APPROVED" >&2; }
fi
if [[ "$s1_ok" == true ]]; then
  pass "S1: lifecycle — current_phase=null, runner_pid number, pre/post SHA 40-hex, verdict APPROVED"
else
  fail "S1: state below"
  [[ -f "$s1_state" ]] && cat "$s1_state" >&2
  cat "$TEST_DIR/s1.out" >&2
fi

# ===========================================================================
# Scenario 2: --parent-run lands in .orchestration.parent_run_id.
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo s2)
run2="$TEST_DIR/run-s2"
(
  export PATH="$TEST_DIR/bin:$PATH"
  bash "$RUNNER" --skip-plan --plan "$PLAN_FIXTURE" --bounces 0 --verify --verifier codex \
    --parent-run "abc-123" --run-dir "$run2" --workdir "$repo" --timeout 60 -- "obs parent-run probe"
) > "$TEST_DIR/s2.out" 2>&1 || true
if [[ -f "$run2/state.json" ]] \
   && jq -e '.orchestration.parent_run_id == "abc-123"' "$run2/state.json" >/dev/null 2>&1; then
  pass "S2: --parent-run abc-123 recorded in .orchestration.parent_run_id"
else
  fail "S2: parent_run_id missing (run=$run2)"
  [[ -f "$run2/state.json" ]] && cat "$run2/state.json" >&2
fi

# ===========================================================================
# Scenario 3: --parent-run rejects a garbage token (path traversal / shell meta).
# ===========================================================================
TOTAL=$((TOTAL + 1))
rc3=0
( export PATH="$TEST_DIR/bin:$PATH"
  bash "$RUNNER" --skip-plan --plan "$PLAN_FIXTURE" --parent-run '../evil;rm' \
    --workdir "$TEST_DIR" --timeout 60 -- "x" ) > "$TEST_DIR/s3.out" 2>&1 || rc3=$?
if [[ "$rc3" -ne 0 ]] && grep -qi 'parent-run' "$TEST_DIR/s3.out"; then
  pass "S3: --parent-run rejects an unsafe token (die)"
else
  fail "S3: rc=$rc3 out=$(cat "$TEST_DIR/s3.out")"
fi

# ===========================================================================
# Scenario 4: mid-run capture — while execute dwells, state.json shows
# current_phase.name == "execute" and runner_pid is alive.
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo s4)
run4="$TEST_DIR/run-s4"
(
  export PATH="$TEST_DIR/bin:$PATH"
  export OBS_EXECUTE_SLEEP=4
  bash "$RUNNER" --skip-plan --plan "$PLAN_FIXTURE" --bounces 0 --verify --verifier codex \
    --run-dir "$run4" --workdir "$repo" --timeout 60 -- "obs mid-run probe"
) > "$TEST_DIR/s4.out" 2>&1 &
runner_bg=$!

# Poll the known run dir's state.json for current_phase.name == execute (no
# newest-mtime discovery needed — the path is pinned by --run-dir above).
captured=false
captured_pid=""
for _ in $(seq 1 60); do
  if [[ -f "$run4/state.json" ]]; then
    name=$(jq -r '.current_phase.name // empty' "$run4/state.json" 2>/dev/null || true)
    if [[ "$name" == "execute" ]]; then
      captured=true
      captured_pid=$(jq -r '.runner_pid // empty' "$run4/state.json" 2>/dev/null || true)
      break
    fi
  fi
  sleep 0.2
done
wait "$runner_bg" 2>/dev/null || true

s4_ok=true
[[ "$captured" == true ]] || { s4_ok=false; echo "  never observed current_phase=execute" >&2; }
# runner_pid captured mid-run must be a positive integer.
[[ "$captured_pid" =~ ^[0-9]+$ ]] || { s4_ok=false; echo "  captured runner_pid not numeric: $captured_pid" >&2; }
# And the run must still terminate cleanly with current_phase cleared.
if [[ -f "$run4/state.json" ]]; then
  jq -e '.current_phase == null and .status == "completed"' "$run4/state.json" >/dev/null 2>&1 \
    || { s4_ok=false; echo "  post-run state not clean terminal" >&2; }
fi
if [[ "$s4_ok" == true ]]; then
  pass "S4: mid-run capture observed current_phase=execute; run then terminated clean"
else
  fail "S4: capture failed"
  [[ -f "$run4/state.json" ]] && cat "$run4/state.json" >&2
  cat "$TEST_DIR/s4.out" >&2
fi

# ===========================================================================
# Scenario 5: parity — a default skip-plan run with NO new flags still produces
# a completed state (no-new-flags regression; existing bounce-state behavior
# is covered by tests/bounce-state-simulation.sh).
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo s5)
run5="$TEST_DIR/run-s5"
(
  export PATH="$TEST_DIR/bin:$PATH"
  bash "$RUNNER" --skip-plan --plan "$PLAN_FIXTURE" --bounces 0 --verify --verifier codex \
    --run-dir "$run5" --workdir "$repo" --timeout 60 -- "obs parity probe"
) > "$TEST_DIR/s5.out" 2>&1 || true
if [[ -f "$run5/state.json" ]] \
   && jq -e '.status == "completed" and .current_phase == null' "$run5/state.json" >/dev/null 2>&1; then
  pass "S5: no-new-flags run reaches completed with current_phase cleared"
else
  fail "S5: parity run not clean (run=$run5)"
  [[ -f "$run5/state.json" ]] && cat "$run5/state.json" >&2
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
