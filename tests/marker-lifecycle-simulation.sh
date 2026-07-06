#!/usr/bin/env bash
# tests/marker-lifecycle-simulation.sh — v1.5 Phase 4 (A-5) gate: the bouncer
# never misrepresents convergence. Every run ends in exactly one of three
# convergence states, each with its guarantees:
#
#   converged  — markers hit 0 naturally within the configured passes. The
#                emitted document is BYTE-IDENTICAL to what the pre-Phase-4
#                (master) bouncer produced on the same input (no extra pass, no
#                changed prompt on this path).
#   adjudicated — markers survived the configured passes; ONE forced-
#                adjudication pass resolved every one and wrote a well-formed
#                adjudication-report.md (>= one CHOSE/WHY bullet per surviving
#                marker). The final document carries 0 live markers.
#   stuck      — the adjudication pass could NOT defensibly resolve every marker
#                (no report, malformed report, or markers still live). The
#                working document is preserved WITH its markers, labeled with a
#                loud CO-EVOLVE:STUCK banner, and is NOT presented as clean.
#
# Byte-parity is PROVEN, not asserted: the converging scenario runs the pristine
# master co-evolve-bouncer.sh (via `git show`, placed at the repo root so its
# SCRIPT_DIR resolves lib/) with the identical stub + input, then diffs the
# emitted document.
#
# Hermetic: agent CLIs PATH-stubbed; the adjudication branch is selected by the
# stub sniffing the prompt for the adjudication template's signature. No
# network, no real claude/codex, no LLM cost. bash 3.2-safe (Git Bash + Linux +
# macOS): no arrays-of-arrays, no `mapfile`, no `${var^^}`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"
MASTER_REF="${MARKER_LIFECYCLE_MASTER_REF:-f8b4f1b}"  # pre-Phase-4 baseline

TEST_DIR=$(mktemp -d -t marker-lifecycle-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; rm -f "$REPO_ROOT/_master-lifecycle-bouncer.sh"; }
trap cleanup EXIT

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required for this gate"; exit 1; }

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }
check() { TOTAL=$((TOTAL + 1)); if eval "$2"; then pass "$1"; else fail "$1 [cond: $2]"; fi; }

# ---------------------------------------------------------------------------
# Stub agents. Behavior is driven by two env knobs the stubs read:
#   LC_STUB_DOC     — which bounce-pass body to emit: "markers" (never converge)
#                     or "clean" (converge). Default "markers".
#   LC_ADJ_MODE     — adjudication behavior when the prompt is an adjudication
#                     prompt: "resolve" (clean body + valid report) or
#                     "fail" (body still carries a live marker, no report).
# The stub detects the adjudication pass by the template's signature line.
# ---------------------------------------------------------------------------
mkdir -p "$TEST_DIR/bin"

# Shared bodies. The "markers" body always carries one [CONTESTED] note so the
# bounce can never converge on its own; "clean" carries none.
write_bodies() {
  cat > "$TEST_DIR/body-markers.txt" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a staged rollout.
[CONTESTED] Reviewer wants two weeks; the plan says one. Alternative: use two weeks because the staged percentages need soak time.

## Risks

Rollback owner is not yet named. This revision keeps every original section intact and adds review notes.
DOC
  cat > "$TEST_DIR/body-clean.txt" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a staged, two-week rollout agreed by both sides.

## Risks

Rollback is owned by the on-call lead. No open questions remain in this document.
DOC
  cat > "$TEST_DIR/body-adj-resolve.txt" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a staged, two-week rollout — the decisive choice.

## Risks

Rollback is owned by the on-call lead.

## ADJUDICATION REPORT

- [CONTESTED] rollout window length -> CHOSE: two weeks | WHY: staged percentages need soak time; the extra week is the cheaper risk.
DOC
  # Fail mode: body STILL carries a live marker and there is no report section.
  cat > "$TEST_DIR/body-adj-fail.txt" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a staged rollout.
[CONTESTED] Still unresolved — the adjudicator could not decide.

## Risks

Rollback owner still unnamed.
DOC
  # Fenced-marker body (adversarial-review fix): the only marker token lives
  # INSIDE a ```yaml fence, so fence-aware count_markers sees 0 — the exact
  # hole that let a run present as "converged" with the token still in the
  # final document. The honesty gate's raw count must catch it.
  cat > "$TEST_DIR/body-fenced.txt" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a staged rollout window with soak checkpoints.

```yaml
rollout:
  note: "[CONTESTED] window length disputed — one week vs two weeks"
```

## Risks

Rollback is owned by the on-call lead. The fenced example above still carries
a live disagreement token that per-pass fence-aware counting cannot see.
DOC
}
write_bodies

# claude stub: reads prompt from stdin, branches on the adjudication signature.
cat > "$TEST_DIR/bin/claude" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do case "\$arg" in --version|-v) echo "claude 1.0.0 (stub)"; exit 0 ;; esac; done
prompt=\$(cat)
if printf '%s' "\$prompt" | grep -q 'You are the ADJUDICATOR'; then
  if [[ "\${LC_ADJ_MODE:-resolve}" == "fail" ]]; then cat "$TEST_DIR/body-adj-fail.txt"; else cat "$TEST_DIR/body-adj-resolve.txt"; fi
else
  case "\${LC_STUB_DOC:-markers}" in
    clean)  cat "$TEST_DIR/body-clean.txt" ;;
    fenced) cat "$TEST_DIR/body-fenced.txt" ;;
    *)      cat "$TEST_DIR/body-markers.txt" ;;
  esac
fi
STUB
chmod +x "$TEST_DIR/bin/claude"

# codex stub: writes to the `-o FILE` target, same branching.
cat > "$TEST_DIR/bin/codex" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do case "\$arg" in --version|-v) echo "codex 0.1.0 (stub)"; exit 0 ;; esac; done
prompt=\$(cat 2>/dev/null || true)
out=""; prev=""
for a in "\$@"; do [[ "\$prev" == "-o" ]] && out="\$a"; prev="\$a"; done
pick() { if [[ -n "\$out" ]]; then cat "\$1" > "\$out"; else cat "\$1"; fi; }
if printf '%s' "\$prompt" | grep -q 'You are the ADJUDICATOR'; then
  if [[ "\${LC_ADJ_MODE:-resolve}" == "fail" ]]; then pick "$TEST_DIR/body-adj-fail.txt"; else pick "$TEST_DIR/body-adj-resolve.txt"; fi
else
  case "\${LC_STUB_DOC:-markers}" in
    clean)  pick "$TEST_DIR/body-clean.txt" ;;
    fenced) pick "$TEST_DIR/body-fenced.txt" ;;
    *)      pick "$TEST_DIR/body-markers.txt" ;;
  esac
fi
exit 0
STUB
chmod +x "$TEST_DIR/bin/codex"

SEED="$TEST_DIR/seed.md"
cat > "$SEED" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a one-week rollout window with staged percentages.

## Risks

Rollback procedure is undocumented and has no named owner at this time.
DOC

# Run the branch bouncer; echo the run dir on stdout (fd 3 trick avoided for
# bash 3.2). Returns the bouncer's exit code.
run_branch() {
  local runs="$1"; shift
  local rc=0
  CO_EVOLVE_RUNS_DIR="$runs" PATH="$TEST_DIR/bin:$PATH" \
    bash "$BOUNCER" "$@" > "$runs.stdout.log" 2> "$runs.stderr.log" || rc=$?
  return $rc
}
find_state() { find "$1" -name state.json 2>/dev/null | head -1; }
final_doc() {
  # The RUN_LABEL.md file: top-level .md that is not a known artifact.
  ls "$1"/*.md 2>/dev/null | grep -viE '/(working|original-input|compose-output)\.md$|pass-|clean|raw|adjudication-report|HUMAN-REPORT' | head -1
}

# ===========================================================================
# Scenario 1: CONVERGED — clean stub, byte-parity vs master.
# ===========================================================================
S1_RUNS="$TEST_DIR/s1-runs"
rc=0; LC_STUB_DOC=clean run_branch "$S1_RUNS" --vanilla --bounce-only "$SEED" || rc=$?
S1_STATE=$(find_state "$S1_RUNS"); S1_DIR=$(dirname "$S1_STATE" 2>/dev/null || echo "")
check "S1a: converged run exits 0" "[[ $rc -eq 0 ]]"
check "S1b: convergence_status == converged" \
  "[[ -f '$S1_STATE' ]] && [[ \$(jq -r '.convergence_status' '$S1_STATE') == converged ]]"
check "S1c: schema bumped to bounce-state/1.1" \
  "[[ -f '$S1_STATE' ]] && jq -e '.schema == \"bounce-state/1.1\"' '$S1_STATE' >/dev/null"
check "S1d: no adjudication-report.md on a converged run" \
  "[[ -n '$S1_DIR' ]] && [[ ! -f '$S1_DIR/adjudication-report.md' ]]"

# Byte-parity: run pristine master on the identical stub+input and diff the doc.
git -C "$REPO_ROOT" show "$MASTER_REF:co-evolve-bouncer.sh" > "$REPO_ROOT/_master-lifecycle-bouncer.sh"
S1M_RUNS="$TEST_DIR/s1-master-runs"
rc_m=0
CO_EVOLVE_RUNS_DIR="$S1M_RUNS" PATH="$TEST_DIR/bin:$PATH" LC_STUB_DOC=clean \
  bash "$REPO_ROOT/_master-lifecycle-bouncer.sh" --vanilla --bounce-only "$SEED" \
  > "$TEST_DIR/s1-master.stdout.log" 2>&1 || rc_m=$?
rm -f "$REPO_ROOT/_master-lifecycle-bouncer.sh"
S1M_DIR=$(dirname "$(find_state "$S1M_RUNS")" 2>/dev/null || echo "")
TOTAL=$((TOTAL + 1))
if [[ -n "$S1_DIR" && -n "$S1M_DIR" && -f "$S1_DIR/working.md" && -f "$S1M_DIR/working.md" ]] \
   && diff -q "$S1M_DIR/working.md" "$S1_DIR/working.md" >/dev/null 2>&1; then
  pass "S1e: BYTE-PARITY — converged working.md identical to master ($MASTER_REF)"
else
  fail "S1e: byte-parity broken (master rc=$rc_m); diff:"
  diff "$S1M_DIR/working.md" "$S1_DIR/working.md" 2>&1 | head -20 || true
fi
# Final emitted doc also identical.
S1_FINAL=$(final_doc "$S1_DIR"); S1M_FINAL=$(final_doc "$S1M_DIR")
check "S1f: BYTE-PARITY — converged final .md identical to master" \
  "[[ -n '$S1_FINAL' && -n '$S1M_FINAL' ]] && diff -q '$S1M_FINAL' '$S1_FINAL' >/dev/null 2>&1"

# ===========================================================================
# Scenario 2: ADJUDICATED — markers survive, adjudication resolves them.
# ===========================================================================
S2_RUNS="$TEST_DIR/s2-runs"
rc=0; LC_STUB_DOC=markers LC_ADJ_MODE=resolve run_branch "$S2_RUNS" --vanilla --bounce-only "$SEED" || rc=$?
S2_STATE=$(find_state "$S2_RUNS"); S2_DIR=$(dirname "$S2_STATE" 2>/dev/null || echo "")
S2_FINAL=$(final_doc "$S2_DIR")
check "S2a: adjudicated run exits 0" "[[ $rc -eq 0 ]]"
check "S2b: convergence_status == adjudicated" \
  "[[ -f '$S2_STATE' ]] && [[ \$(jq -r '.convergence_status' '$S2_STATE') == adjudicated ]]"
check "S2c: adjudication-report.md exists and is non-empty" \
  "[[ -s '$S2_DIR/adjudication-report.md' ]]"
check "S2d: report maps every marker (>=1 CHOSE/WHY bullet)" \
  "grep -Eq '^[[:space:]]*[-*][[:space:]]+\[(CONTESTED|CLARIFY)\].*CHOSE:.*WHY:' '$S2_DIR/adjudication-report.md'"
check "S2e: final document carries 0 live markers" \
  "[[ -n '$S2_FINAL' ]] && [[ \$(grep -cE '\[(CONTESTED|CLARIFY)\]' '$S2_FINAL' || true) -eq 0 ]]"
check "S2f: final document is NOT labeled stuck" \
  "[[ -n '$S2_FINAL' ]] && ! grep -q 'CO-EVOLVE:STUCK' '$S2_FINAL'"
# The report section must NOT leak into working.md (it is stripped to its own file).
check "S2g: ADJUDICATION REPORT section stripped from working.md" \
  "[[ -f '$S2_DIR/working.md' ]] && ! grep -q '## ADJUDICATION REPORT' '$S2_DIR/working.md'"

# ===========================================================================
# Scenario 3: STUCK — adjudication cannot resolve; markers preserved.
# ===========================================================================
S3_RUNS="$TEST_DIR/s3-runs"
rc=0; LC_STUB_DOC=markers LC_ADJ_MODE=fail run_branch "$S3_RUNS" --vanilla --bounce-only "$SEED" || rc=$?
S3_STATE=$(find_state "$S3_RUNS"); S3_DIR=$(dirname "$S3_STATE" 2>/dev/null || echo "")
S3_FINAL=$(final_doc "$S3_DIR")
check "S3a: stuck run still finalizes state (status complete)" \
  "[[ -f '$S3_STATE' ]] && [[ \$(jq -r '.status' '$S3_STATE') == complete ]]"
check "S3b: convergence_status == stuck" \
  "[[ -f '$S3_STATE' ]] && [[ \$(jq -r '.convergence_status' '$S3_STATE') == stuck ]]"
check "S3c: final document labeled with CO-EVOLVE:STUCK banner" \
  "[[ -n '$S3_FINAL' ]] && grep -q 'CO-EVOLVE:STUCK' '$S3_FINAL'"
check "S3d: STUCK final PRESERVES the unresolved marker" \
  "[[ -n '$S3_FINAL' ]] && [[ \$(grep -cE '\[(CONTESTED|CLARIFY)\]' '$S3_FINAL' || true) -ge 1 ]]"
check "S3e: working.md (preserved) still carries the marker" \
  "[[ -f '$S3_DIR/working.md' ]] && [[ \$(grep -cE '\[(CONTESTED|CLARIFY)\]' '$S3_DIR/working.md' || true) -ge 1 ]]"

# ===========================================================================
# Scenario 4: the deterministic scorer FAILS the gate on a stuck run and
# surfaces convergence_status.
# ===========================================================================
if [[ -n "$S3_DIR" ]]; then
  rc=0
  bash "$REPO_ROOT/evals/score-bounce.sh" --run-dir "$S3_DIR" --output "$S3_DIR/scores.json" >/dev/null 2>&1 || rc=$?
  check "S4a: scorer exits non-zero (gate FAIL) on a stuck run" "[[ $rc -ne 0 ]]"
  check "S4b: scores.json convergence_status == stuck" \
    "[[ -f '$S3_DIR/scores.json' ]] && [[ \$(jq -r '.convergence_status' '$S3_DIR/scores.json') == stuck ]]"
  check "S4c: scorer overall_pass == false on stuck" \
    "[[ -f '$S3_DIR/scores.json' ]] && jq -e '.overall_pass == false' '$S3_DIR/scores.json' >/dev/null"
fi

# ===========================================================================
# Scenario 5: CHAIN mode gets the same post-final adjudication (never
# early-converges; surviving markers -> adjudication).
# ===========================================================================
S5_RUNS="$TEST_DIR/s5-runs"
rc=0; LC_STUB_DOC=markers LC_ADJ_MODE=resolve run_branch "$S5_RUNS" --vanilla --chain --bounce-only "$SEED" || rc=$?
S5_STATE=$(find_state "$S5_RUNS"); S5_DIR=$(dirname "$S5_STATE" 2>/dev/null || echo "")
check "S5a: chain run reaches adjudication (convergence_status set)" \
  "[[ -f '$S5_STATE' ]] && [[ \$(jq -r '.convergence_status' '$S5_STATE') == adjudicated ]]"
check "S5b: chain adjudicated run produced adjudication-report.md" \
  "[[ -s '$S5_DIR/adjudication-report.md' ]]"
check "S5c: chain ran its fixed 3 passes before adjudication" \
  "[[ -f '$S5_STATE' ]] && [[ \$(jq -r '.passes | length' '$S5_STATE') -eq 3 ]]"

# ===========================================================================
# Scenario 6: FENCED marker (adversarial-review fix) — a marker inside a
# ```yaml fence is invisible to fence-aware per-pass counting, so the loop
# early-breaks "converged"; the raw honesty gate must catch it and force
# adjudication. With a resolving adjudicator the run ends `adjudicated`,
# NEVER `converged`.
# ===========================================================================
S6_RUNS="$TEST_DIR/s6-runs"
rc=0; LC_STUB_DOC=fenced LC_ADJ_MODE=resolve run_branch "$S6_RUNS" --vanilla --bounce-only "$SEED" || rc=$?
S6_STATE=$(find_state "$S6_RUNS"); S6_DIR=$(dirname "$S6_STATE" 2>/dev/null || echo "")
S6_FINAL=$(final_doc "$S6_DIR")
check "S6a: fenced-marker run is NOT presented as converged" \
  "[[ -f '$S6_STATE' ]] && [[ \$(jq -r '.convergence_status' '$S6_STATE') != converged ]]"
check "S6b: fenced-marker run ends adjudicated (resolving adjudicator)" \
  "[[ -f '$S6_STATE' ]] && [[ \$(jq -r '.convergence_status' '$S6_STATE') == adjudicated ]]"
check "S6c: adjudication-report.md written for the fenced survivor" \
  "[[ -s '$S6_DIR/adjudication-report.md' ]]"
check "S6d: final document carries 0 marker tokens (raw grep, fences included)" \
  "[[ -n '$S6_FINAL' ]] && [[ \$(grep -cE '\[(CONTESTED|CLARIFY)\]' '$S6_FINAL' || true) -eq 0 ]]"

# ===========================================================================
# Scenario 7: FENCED marker + failing adjudicator — the run must end `stuck`
# with the fenced token preserved, never silent-converged.
# ===========================================================================
S7_RUNS="$TEST_DIR/s7-runs"
rc=0; LC_STUB_DOC=fenced LC_ADJ_MODE=fail run_branch "$S7_RUNS" --vanilla --bounce-only "$SEED" || rc=$?
S7_STATE=$(find_state "$S7_RUNS"); S7_DIR=$(dirname "$S7_STATE" 2>/dev/null || echo "")
S7_FINAL=$(final_doc "$S7_DIR")
check "S7a: fenced-marker run with failed adjudication ends stuck" \
  "[[ -f '$S7_STATE' ]] && [[ \$(jq -r '.convergence_status' '$S7_STATE') == stuck ]]"
check "S7b: stuck fenced run labeled with CO-EVOLVE:STUCK banner" \
  "[[ -n '$S7_FINAL' ]] && grep -q 'CO-EVOLVE:STUCK' '$S7_FINAL'"
check "S7c: fenced marker token preserved in the stuck document" \
  "[[ -f '$S7_DIR/working.md' ]] && [[ \$(grep -cE '\[(CONTESTED|CLARIFY)\]' '$S7_DIR/working.md' || true) -ge 1 ]]"

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
