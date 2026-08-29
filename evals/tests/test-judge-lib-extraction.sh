#!/usr/bin/env bash
# evals/tests/test-judge-lib-extraction.sh
# Regression gate for the judge-lib extraction: blinding, the trial runner, and
# evidence verification moved from evals/judge-bounce.sh into
# evals/lib/judge-lib.sh, and judge-bounce.sh must stay byte-identical in what
# it emits.
#
# The golden verdict below was captured from the PRE-extraction judge-bounce.sh
# (git HEAD before the move) against the reused fixture run
# evals/tests/fixtures/bounce-runs/resolved-with-edit with the honest PATH-
# stubbed judge CLI defined here. Everything except judged_at (a timestamp) is
# compared byte-for-byte.
#
# Hermetic: no live model calls. Exit 0 all scenarios pass, 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE="$REPO_ROOT/evals/tests/fixtures/bounce-runs/resolved-with-edit"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required"; exit 1; }

TEST_DIR=$(mktemp -d -t judge-lib-extract-XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

# --- Stub judge CLIs (PATH-shadowed, fake-runner pattern) --------------------
mkdir -p "$TEST_DIR/bin-honest" "$TEST_DIR/bin-biased" "$TEST_DIR/bin-liar"

# Honest content-aware stub: prefers whichever document carries the phrase
# "21 day window" (only the fixture's FINAL doc has it), whatever its position.
cat > "$TEST_DIR/bin-honest/claude" <<'STUB'
#!/usr/bin/env bash
input=$(cat)
a_part=$(printf '%s' "$input" | awk '/^## Document A$/{f=1;next} /^## Document B$/{f=0} f')
if printf '%s' "$a_part" | grep -q '21 day window'; then winner="A"; else winner="B"; fi
printf '{"better": "%s", "confidence": "high", "reasons": ["the winning version resolves the rollout-window dispute concretely"], "evidence": [{"doc": "%s", "quote": "21 day window using a staged rollout, extended from 14 days"}]}\n' "$winner" "$winner"
STUB

# Always answers "A" — the position-bias path through the swapped trials.
cat > "$TEST_DIR/bin-biased/claude" <<'STUB'
#!/usr/bin/env bash
cat > /dev/null
printf '{"better": "A", "confidence": "high", "reasons": ["first is better"], "evidence": []}\n'
STUB

# Content-aware verdict, fabricated quote — the evidence-verification path.
cat > "$TEST_DIR/bin-liar/claude" <<'STUB'
#!/usr/bin/env bash
input=$(cat)
a_part=$(printf '%s' "$input" | awk '/^## Document A$/{f=1;next} /^## Document B$/{f=0} f')
if printf '%s' "$a_part" | grep -q '21 day window'; then winner="A"; else winner="B"; fi
printf '{"better": "%s", "confidence": "high", "reasons": ["made up"], "evidence": [{"doc": "%s", "quote": "this exact sentence appears nowhere in either document at all"}]}\n' "$winner" "$winner"
STUB

chmod +x "$TEST_DIR"/bin-*/claude

# --- Golden verdict from the pre-extraction script ---------------------------
# jq -S sorted, judged_at removed.
cat > "$TEST_DIR/golden.json" <<'GOLDEN'
{
  "evidence": [
    {
      "doc": "B",
      "quote": "21 day window using a staged rollout, extended from 14 days",
      "trial": 1,
      "verified": true
    },
    {
      "doc": "A",
      "quote": "21 day window using a staged rollout, extended from 14 days",
      "trial": 2,
      "verified": true
    }
  ],
  "evidence_verified": true,
  "judge_cmd": "claude",
  "judge_effort": "high",
  "judge_model": "claude-fable-5",
  "run_dir": "judge-lib-fixture-run",
  "schema": "bounce-judge/1.0",
  "self_preference_risk": true,
  "trials": [
    {
      "order": "baseline=A final=B",
      "raw": {
        "better": "B",
        "confidence": "high",
        "evidence": [
          {
            "doc": "B",
            "quote": "21 day window using a staged rollout, extended from 14 days"
          }
        ],
        "reasons": [
          "the winning version resolves the rollout-window dispute concretely"
        ]
      }
    },
    {
      "order": "final=A baseline=B",
      "raw": {
        "better": "A",
        "confidence": "high",
        "evidence": [
          {
            "doc": "A",
            "quote": "21 day window using a staged rollout, extended from 14 days"
          }
        ],
        "reasons": [
          "the winning version resolves the rollout-window dispute concretely"
        ]
      }
    }
  ],
  "verdict": "improved"
}
GOLDEN

# A scored, passing run dir to judge. The directory name is load-bearing: it
# lands in the verdict's run_dir field, which the golden diff compares.
make_run() { # $1 = parent dir -> <parent>/judge-lib-fixture-run
  local dest="$1/judge-lib-fixture-run"
  mkdir -p "$1"
  cp -R "$FIXTURE" "$dest"
  rm -f "$dest/EXPECTED.json"
  bash "$REPO_ROOT/evals/score-bounce.sh" --run-dir "$dest" >/dev/null 2>&1
  printf '%s' "$dest"
}

run_judge() { # $1 = stub bin dir, $2 = run dir; judge env cleared for determinism
  env -u JUDGE_CMD -u JUDGE_MODEL -u JUDGE_EFFORT PATH="$1:$PATH" \
    bash "$REPO_ROOT/evals/judge-bounce.sh" --run-dir "$2" >/dev/null 2>&1
}

# --- S1: syntax of both scripts ----------------------------------------------
TOTAL=$((TOTAL + 1))
if bash -n "$REPO_ROOT/evals/lib/judge-lib.sh" && bash -n "$REPO_ROOT/evals/judge-bounce.sh"; then
  pass "S1: judge-lib.sh and judge-bounce.sh parse clean"
else
  fail "S1: bash -n failed"
fi

# --- S2: the lib defines the extracted API, judge-bounce no longer does -------
TOTAL=$((TOTAL + 1))
missing=""
for fn in judge_blind judge_build_trial_prompt judge_invoke_trial judge_run_trial \
          judge_norm judge_reset_evidence_state judge_check_trial_evidence; do
  grep -qE "^$fn\(\)" "$REPO_ROOT/evals/lib/judge-lib.sh" || missing="$missing $fn"
done
stale=""
for fn in blind run_trial norm check_trial_evidence; do
  grep -qE "^$fn\(\)" "$REPO_ROOT/evals/judge-bounce.sh" && stale="$stale $fn"
done
if [[ -z "$missing" && -z "$stale" ]]; then
  pass "S2: extracted API present in the lib, no stale copies left behind"
else
  fail "S2: missing in lib:${missing:-none}; still in judge-bounce:${stale:-none}"
fi

# --- S3: golden verdict, byte-for-byte minus judged_at -----------------------
# CR is stripped from both sides: jq.exe emits CRLF on Windows while this
# script's heredoc golden is LF. Line endings are a platform artifact of the
# comparison, not of the verdict content.
TOTAL=$((TOTAL + 1))
RUN3=$(make_run "$TEST_DIR/s3")
rc=0
run_judge "$TEST_DIR/bin-honest" "$RUN3" || rc=$?
if [[ "$rc" -eq 0 ]] && jq -S 'del(.judged_at)' "$RUN3/judge-verdict.json" | tr -d '\r' > "$TEST_DIR/actual.json" \
   && diff -u "$TEST_DIR/golden.json" "$TEST_DIR/actual.json" > "$TEST_DIR/golden.diff"; then
  pass "S3: verdict matches the pre-extraction golden (minus judged_at)"
else
  fail "S3: rc=$rc; diff vs golden:"
  sed -n '1,40p' "$TEST_DIR/golden.diff" 2>/dev/null || true
fi

# --- S4: judged_at is still emitted and well-formed --------------------------
TOTAL=$((TOTAL + 1))
if jq -e '.judged_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' \
     "$RUN3/judge-verdict.json" >/dev/null 2>&1; then
  pass "S4: judged_at present and ISO-8601 UTC"
else
  fail "S4: judged_at missing or malformed"
fi

# --- S5: position-bias path still routes through the extracted trial runner ---
TOTAL=$((TOTAL + 1))
RUN5=$(make_run "$TEST_DIR/s5")
rc=0
run_judge "$TEST_DIR/bin-biased" "$RUN5" || rc=$?
if [[ "$rc" -eq 0 ]] && jq -e '.verdict == "position_biased"' "$RUN5/judge-verdict.json" >/dev/null 2>&1; then
  pass "S5: order-swap disagreement -> position_biased"
else
  fail "S5: rc=$rc verdict=$(jq -r '.verdict' "$RUN5/judge-verdict.json" 2>/dev/null)"
fi

# --- S6: fabricated evidence still invalidates the verdict -------------------
TOTAL=$((TOTAL + 1))
RUN6=$(make_run "$TEST_DIR/s6")
rc=0
run_judge "$TEST_DIR/bin-liar" "$RUN6" || rc=$?
if [[ "$rc" -eq 0 ]] && jq -e '.verdict == "invalid-evidence" and .evidence_verified == false' \
     "$RUN6/judge-verdict.json" >/dev/null 2>&1; then
  pass "S6: fabricated quote -> invalid-evidence (evidence globals reset per run)"
else
  fail "S6: rc=$rc verdict=$(jq -c '{verdict, evidence_verified}' "$RUN6/judge-verdict.json" 2>/dev/null)"
fi

# --- S7: the lib is sourceable on its own and its pure helpers work ----------
TOTAL=$((TOTAL + 1))
cat > "$TEST_DIR/doc.md" <<'DOC'
# Plan [CONTESTED]

Generated by co-evolve-bouncer

Body line with   collapsing	whitespace.

## HUMAN SUMMARY

should not survive

# After
DOC
s7_out=$(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/lib/co-evolution.sh"
  # shellcheck disable=SC1091
  source "$REPO_ROOT/evals/lib/judge-lib.sh"
  judge_blind "$TEST_DIR/doc.md" > "$TEST_DIR/blinded.md"
  judge_norm "$TEST_DIR/blinded.md"
)
if [[ "$s7_out" != *"[CONTESTED]"* && "$s7_out" != *"should not survive"* \
      && "$s7_out" != *"Generated by co-evolve-bouncer"* \
      && "$s7_out" == *"# After"* && "$s7_out" == *"with collapsing whitespace"* ]]; then
  pass "S7: lib sources standalone; judge_blind + judge_norm behave as extracted"
else
  fail "S7: blinded/normalized output unexpected: $s7_out"
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
