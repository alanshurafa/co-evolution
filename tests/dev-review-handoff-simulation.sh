#!/usr/bin/env bash
# tests/dev-review-handoff-simulation.sh
# Hermetic simulation of co-evolve-bouncer.sh's --execute / --verify dev-review
# hand-off (see .notes/dev-review-merge-plan.md). Runs without network, without
# real codex/claude CLIs, and without invoking the real dev-review engine.
#
# The hand-off delegates the bounced plan to the dev-review engine via
# `exec bash "$DEV_REVIEW_SCRIPT" --skip-plan --plan <plan> [flags...]`. This
# test overrides CO_EVOLVE_DEV_REVIEW_SCRIPT with a RECORDING STUB that captures
# the exact argv it was exec'd with and exits with a scripted code. That lets us
# assert the delegation contract (argv construction, flag pass-through, plan
# path, exit-code propagation) precisely, while `claude`/`codex` are PATH-stubbed
# so the compose+bounce phase reaches the hand-off. No real Codex is ever run
# (that would cost money) — every LLM call is a canned stub.
#
# Scenarios (exit 0 iff all pass):
#   S1: --execute --verify --skip-interview --auto — engine receives
#       --skip-plan --plan <the co-evolve final plan> --verify; co-evolve exits
#       with the engine's exit code (0).
#   S2: exit-code passthrough — stub engine exits 2 (REVISE); co-evolve exits 2.
#   S3: full flag pass-through — --workdir/--verifier/--revise-loop/--exec-branch/
#       --exec-timeout are all forwarded (branch->--branch, exec-timeout->--timeout).
#   S4: --execute WITHOUT --verify does not forward --verify.
#   S5: empty-plan guard — an empty bounced plan aborts before the engine runs.
#   S6: no --execute — engine stub is never invoked (pure bounce, byte-parity).
#
# Dependencies: bash, jq (optional for co-evolve internals), git. No claude/codex.
# Cross-platform: Git Bash Windows + Linux + macOS (bash 3.2).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"

TEST_DIR=$(mktemp -d -t dr-handoff-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

PASS=0
FAIL=0
note_pass() { echo "  OK: $1"; PASS=$((PASS + 1)); }
note_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---- PATH-injected claude/codex stubs (compose + bounce) --------------------
# co-evolve's compose+bounce call claude (AGENT_A) and codex (AGENT_B) through
# lib/co-evolution.sh's invoke_claude/invoke_codex, which resolve the binary via
# PATH and write to the -o target (codex) or stdout (claude). Both stubs emit a
# substantial, structured document so validate_plan_artifact / size checks pass
# and the bounce converges to a non-empty plan. No markers => early convergence.
mkdir -p "$TEST_DIR/bin"

# Canned plan body — >60 words, >5 non-empty lines, structural (#, -) lines, and
# deliberately marker-free so the bounce loop converges on pass 1.
CANNED_DOC='# Implementation Plan

## Files to Change

- `example.txt` — add a greeting line so the executor has a concrete change

## Approach

Create a single text file with one line of content. This is a hermetic
simulation fixture; the plan only needs to be a well-formed, structured
document with enough words and lines to satisfy the plan validators used by
the compose and bounce phases of the co-evolve pipeline.

## Risks

- None identified. This is a fixture used only by the hand-off simulation.'

cat > "$TEST_DIR/bin/claude" <<STUB
#!/usr/bin/env bash
# Claude stub: ignore prompt (stdin), print canned doc to stdout.
cat > /dev/null
cat <<'DOC'
$CANNED_DOC
DOC
STUB
chmod +x "$TEST_DIR/bin/claude"

# Codex stub: writes canned doc to the file named by -o (co-evolve's invoke_codex
# always passes -o). Mirrors the real codex exec output contract.
cat > "$TEST_DIR/bin/codex" <<STUB
#!/usr/bin/env bash
cat > /dev/null 2>/dev/null || true
out=""
prev=""
for a in "\$@"; do
  if [[ "\$prev" == "-o" ]]; then out="\$a"; fi
  prev="\$a"
done
if [[ -n "\$out" ]]; then
  cat > "\$out" <<'DOC'
$CANNED_DOC
DOC
fi
exit 0
STUB
chmod +x "$TEST_DIR/bin/codex"

# ---- Recording stub for the dev-review engine -------------------------------
# Captures argv (one per line) to $ARGV_FILE and exits with $STUB_EXIT (env,
# default 0). This is the seam under test: co-evolve exec's this instead of the
# real engine, so whatever argv co-evolve built lands here verbatim.
ENGINE_STUB="$TEST_DIR/dev-review-stub.sh"
cat > "$ENGINE_STUB" <<'STUB'
#!/usr/bin/env bash
: > "$ARGV_FILE"
for a in "$@"; do printf '%s\n' "$a" >> "$ARGV_FILE"; done
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$ENGINE_STUB"

# Shared run: invoke co-evolve with the recording engine + stubbed CLIs.
# Redirect co-evolve run artifacts into TEST_DIR so nothing pollutes the repo.
run_bouncer() {
  local rc=0
  CO_EVOLVE_DEV_REVIEW_SCRIPT="$ENGINE_STUB" \
  CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs" \
  ARGV_FILE="$ARGV_FILE" \
  STUB_EXIT="${STUB_EXIT:-0}" \
  PATH="$TEST_DIR/bin:$PATH" \
    bash "$BOUNCER" "$@" >"$TEST_DIR/out.log" 2>&1 || rc=$?
  return $rc
}

# argv_has <flag> [value] — true if $ARGV_FILE contains <flag>, and (when value
# given) the line immediately after it equals <value>.
argv_has() {
  local flag="$1" val="${2:-}"
  if [[ -z "$val" ]]; then
    grep -qxF -- "$flag" "$ARGV_FILE"
    return $?
  fi
  awk -v f="$flag" -v v="$val" '
    prev == f && $0 == v { found = 1 }
    { prev = $0 }
    END { exit(found ? 0 : 1) }
  ' "$ARGV_FILE"
}

# ------------------------------------------------------------------ S1
ARGV_FILE="$TEST_DIR/argv-s1.txt"
echo "S1: --execute --verify forwards --skip-plan --plan <plan> --verify"
STUB_EXIT=0
s1_rc=0
run_bouncer --skip-interview --auto --execute --verify "build a greeting file" || s1_rc=$?
if [[ ! -f "$ARGV_FILE" ]]; then
  note_fail "engine stub was never invoked"; cat "$TEST_DIR/out.log"
else
  argv_has "--skip-plan"          && note_pass "forwarded --skip-plan"          || note_fail "missing --skip-plan"
  argv_has "--verify"             && note_pass "forwarded --verify"             || note_fail "missing --verify"
  # --plan <path> must point at an existing, non-empty co-evolve final plan.
  plan_path=$(awk 'prev=="--plan"{print; exit} {prev=$0}' "$ARGV_FILE")
  if [[ -n "$plan_path" && -s "$plan_path" ]]; then
    note_pass "forwarded --plan <non-empty file>: $(basename "$plan_path")"
  else
    note_fail "--plan missing or points at empty file: '$plan_path'"
  fi
  [[ "$s1_rc" -eq 0 ]] && note_pass "co-evolve exit code == engine exit (0)" || note_fail "expected exit 0, got $s1_rc"
fi

# ------------------------------------------------------------------ S2
ARGV_FILE="$TEST_DIR/argv-s2.txt"
echo "S2: engine exit 2 (REVISE) propagates through co-evolve"
STUB_EXIT=2
s2_rc=0
run_bouncer --skip-interview --auto --execute --verify "revise scenario" || s2_rc=$?
[[ "$s2_rc" -eq 2 ]] && note_pass "co-evolve propagated exit 2" || note_fail "expected exit 2, got $s2_rc"

# ------------------------------------------------------------------ S3
ARGV_FILE="$TEST_DIR/argv-s3.txt"
echo "S3: full flag pass-through (workdir/verifier/revise-loop/branch/timeout)"
STUB_EXIT=0
# Real dir for --workdir so co-evolve's normalize_path_for_bash accepts it.
mkdir -p "$TEST_DIR/wd"
s3_rc=0
run_bouncer --skip-interview --auto --execute --verify \
  --workdir "$TEST_DIR/wd" --verifier codex --revise-loop 2 \
  --exec-branch auto --exec-timeout 900 "flag passthrough" || s3_rc=$?
argv_has "--workdir" "$TEST_DIR/wd" && note_pass "forwarded --workdir <dir>"       || note_fail "missing/incorrect --workdir"
argv_has "--verifier" "codex"       && note_pass "forwarded --verifier codex"       || note_fail "missing --verifier codex"
argv_has "--revise-loop" "2"        && note_pass "forwarded --revise-loop 2"        || note_fail "missing --revise-loop 2"
argv_has "--branch" "auto"          && note_pass "--exec-branch -> engine --branch"  || note_fail "missing --branch auto"
argv_has "--timeout" "900"          && note_pass "--exec-timeout -> engine --timeout"|| note_fail "missing --timeout 900"

# ------------------------------------------------------------------ S4
ARGV_FILE="$TEST_DIR/argv-s4.txt"
echo "S4: --execute WITHOUT --verify does not forward --verify"
STUB_EXIT=0
s4_rc=0
run_bouncer --skip-interview --auto --execute "no verify" || s4_rc=$?
if argv_has "--verify"; then
  note_fail "--verify leaked into engine argv without --verify flag"
else
  note_pass "--verify correctly absent"
fi
argv_has "--skip-plan" && note_pass "still forwarded --skip-plan" || note_fail "missing --skip-plan in execute-only run"

# ------------------------------------------------------------------ S5
ARGV_FILE="$TEST_DIR/argv-s5.txt"
echo "S5: empty bounced plan aborts before engine runs"
# Force an empty plan by making both CLI stubs emit nothing for this run.
mkdir -p "$TEST_DIR/bin-empty"
cat > "$TEST_DIR/bin-empty/claude" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
# emit nothing
STUB
cat > "$TEST_DIR/bin-empty/codex" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null 2>/dev/null || true
prev=""; for a in "$@"; do [[ "$prev" == "-o" ]] && : > "$a"; prev="$a"; done
exit 0
STUB
chmod +x "$TEST_DIR/bin-empty/claude" "$TEST_DIR/bin-empty/codex"
s5_rc=0
CO_EVOLVE_DEV_REVIEW_SCRIPT="$ENGINE_STUB" \
CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs-s5" \
ARGV_FILE="$ARGV_FILE" \
PATH="$TEST_DIR/bin-empty:$PATH" \
  bash "$BOUNCER" --skip-interview --auto --execute "empty plan" >"$TEST_DIR/out-s5.log" 2>&1 || s5_rc=$?
# co-evolve should fail (empty compose output => exit 1 from run_compose_phase,
# OR our empty-plan guard). Either way the engine stub must NOT have run.
if [[ -f "$ARGV_FILE" ]]; then
  note_fail "engine ran despite empty plan (argv file present)"
else
  note_pass "engine did not run on empty plan"
fi
[[ "$s5_rc" -ne 0 ]] && note_pass "co-evolve exited non-zero on empty plan ($s5_rc)" || note_fail "expected non-zero exit on empty plan"

# ------------------------------------------------------------------ S6
ARGV_FILE="$TEST_DIR/argv-s6.txt"
echo "S6: no --execute => engine never invoked (pure bounce)"
STUB_EXIT=0
s6_rc=0
run_bouncer --skip-interview --auto "pure bounce, no execute" || s6_rc=$?
if [[ -f "$ARGV_FILE" ]]; then
  note_fail "engine ran without --execute"
else
  note_pass "engine correctly not invoked without --execute"
fi
[[ "$s6_rc" -eq 0 ]] && note_pass "pure bounce exited 0" || note_fail "pure bounce expected exit 0, got $s6_rc"

# ------------------------------------------------------------------ S7
# Seat-forwarding boundary (v1.5 Phase 4, A-6): the DOCUMENT pipeline's per-role
# seats (COMPOSER_MODEL / REVIEWER_MODEL) shape the bounce's two roles. They must
# NOT leak into the dev-review engine — the engine has its OWN seats/presets.
# Only the base --claude-model is forwarded (a global model choice), and it is
# forwarded from CLAUDE_MODEL_BASE, NOT the per-pass-mutated CLAUDE_MODEL.
ARGV_FILE="$TEST_DIR/argv-s7.txt"
echo "S7: doc-pipeline seats are NOT forwarded; base --claude-model IS"
STUB_EXIT=0
s7_rc=0
COMPOSER_MODEL="gpt-5.5" REVIEWER_MODEL="claude-sonnet-4-5" \
CO_EVOLVE_DEV_REVIEW_SCRIPT="$ENGINE_STUB" \
CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs" \
ARGV_FILE="$ARGV_FILE" \
STUB_EXIT=0 \
PATH="$TEST_DIR/bin:$PATH" \
  bash "$BOUNCER" --skip-interview --auto --execute --claude-model best "seat boundary" \
  >"$TEST_DIR/out-s7.log" 2>&1 || s7_rc=$?
if [[ ! -f "$ARGV_FILE" ]]; then
  note_fail "S7: engine stub never invoked"; cat "$TEST_DIR/out-s7.log"
else
  # No engine flag may carry the doc-pipeline seat model ids.
  if grep -qxF -- "gpt-5.5" "$ARGV_FILE" || grep -qxF -- "claude-sonnet-4-5" "$ARGV_FILE"; then
    note_fail "S7: a doc-pipeline seat (COMPOSER_MODEL/REVIEWER_MODEL) leaked into engine argv"
  else
    note_pass "S7: COMPOSER_MODEL/REVIEWER_MODEL not forwarded to engine"
  fi
  # The base --claude-model must be forwarded (resolved from the `best` alias).
  if argv_has "--claude-model"; then
    cm=$(awk 'prev=="--claude-model"{print; exit} {prev=$0}' "$ARGV_FILE")
    note_pass "S7: base --claude-model forwarded to engine ($cm)"
    # It must be the resolved base, never a doc-role seat value.
    if [[ "$cm" == "gpt-5.5" || "$cm" == "claude-sonnet-4-5" ]]; then
      note_fail "S7: forwarded --claude-model carries a doc-role seat value ($cm)"
    else
      note_pass "S7: forwarded --claude-model is the base choice, not a seat"
    fi
  else
    note_fail "S7: base --claude-model was not forwarded"
  fi
fi

# ------------------------------------------------------------------ S8
# A STUCK bounce must NEVER be handed to the executor (v1.5 Phase 4, A-5 x A-6).
# Use stubs that keep a marker alive through the bounce AND fail adjudication, so
# the run ends `stuck`; the engine must not be invoked and co-evolve must exit
# non-zero.
ARGV_FILE="$TEST_DIR/argv-s8.txt"
echo "S8: a STUCK bounce refuses the --execute hand-off"
mkdir -p "$TEST_DIR/bin-stuck"
# Bounce passes + adjudication all emit a doc that still carries a live marker
# and never a valid ADJUDICATION REPORT => convergence_status=stuck.
cat > "$TEST_DIR/bin-stuck/claude" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --version|-v) echo "claude 1.0.0 (stub)"; exit 0 ;; esac; done
cat > /dev/null
cat <<'DOC'
# Plan
## Approach
Do the thing. [CONTESTED] method A vs B — unresolved. Alternative: A, because simpler.
DOC
STUB
cat > "$TEST_DIR/bin-stuck/codex" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --version|-v) echo "codex 0.1.0 (stub)"; exit 0 ;; esac; done
cat > /dev/null 2>/dev/null || true
out=""; prev=""; for a in "$@"; do [[ "$prev" == "-o" ]] && out="$a"; prev="$a"; done
body='# Plan
## Approach
Do the thing. [CONTESTED] method A vs B — unresolved. Alternative: A, because simpler.'
if [[ -n "$out" ]]; then printf '%s\n' "$body" > "$out"; else printf '%s\n' "$body"; fi
exit 0
STUB
chmod +x "$TEST_DIR/bin-stuck/claude" "$TEST_DIR/bin-stuck/codex"
s8_rc=0
CO_EVOLVE_DEV_REVIEW_SCRIPT="$ENGINE_STUB" \
CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs-s8" \
ARGV_FILE="$ARGV_FILE" \
PATH="$TEST_DIR/bin-stuck:$PATH" \
  bash "$BOUNCER" --skip-interview --auto --execute "stuck plan must not execute" \
  >"$TEST_DIR/out-s8.log" 2>&1 || s8_rc=$?
if [[ -f "$ARGV_FILE" ]]; then
  note_fail "S8: engine ran on a STUCK bounce (must be refused)"
else
  note_pass "S8: engine not invoked on a STUCK bounce"
fi
[[ "$s8_rc" -ne 0 ]] && note_pass "S8: co-evolve exited non-zero on stuck --execute ($s8_rc)" \
  || note_fail "S8: expected non-zero exit on stuck --execute"
grep -q 'STUCK' "$TEST_DIR/out-s8.log" && note_pass "S8: refusal message names the stuck state" \
  || note_fail "S8: no stuck-refusal message in output"

# ------------------------------------------------------------------ summary
echo "----------------------------------------------------------------------"
echo "dev-review hand-off simulation: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
echo "ALL PASS"
