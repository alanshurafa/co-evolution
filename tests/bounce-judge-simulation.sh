#!/usr/bin/env bash
# tests/bounce-judge-simulation.sh — v1.3 Phase 5 gate for evals/judge-bounce.sh
# and evals/report-bounce.sh. Hermetic: the judge CLI is PATH-stubbed.
#
# Scenarios:
#   S1 ordering: judge refuses without bounce-scores.json (exit 2)
#   S2 ordering: judge refuses when overall_pass=false (exit 2)
#   S3 agree path: content-aware stub -> verdict=improved across both orders
#   S4 position-bias path: stub always answers "A" -> position_biased
#   S5 malformed path: stub returns garbage twice -> exit 3, no verdict file
#   S6 fabricated evidence -> verdict=invalid-evidence
#   S7 report: HUMAN-REPORT.md renders all sections incl. judge verdict

set -euo pipefail

TEST_DIR=$(mktemp -d -t bounce-judge-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$REPO_ROOT/evals/tests/fixtures/bounce-runs/resolved-with-edit"

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required"; exit 1; }

# A scored, passing run dir to judge (fresh copy per scenario).
make_run() {
  local dest="$1"
  cp -R "$FIXTURE" "$dest"
  rm -f "$dest/EXPECTED.json"
  bash "$REPO_ROOT/evals/score-bounce.sh" --run-dir "$dest" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# S1: no scores file -> exit 2
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
cp -R "$FIXTURE" "$TEST_DIR/s1"
rm -f "$TEST_DIR/s1/EXPECTED.json"
rc=0
bash "$REPO_ROOT/evals/judge-bounce.sh" --run-dir "$TEST_DIR/s1" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 && ! -f "$TEST_DIR/s1/judge-verdict.json" ]]; then
  pass "S1: refuses to judge without bounce-scores.json (exit 2)"
else
  fail "S1: expected exit 2, got $rc"
fi

# ---------------------------------------------------------------------------
# S2: failing scores -> exit 2
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
cp -R "$REPO_ROOT/evals/tests/fixtures/bounce-runs/rubber-stamp" "$TEST_DIR/s2"
rm -f "$TEST_DIR/s2/EXPECTED.json"
bash "$REPO_ROOT/evals/score-bounce.sh" --run-dir "$TEST_DIR/s2" >/dev/null 2>&1 || true
rc=0
bash "$REPO_ROOT/evals/judge-bounce.sh" --run-dir "$TEST_DIR/s2" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 && ! -f "$TEST_DIR/s2/judge-verdict.json" ]]; then
  pass "S2: refuses to judge a run that failed the behavior gate (exit 2)"
else
  fail "S2: expected exit 2, got $rc"
fi

# ---------------------------------------------------------------------------
# Judge stubs
# ---------------------------------------------------------------------------
mkdir -p "$TEST_DIR/bin-honest" "$TEST_DIR/bin-biased" "$TEST_DIR/bin-broken" "$TEST_DIR/bin-liar"

# Honest content-aware stub: prefers whichever document contains the marker
# phrase "21 day window" (only the FINAL fixture doc has it), regardless of
# position. Quotes verbatim from that document.
cat > "$TEST_DIR/bin-honest/claude" <<'STUB'
#!/usr/bin/env bash
input=$(cat)
a_part=$(printf '%s' "$input" | awk '/^## Document A$/{f=1;next} /^## Document B$/{f=0} f')
if printf '%s' "$a_part" | grep -q '21 day window'; then
  winner="A"
else
  winner="B"
fi
printf '{"better": "%s", "confidence": "high", "reasons": ["the winning version resolves the rollout-window dispute concretely"], "evidence": [{"doc": "%s", "quote": "21 day window using a staged rollout, extended from 14 days"}]}\n' "$winner" "$winner"
STUB
chmod +x "$TEST_DIR/bin-honest/claude"

# Position-biased stub: always prefers Document A.
cat > "$TEST_DIR/bin-biased/claude" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
printf '{"better": "A", "confidence": "high", "reasons": ["first is better"], "evidence": []}\n'
STUB
chmod +x "$TEST_DIR/bin-biased/claude"

# Broken stub: never valid JSON.
cat > "$TEST_DIR/bin-broken/claude" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
echo "I think Document A is nicer, but I refuse to emit JSON."
STUB
chmod +x "$TEST_DIR/bin-broken/claude"

# Liar stub: content-aware verdict but fabricated evidence quote.
cat > "$TEST_DIR/bin-liar/claude" <<'STUB'
#!/usr/bin/env bash
input=$(cat)
a_part=$(printf '%s' "$input" | awk '/^## Document A$/{f=1;next} /^## Document B$/{f=0} f')
if printf '%s' "$a_part" | grep -q '21 day window'; then winner="A"; else winner="B"; fi
printf '{"better": "%s", "confidence": "high", "reasons": ["made up"], "evidence": [{"doc": "%s", "quote": "this exact sentence appears nowhere in either document at all"}]}\n' "$winner" "$winner"
STUB
chmod +x "$TEST_DIR/bin-liar/claude"

# ---------------------------------------------------------------------------
# S3: honest judge -> improved, evidence verified
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
make_run "$TEST_DIR/s3"
rc=0
PATH="$TEST_DIR/bin-honest:$PATH" bash "$REPO_ROOT/evals/judge-bounce.sh" --run-dir "$TEST_DIR/s3" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && jq -e '.verdict == "improved" and .evidence_verified == true and .self_preference_risk == true' "$TEST_DIR/s3/judge-verdict.json" >/dev/null 2>&1; then
  pass "S3: order-swapped agreement -> verdict=improved, evidence verified"
else
  fail "S3: rc=$rc verdict=$(jq -c '{verdict, evidence_verified}' "$TEST_DIR/s3/judge-verdict.json" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# S4: position-biased judge -> position_biased, no quality claim
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
make_run "$TEST_DIR/s4"
rc=0
PATH="$TEST_DIR/bin-biased:$PATH" bash "$REPO_ROOT/evals/judge-bounce.sh" --run-dir "$TEST_DIR/s4" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && jq -e '.verdict == "position_biased"' "$TEST_DIR/s4/judge-verdict.json" >/dev/null 2>&1; then
  pass "S4: order-swap disagreement -> position_biased"
else
  fail "S4: rc=$rc verdict=$(jq -r '.verdict' "$TEST_DIR/s4/judge-verdict.json" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# S5: malformed judge output -> exit 3, no verdict written
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
make_run "$TEST_DIR/s5"
rc=0
PATH="$TEST_DIR/bin-broken:$PATH" bash "$REPO_ROOT/evals/judge-bounce.sh" --run-dir "$TEST_DIR/s5" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 3 && ! -f "$TEST_DIR/s5/judge-verdict.json" ]]; then
  pass "S5: unparseable judge output -> exit 3, no verdict file"
else
  fail "S5: expected exit 3 + no verdict, got rc=$rc"
fi

# ---------------------------------------------------------------------------
# S6: fabricated evidence -> invalid-evidence
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
make_run "$TEST_DIR/s6"
rc=0
PATH="$TEST_DIR/bin-liar:$PATH" bash "$REPO_ROOT/evals/judge-bounce.sh" --run-dir "$TEST_DIR/s6" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && jq -e '.verdict == "invalid-evidence" and .evidence_verified == false' "$TEST_DIR/s6/judge-verdict.json" >/dev/null 2>&1; then
  pass "S6: fabricated quote -> verdict=invalid-evidence"
else
  fail "S6: rc=$rc verdict=$(jq -c '{verdict, evidence_verified}' "$TEST_DIR/s6/judge-verdict.json" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# S7: HUMAN-REPORT.md renders every section, including the judge verdict
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
rc=0
bash "$REPO_ROOT/evals/report-bounce.sh" --run-dir "$TEST_DIR/s3" >/dev/null 2>&1 || rc=$?
report="$TEST_DIR/s3/HUMAN-REPORT.md"
s7_ok=true
for token in "## What happened" "## Pass by pass" "## What happened to each disagreement" "## Scorecard" "## Independent quality judgment" "## What we cannot measure"; do
  grep -qF "$token" "$report" 2>/dev/null || { s7_ok=false; break; }
done
grep -q 'better' "$report" 2>/dev/null || s7_ok=false
if [[ "$rc" -eq 0 && "$s7_ok" == true ]]; then
  pass "S7: HUMAN-REPORT.md renders all sections with the judge verdict"
else
  fail "S7: rc=$rc; missing section token ($token)"
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
