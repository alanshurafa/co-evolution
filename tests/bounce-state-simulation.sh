#!/usr/bin/env bash
# tests/bounce-state-simulation.sh — v1.3 Phase 3 gate: both document bouncers
# emit a conforming bounce-state/1.0 state.json plus plain (not dot-prefixed)
# per-pass clean artifacts. Contract: evals/BOUNCE-RUNNER-CONTRACT.md.
#
# Hermetic: agent CLIs PATH-stubbed; no network, no LLM cost.

set -euo pipefail

TEST_DIR=$(mktemp -d -t bounce-state-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required for this gate"; exit 1; }

# --- stub CLIs ---------------------------------------------------------------
# Pass 1 (reviewer) returns a doc WITH markers; pass 2 (composer) returns a
# doc with NONE, so the loop converges naturally. A per-run counter file
# tracks invocation order.
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in --version|-v) echo "claude 1.0.0 (stub)"; exit 0 ;; esac
done
while IFS= read -r _line; do :; done
count_file="${BOUNCE_STUB_COUNTER:?BOUNCE_STUB_COUNTER not set}"
n=0
[[ -f "$count_file" ]] && n=$(cat "$count_file")
n=$((n + 1))
printf '%s' "$n" > "$count_file"
if (( n % 2 == 1 )); then
  cat <<'DOC'
# Sample Plan

## Approach

The approach is sound but the rollout window is risky.
[CONTESTED] Reviewer says two weeks; the original says one. Pick one and justify it.

## Risks

Need clarity on the rollback owner. [CLARIFY] Who owns rollback during the window?
This revision adds review notes and keeps every original section intact.
DOC
else
  cat <<'DOC'
# Sample Plan

## Approach

The approach is sound and the rollout window is now two weeks, agreed by
both sides after the contested point was resolved with a concrete owner.

## Risks

Rollback is owned by the on-call lead. All markers resolved this pass.
DOC
fi
STUB
chmod +x "$TEST_DIR/bin/claude"

# codex stub: invoke_codex discards stdout and reads the artifact from the
# `-o FILE` argument, so the stub must parse argv and write there.
cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in --version|-v) echo "codex 0.1.0 (stub)"; exit 0 ;; esac
done
output_file=""
prev=""
for arg in "$@"; do
  [[ "$prev" == "-o" ]] && output_file="$arg"
  prev="$arg"
done
while IFS= read -r _line; do :; done
# Stateless: always the converged doc. Only claude-stub calls advance the
# odd/even counter, so the run-naming codex call cannot skew pass content.
doc=$(cat <<'DOC'
# Sample Plan

## Approach

The approach is sound and the rollout window is now two weeks, agreed by
both sides after the contested point was resolved with a concrete owner.

## Risks

Rollback is owned by the on-call lead. All markers resolved this pass.
DOC
)
if [[ -n "$output_file" ]]; then
  printf '%s\n' "$doc" > "$output_file"
else
  printf '%s\n' "$doc"
fi
STUB
chmod +x "$TEST_DIR/bin/codex"

DOC_SRC="$TEST_DIR/input-doc.md"
cat > "$DOC_SRC" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a one-week rollout window with staged percentages.

## Risks

Rollback procedure is undocumented and has no named owner at this time.
DOC

# ---------------------------------------------------------------------------
# Scenario 1: co-evolve-bouncer --vanilla --bounce-only -> conforming state
# ---------------------------------------------------------------------------
# Policy (b): co-evolve-bouncer.sh already supports CO_EVOLVE_RUNS_DIR (v1.4,
# added for the npm MCP embedder) to redirect run artifacts away from its own
# runs/ dir. Pointing it at this sim's own $TEST_DIR makes discovery within
# that private root race-free by construction — no other concurrent suite can
# ever write into it — instead of racing on `ls -dt` against the shared repo
# runs/ dir that every concurrent suite's default invocation also writes to.
CO_EVOLVE_RUNS_DIR="$TEST_DIR/co-evolve-runs"
TOTAL=$((TOTAL + 1))
s1_doc="$TEST_DIR/s1-doc.md"
cp "$DOC_SRC" "$s1_doc"
rc=0
BOUNCE_STUB_COUNTER="$TEST_DIR/s1-count" PATH="$TEST_DIR/bin:$PATH" CO_EVOLVE_RUNS_DIR="$CO_EVOLVE_RUNS_DIR" \
  bash "$REPO_ROOT/co-evolve-bouncer.sh" --vanilla --bounce-only "$s1_doc" \
  > "$TEST_DIR/s1-stdout.log" 2> "$TEST_DIR/s1-stderr.log" || rc=$?

s1_run_dir=$(ls -dt "$CO_EVOLVE_RUNS_DIR"/co-evolve-* 2>/dev/null | head -1)
s1_state="$s1_run_dir/state.json"
if [[ "$rc" -eq 0 && -f "$s1_state" ]] \
   && jq -e '.schema == "bounce-state/1.0"
             and .runner == "co-evolve-bouncer.sh"
             and .mode == "bounce-only"
             and .baseline_file == "original-input.md"
             and .status == "complete"
             and (.passes | length) >= 2
             and .passes[0].role == "reviewer"
             and (.passes[0].total_markers > 0)
             and (.passes[-1].total_markers == 0)
             and (.finished_at != null)' "$s1_state" >/dev/null; then
  pass "S1: co-evolve bounce-only writes conforming bounce-state/1.0"
else
  fail "S1: rc=$rc state=$( [[ -f "$s1_state" ]] && cat "$s1_state" || echo MISSING)"
fi

# Scenario 2: plain pass-N-clean.md artifacts exist (not dot-prefixed).
TOTAL=$((TOTAL + 1))
if [[ -s "$s1_run_dir/pass-1-clean.md" && -s "$s1_run_dir/pass-2-clean.md" ]] \
   && ! ls "$s1_run_dir"/.bounce-pass-*-clean.md >/dev/null 2>&1; then
  pass "S2: plain pass-N-clean.md artifacts persisted (no dot-prefixed clean files)"
else
  fail "S2: clean artifacts wrong: $(ls -a "$s1_run_dir" | tr '\n' ' ')"
fi

# Scenario 3: state pass records agree with the artifacts they point at.
TOTAL=$((TOTAL + 1))
s3_ok=true
for i in 1 2; do
  clean_rel=$(jq -r ".passes[$((i-1))].output_clean" "$s1_state")
  [[ -s "$s1_run_dir/$clean_rel" ]] || s3_ok=false
  state_words=$(jq -r ".passes[$((i-1))].word_count" "$s1_state")
  file_words=$(wc -w < "$s1_run_dir/$clean_rel" | tr -d '\r\n ')
  [[ "$state_words" == "$file_words" ]] || s3_ok=false
done
if [[ "$s3_ok" == true ]]; then
  pass "S3: state pass records match artifact word counts"
else
  fail "S3: state/artifact mismatch"
fi

rm -rf "$s1_run_dir"

# ---------------------------------------------------------------------------
# Scenario 4: aborted run (auth-error stub) -> status "aborted"
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
mkdir -p "$TEST_DIR/authbin"
cat > "$TEST_DIR/authbin/claude" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in --version|-v) echo "claude 1.0.0 (stub)"; exit 0 ;; esac
done
while IFS= read -r _line; do :; done
printf 'Failed to authenticate. Please run `claude login`.\n'
STUB
chmod +x "$TEST_DIR/authbin/claude"
cp "$TEST_DIR/authbin/claude" "$TEST_DIR/authbin/codex"

s4_doc="$TEST_DIR/s4-doc.md"
cp "$DOC_SRC" "$s4_doc"
rc=0
PATH="$TEST_DIR/authbin:$PATH" CO_EVOLVE_RUNS_DIR="$CO_EVOLVE_RUNS_DIR" \
  bash "$REPO_ROOT/co-evolve-bouncer.sh" --vanilla --bounce-only "$s4_doc" \
  > /dev/null 2>&1 || rc=$?
s4_run_dir=$(ls -dt "$CO_EVOLVE_RUNS_DIR"/co-evolve-* 2>/dev/null | head -1)
s4_state="$s4_run_dir/state.json"
if [[ "$rc" -ne 0 && -f "$s4_state" ]] \
   && jq -e '.status == "aborted" and (.passes | length) == 0' "$s4_state" >/dev/null; then
  pass "S4: auth-failure abort marks state status=aborted"
else
  fail "S4: rc=$rc state=$( [[ -f "$s4_state" ]] && cat "$s4_state" || echo MISSING)"
fi
rm -rf "$s4_run_dir"

# ---------------------------------------------------------------------------
# Scenario 5: agent-bouncer -> conforming state + normalized artifact names
# ---------------------------------------------------------------------------
# Policy (c): agent-bouncer.sh hardcodes RUNS_DIR="${REPO_ROOT}/runs" with no
# env override (unlike co-evolve-bouncer.sh's CO_EVOLVE_RUNS_DIR), so it always
# writes into the shared repo runs/ dir that a concurrent suite's own bouncer
# runs also write into. Snapshot-diff instead of `ls -dt | head -1`: list
# before, list after, the run dir is the one new entry — fail loudly if the
# invocation produced zero or more than one new dir (either points at a real
# bug, not this race).
TOTAL=$((TOTAL + 1))
s5_doc="$TEST_DIR/s5-doc.md"
cp "$DOC_SRC" "$s5_doc"
s5_before=$(ls -d "$REPO_ROOT"/runs/bouncer-* 2>/dev/null || true)
rc=0
BOUNCE_STUB_COUNTER="$TEST_DIR/s5-count" PATH="$TEST_DIR/bin:$PATH" \
  bash "$REPO_ROOT/agent-bouncer/agent-bouncer.sh" "$s5_doc" 2 claude claude \
  > "$TEST_DIR/s5-stdout.log" 2>&1 || rc=$?
s5_after=$(ls -d "$REPO_ROOT"/runs/bouncer-* 2>/dev/null || true)
s5_new=$(comm -13 <(printf '%s\n' "$s5_before" | sort) <(printf '%s\n' "$s5_after" | sort))
s5_run_dir=""
# grep -c exits 1 on zero matches, which would trip `set -e` inside a command
# substitution (zero-new-dirs is a real failure mode here, e.g. the invocation
# died before creating one) — `|| true` keeps that a value, not a script kill.
s5_new_count=$(printf '%s\n' "$s5_new" | grep -c . || true)
if [[ "$s5_new_count" -eq 1 ]]; then
  s5_run_dir="$s5_new"
fi
s5_state="$s5_run_dir/state.json"
if [[ "$rc" -eq 0 && -f "$s5_state" ]] \
   && jq -e '.schema == "bounce-state/1.0"
             and .runner == "agent-bouncer.sh"
             and .mode == "agent-bouncer"
             and .status == "complete"
             and (.passes | length) >= 2' "$s5_state" >/dev/null \
   && [[ -s "$s5_run_dir/original-input.md" && -s "$s5_run_dir/pass-1-clean.md" ]]; then
  pass "S5: agent-bouncer writes conforming state + normalized artifact names"
else
  fail "S5: rc=$rc dir=$s5_run_dir state=$( [[ -f "$s5_state" ]] && cat "$s5_state" || echo MISSING)"
fi
rm -rf "$s5_run_dir"

# ---------------------------------------------------------------------------
# Scenario 6: CO_EVOLVE_RUNS_DIR redirects run artifacts (v1.4 MCP enabler)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
s6_doc="$TEST_DIR/s6-doc.md"
cp "$DOC_SRC" "$s6_doc"
s6_runs="$TEST_DIR/s6-runs"
mkdir -p "$s6_runs"
rc=0
CO_EVOLVE_RUNS_DIR="$s6_runs" BOUNCE_STUB_COUNTER="$TEST_DIR/s6-count" PATH="$TEST_DIR/bin:$PATH" \
  bash "$REPO_ROOT/co-evolve-bouncer.sh" --vanilla --bounce-only "$s6_doc" \
  > /dev/null 2>&1 || rc=$?
s6_run_dir=$(ls -dt "$s6_runs"/co-evolve-* 2>/dev/null | head -1)
if [[ "$rc" -eq 0 && -n "$s6_run_dir" && -f "$s6_run_dir/state.json" ]] \
   && ! ls "$REPO_ROOT"/runs/co-evolve-*s6-doc* >/dev/null 2>&1; then
  pass "S6: CO_EVOLVE_RUNS_DIR redirects artifacts away from the repo"
else
  fail "S6: rc=$rc run_dir=$s6_run_dir"
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
