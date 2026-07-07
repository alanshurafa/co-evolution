#!/usr/bin/env bash
# tests/audit-hardening-simulation.sh — 2026-07-07 audit Phase A low-severity
# bundle. Three hermetic gates, one per defect closed:
#
#   B: --agents parsing — a value with no comma (e.g. `--agents claude`) used to
#      self-pair silently (claude,claude) and bounce an agent against itself.
#      It must now die with a clear message; exactly one comma + two non-empty
#      names is the only accepted shape.
#   C: strip_human_summary — used to truncate at the FIRST `^## HUMAN SUMMARY`
#      line, destroying any document whose BODY legitimately contains that
#      heading. It must strip only the LAST (agent-appended, trailing) section.
#   D: count_markers_raw / adjudication receipt gate — the raw marker count used
#      to increment once per LINE, so two of the SAME marker token on one line
#      counted as 1 and the adjudication gate accepted ONE report entry for TWO
#      live markers. The count must be per-occurrence, and the gate must demand a
#      report entry per marker.
#
# Hermetic: agent CLIs PATH-stubbed for the D integration; B and C need no
# network. bash 3.2-safe (Git Bash + Linux + macOS): no arrays-of-arrays, no
# `mapfile`, no `${var^^}`. CRLF-safe: lib helpers already `tr -d '\r'`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"
LIB="$REPO_ROOT/lib/co-evolution.sh"

TEST_DIR=$(mktemp -d -t audit-hardening-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required for this gate"; exit 1; }

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }
check() { TOTAL=$((TOTAL + 1)); if eval "$2"; then pass "$1"; else fail "$1 [cond: $2]"; fi; }

# ===========================================================================
# B: --agents parsing. A malformed value dies during arg parsing before any
# agent is invoked. A VALID pair parses and proceeds, so the B section is run
# under fast converging stubs (reviewer emits a marker-free doc → the loop
# converges on pass 1) to keep the positive control hermetic and quick.
# ===========================================================================
mkdir -p "$TEST_DIR/agentbin"
for a in claude codex; do
  cat > "$TEST_DIR/agentbin/$a" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in --version|-v) echo "stub 1.0.0"; exit 0 ;; esac; done
out=""; prev=""
for x in "$@"; do [[ "$prev" == "-o" ]] && out="$x"; prev="$x"; done
cat >/dev/null 2>&1 || true
body='# Plan

## Approach

Ship it. No open questions remain.'
if [[ -n "$out" ]]; then printf '%s\n' "$body" > "$out"; else printf '%s\n' "$body"; fi
STUB
  chmod +x "$TEST_DIR/agentbin/$a"
done

run_agents() {
  # Returns the bouncer's exit code; captures BOTH streams (die() logs the parse
  # error via log(), which prints to STDOUT before RUN_DIR/run.log exists, so
  # stderr alone would miss the message). --vanilla keeps it non-interactive.
  local val="$1"
  local outlog="$2"
  local rc=0
  PATH="$TEST_DIR/agentbin:$PATH" CO_EVOLVE_RUNS_DIR="$TEST_DIR/agents-runs" \
    bash "$BOUNCER" --agents "$val" --vanilla "some prompt" \
    > "$outlog" 2>&1 || rc=$?
  return $rc
}

B1_ERR="$TEST_DIR/b1.err"; rc=0; run_agents "claude" "$B1_ERR" || rc=$?
check "B1: --agents with no comma exits non-zero (no silent self-pair)" \
  "[[ $rc -ne 0 ]]"
check "B1b: the error message names the comma requirement" \
  "grep -q 'comma' '$B1_ERR'"

B2_ERR="$TEST_DIR/b2.err"; rc=0; run_agents "claude,codex,opus" "$B2_ERR" || rc=$?
check "B2: --agents with two commas (three agents) exits non-zero" \
  "[[ $rc -ne 0 ]]"

B3_ERR="$TEST_DIR/b3.err"; rc=0; run_agents ",codex" "$B3_ERR" || rc=$?
check "B3: --agents with an empty first name exits non-zero" \
  "[[ $rc -ne 0 ]]"

B4_ERR="$TEST_DIR/b4.err"; rc=0; run_agents "claude," "$B4_ERR" || rc=$?
check "B4: --agents with an empty second name exits non-zero" \
  "[[ $rc -ne 0 ]]"

# Positive control: a valid pair must PARSE (it may fail later for lack of a
# real CLI, but it must NOT die with an --agents message). We assert the stderr
# from a valid pair does NOT carry the --agents parse error.
B5_ERR="$TEST_DIR/b5.err"; rc=0; run_agents "claude,codex" "$B5_ERR" || rc=$?
check "B5: a valid comma-separated pair does NOT trip the --agents parse error" \
  "! grep -q '\\-\\-agents requires' '$B5_ERR'"

# B6 (C-8 cross-vendor review): --agents as the LAST argv token — no value at
# all. Pre-fix, `$2` was unbound and set -u killed the script with a raw
# "unbound variable" error instead of the validation message; `${2:-}` now
# routes it into the same clear die. Invoked directly (not via run_agents,
# which always supplies a value after the flag).
B6_OUT="$TEST_DIR/b6.out"; rc=0
bash "$BOUNCER" --vanilla "some prompt" --agents > "$B6_OUT" 2>&1 || rc=$?
check "B6: --agents with NO value exits non-zero" \
  "[[ $rc -ne 0 ]]"
check "B6b: missing value dies with the '--agents requires' message" \
  "grep -q -- '--agents requires' '$B6_OUT'"
check "B6c: no raw set -u 'unbound variable' error leaks" \
  "! grep -qi 'unbound variable' '$B6_OUT'"

# ===========================================================================
# C: strip_human_summary keys on the LAST heading (source the lib directly).
# ===========================================================================
# shellcheck disable=SC1090
source "$LIB"

# A document whose BODY contains `## HUMAN SUMMARY` plus an agent-appended
# trailing `## HUMAN SUMMARY` section. The body heading + everything under it
# up to the trailing section must survive; only the trailing section is stripped.
C_IN="$TEST_DIR/c-in.md"
cat > "$C_IN" <<'DOC'
# Plan

## HUMAN SUMMARY

This heading is part of the document body: it explains what a human summary is.

## Approach

Ship it.

## HUMAN SUMMARY

- pass 1: tightened the approach
DOC
C_OUT="$TEST_DIR/c-out.md"
strip_human_summary "$C_IN" "$C_OUT"
check "C1: body-level '## HUMAN SUMMARY' heading survives the strip" \
  "grep -q '^## HUMAN SUMMARY' '$C_OUT'"
check "C2: exactly ONE '## HUMAN SUMMARY' remains (trailing section removed)" \
  "[[ \$(grep -c '^## HUMAN SUMMARY' '$C_OUT') -eq 1 ]]"
check "C3: the body 'Approach' section is preserved" \
  "grep -q '^## Approach' '$C_OUT'"
check "C4: the trailing per-pass line is gone" \
  "! grep -q 'pass 1: tightened' '$C_OUT'"

# Byte-parity: a document with only ONE (trailing) HUMAN SUMMARY strips exactly
# as the old first-match awk did.
C2_IN="$TEST_DIR/c2-in.md"
printf '# Plan\n\nBody text.\n\n## HUMAN SUMMARY\n\n- pass 1\n' > "$C2_IN"
C2_OUT="$TEST_DIR/c2-out.md"
strip_human_summary "$C2_IN" "$C2_OUT"
C2_EXP="$TEST_DIR/c2-exp.md"
printf '# Plan\n\nBody text.\n\n' > "$C2_EXP"
check "C5: single trailing heading strips byte-identically to the old behavior" \
  "diff -q '$C2_EXP' '$C2_OUT' >/dev/null"

# ===========================================================================
# D-unit: count_markers_raw counts token OCCURRENCES, not lines.
# ===========================================================================
D_DOC="$TEST_DIR/d-two-same.md"
# Two of the SAME marker token on ONE line — the exact undercount case.
printf '# Doc\n\n[CONTESTED] window one vs two weeks.  [CONTESTED] rollback owner unnamed.\n' > "$D_DOC"
check "D1: two [CONTESTED] on one line count as 2 (was 1 under the line-count bug)" \
  "[[ \$(count_markers_raw '$D_DOC' '[CONTESTED]') -eq 2 ]]"
check "D2: a marker-free document still counts 0" \
  "[[ \$(count_markers_raw '$TEST_DIR/c2-exp.md' '[CONTESTED]') -eq 0 ]]"

# ===========================================================================
# D-integration: two identical markers on one line survive the bounce; the
# adjudication receipt gate must demand a report entry PER marker. A one-entry
# adjudicator is now insufficient (run ends stuck); a two-entry adjudicator
# resolves it (adjudicated). Under the old line-count, pre_markers was 1 and the
# one-entry report wrongly passed the gate.
# ===========================================================================
mkdir -p "$TEST_DIR/bin"

# Reviewer (claude, odd passes) and composer (codex, even passes) both emit the
# same two-CONTESTED-on-one-line body so the pair survives to adjudication. The
# codex stub also plays adjudicator: on the adjudication prompt it emits a clean
# body plus a report whose entry count is AH_ADJ_ENTRIES.
BODY_TWO="$TEST_DIR/body-two.txt"
cat > "$BODY_TWO" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a staged rollout.
[CONTESTED] window one week vs two.  [CONTESTED] rollback owner is unnamed.

## Risks

Both disagreements above share a single line on purpose.
DOC

ADJ_BODY="$TEST_DIR/adj-body.txt"   # clean body, no report yet (report appended per entries)
cat > "$ADJ_BODY" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a staged, two-week rollout owned by the on-call lead.

## Risks

Resolved.

## ADJUDICATION REPORT
DOC

cat > "$TEST_DIR/bin/claude" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do case "\$arg" in --version|-v) echo "claude 1.0.0 (stub)"; exit 0 ;; esac; done
cat >/dev/null
cat "$BODY_TWO"
STUB
chmod +x "$TEST_DIR/bin/claude"

cat > "$TEST_DIR/bin/codex" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do case "\$arg" in --version|-v) echo "codex 0.1.0 (stub)"; exit 0 ;; esac; done
prompt=\$(cat 2>/dev/null || true)
out=""; prev=""
for a in "\$@"; do [[ "\$prev" == "-o" ]] && out="\$a"; prev="\$a"; done
emit() { if [[ -n "\$out" ]]; then cat > "\$out"; else cat; fi; }
if printf '%s' "\$prompt" | grep -q 'You are the ADJUDICATOR'; then
  {
    cat "$ADJ_BODY"
    printf -- '- [CONTESTED] window length -> CHOSE: two weeks | WHY: soak time needed.\n'
    if [[ "\${AH_ADJ_ENTRIES:-1}" -ge 2 ]]; then
      printf -- '- [CONTESTED] rollback owner -> CHOSE: on-call lead | WHY: clear accountability.\n'
    fi
  } | emit
else
  cat "$BODY_TWO" | emit
fi
exit 0
STUB
chmod +x "$TEST_DIR/bin/codex"

D_SEED="$TEST_DIR/d-seed.md"
cat > "$D_SEED" <<'DOC'
# Sample Plan

## Approach

Ship the feature in a one-week rollout window.

## Risks

Rollback procedure has no named owner.
DOC

run_d() {
  local runs="$1"; local entries="$2"; local rc=0
  AH_ADJ_ENTRIES="$entries" CO_EVOLVE_RUNS_DIR="$runs" PATH="$TEST_DIR/bin:$PATH" \
    bash "$BOUNCER" --vanilla --bounce-only "$D_SEED" \
    > "$runs.stdout.log" 2> "$runs.stderr.log" || rc=$?
  return $rc
}
d_state() { find "$1" -name state.json 2>/dev/null | head -1; }

# One entry for two markers -> gate refuses -> stuck.
D3_RUNS="$TEST_DIR/d3-runs"
run_d "$D3_RUNS" 1 || true
D3_STATE=$(d_state "$D3_RUNS")
check "D3: one report entry for two same-line markers ends STUCK (gate honest)" \
  "[[ -f '$D3_STATE' ]] && [[ \$(jq -r '.convergence_status' '$D3_STATE') == stuck ]]"

# Two entries for two markers -> gate satisfied -> adjudicated.
D4_RUNS="$TEST_DIR/d4-runs"
run_d "$D4_RUNS" 2 || true
D4_STATE=$(d_state "$D4_RUNS")
check "D4: two report entries for two same-line markers ends ADJUDICATED" \
  "[[ -f '$D4_STATE' ]] && [[ \$(jq -r '.convergence_status' '$D4_STATE') == adjudicated ]]"

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
