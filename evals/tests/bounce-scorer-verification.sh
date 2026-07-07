#!/usr/bin/env bash
# evals/tests/bounce-scorer-verification.sh — v1.3 Phase 4 gate for
# evals/score-bounce.sh.
#
# Tier 1: frozen synthetic fixtures with EXPECTED.json (resolved-with-edit,
#         deleted-with-section, expired-at-final, rubber-stamp)
# Tier 2: artifact-parsing fallback (no state.json) + dotted legacy clean names
# Tier 3: determinism — double run, byte-identical after stripping scored_at
#
# Hermetic: no LLM calls; needs jq + mikefarah yq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures/bounce-runs"
SCORER="$REPO_ROOT/evals/score-bounce.sh"

TEST_DIR=$(mktemp -d -t bounce-scorer-verify-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Tier 1: frozen fixtures vs EXPECTED.json
# ---------------------------------------------------------------------------
for fixture_dir in "$FIXTURES"/*/; do
  fixture=$(basename "$fixture_dir")
  TOTAL=$((TOTAL + 1))
  expected="$fixture_dir/EXPECTED.json"
  [[ -f "$expected" ]] || { fail "Tier 1 / $fixture: EXPECTED.json missing"; continue; }

  out="$TEST_DIR/scores-$fixture.json"
  rc=0
  bash "$SCORER" --run-dir "$fixture_dir" --output "$out" >/dev/null 2>&1 || rc=$?

  want_pass=$(jq -r '.overall_pass' "$expected")
  # Scorer exits 0 on PASS, 1 on FAIL — exit code must agree with EXPECTED.
  if [[ "$want_pass" == "true" && "$rc" -ne 0 ]] || [[ "$want_pass" == "false" && "$rc" -eq 0 ]]; then
    fail "Tier 1 / $fixture: exit code $rc disagrees with expected overall_pass=$want_pass"
    continue
  fi

  ok=true
  jq -e --argjson exp "$(cat "$expected")" '
    (.overall_pass == $exp.overall_pass)
    and (.mode == $exp.mode)
    and (.source == $exp.source)
    and (.pass_count == $exp.pass_count)
    and (([.marker_ledger[].fate] | sort) == ($exp.ledger_fates | sort))
  ' "$out" >/dev/null || ok=false

  if [[ "$ok" == true ]] && jq -e 'has("failing_checks_include")' "$expected" >/dev/null; then
    while IFS= read -r check; do
      # Windows-native jq emits CRLF line endings; strip the trailing \r or
      # $check never matches the clean scorer check name.
      check=${check%$'\r'}
      jq -e --arg c "$check" '[.dimensions[].checks[]? | select(.ok == false) | .name] | index($c) != null' "$out" >/dev/null || ok=false
    done < <(jq -r '.failing_checks_include[]' "$expected")
  fi

  if [[ "$ok" == true ]]; then
    pass "Tier 1 / $fixture"
  else
    fail "Tier 1 / $fixture: output disagrees with EXPECTED.json — $(jq -c '{overall_pass, mode, source, pass_count, fates: [.marker_ledger[].fate]}' "$out")"
  fi
done

# ---------------------------------------------------------------------------
# Tier 2a: artifact-parsing fallback (state.json removed)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
cp -R "$FIXTURES/resolved-with-edit" "$TEST_DIR/no-state"
rm -f "$TEST_DIR/no-state/state.json" "$TEST_DIR/no-state/EXPECTED.json"
rc=0
bash "$SCORER" --run-dir "$TEST_DIR/no-state" --output "$TEST_DIR/no-state-scores.json" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && jq -e '.source == "artifacts" and .overall_pass == true and .pass_count == 2' "$TEST_DIR/no-state-scores.json" >/dev/null; then
  pass "Tier 2a / artifact fallback scores a state-less run"
else
  fail "Tier 2a / artifact fallback: rc=$rc $(cat "$TEST_DIR/no-state-scores.json" 2>/dev/null | jq -c '{source, overall_pass, pass_count}' 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Tier 2b: dotted legacy clean-pass names (pre-v1.3 co-evolve runs)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
cp -R "$FIXTURES/resolved-with-edit" "$TEST_DIR/legacy-names"
rm -f "$TEST_DIR/legacy-names/state.json" "$TEST_DIR/legacy-names/EXPECTED.json"
mv "$TEST_DIR/legacy-names/pass-1-clean.md" "$TEST_DIR/legacy-names/.bounce-pass-1-clean.md"
mv "$TEST_DIR/legacy-names/pass-2-clean.md" "$TEST_DIR/legacy-names/.bounce-pass-2-clean.md"
rc=0
bash "$SCORER" --run-dir "$TEST_DIR/legacy-names" --output "$TEST_DIR/legacy-scores.json" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && jq -e '.pass_count == 2 and .overall_pass == true' "$TEST_DIR/legacy-scores.json" >/dev/null; then
  pass "Tier 2b / dotted legacy pass names still discovered"
else
  fail "Tier 2b / legacy names: rc=$rc $(jq -c '{pass_count, overall_pass}' "$TEST_DIR/legacy-scores.json" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Tier 3: determinism — double run byte-compare (scored_at stripped)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
bash "$SCORER" --run-dir "$FIXTURES/resolved-with-edit" --output "$TEST_DIR/det-1.json" >/dev/null 2>&1 || true
bash "$SCORER" --run-dir "$FIXTURES/resolved-with-edit" --output "$TEST_DIR/det-2.json" >/dev/null 2>&1 || true
jq 'del(.scored_at)' "$TEST_DIR/det-1.json" > "$TEST_DIR/det-1-stripped.json"
jq 'del(.scored_at)' "$TEST_DIR/det-2.json" > "$TEST_DIR/det-2-stripped.json"
if cmp -s "$TEST_DIR/det-1-stripped.json" "$TEST_DIR/det-2-stripped.json"; then
  pass "Tier 3 / determinism: double run byte-identical after stripping scored_at"
else
  fail "Tier 3 / determinism: outputs differ"
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
