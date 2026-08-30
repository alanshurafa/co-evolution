#!/usr/bin/env bash

# benchmarks/tests/test-report.sh — contract tests for benchmarks/report.sh.
#
# Every number asserted here was computed by hand from the toy verdict set built
# below, so a regression in the aggregation shows up as a mismatch against
# arithmetic rather than against the previous run's output.
#
# Toy set: 3 conditions (A, B, D) x 8 tasks x 3 pairs = 24 verdicts per judge.
#
#   A-vs-B : B wins 7, tie 1        -> B 7.5, A 0.5
#   A-vs-D : D wins 6, A wins 2     -> D 6.0, A 2.0
#   B-vs-D : B wins 5, D wins 3     -> B 5.0, D 3.0
#
#   total wins: B 12.5 > D 9.0 > A 2.5     -> Bradley-Terry order B, D, A
#   sign test (B vs A, primary judge): 7/8 decisive wins -> "B helps"
#
#   word counts A=100 B=200 D=150; decisive pairs 7 + 8 + 8 = 23, of which the
#   longer document won 7 + 6 + 5 = 18.
#
# No model calls, no network. Exit 0 all scenarios pass, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT="$BENCH_DIR/report.sh"
FIXTURES="$SCRIPT_DIR/fixtures/judging"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required"; exit 1; }

TEST_DIR=$(mktemp -d -t bench-report-test-XXXXXX)
COPY_ARTIFACT=""
cleanup() { rm -rf "$TEST_DIR"; [[ -n "$COPY_ARTIFACT" ]] && rm -f "$COPY_ARTIFACT"; }
trap cleanup EXIT

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

TASKS="t1 t2 t3 t4 t5 t6 t7 t8"
declare -A WORDS=([A]=100 [B]=200 [D]=150)

mk_cell() { # batch task cond
  local cell="$1/$2/$3"
  mkdir -p "$cell"
  printf '# Plan\nBody for %s %s.\n' "$2" "$3" > "$cell/final.md"
  jq -n --argjson w "${WORDS[$3]}" \
    '{schema:"bench-cell/1.0", status:"complete", wall_secs:30, word_count:$w,
      convergence_status:"converged", markers_final:0, glm_calls:0,
      kimi_status:"ok", degraded:false,
      tokens:{compose:{input:1000,output:500,total_cost_usd:0.02}}, error:null}' \
    > "$cell/meta.json"
}

mk_verdict() { # batch task judge x y verdict
  local dir="$1/$2/judging/$3"
  mkdir -p "$dir"
  jq -n --arg t "$2" --arg x "$4" --arg y "$5" --arg v "$6" --arg j "$3" \
    --argjson wx "${WORDS[$4]}" --argjson wy "${WORDS[$5]}" \
    '{schema:"bench-pair/1.0", task_id:$t, cond_x:$x, cond_y:$y, verdict:$v,
      confidence_pair:"high", evidence_verified:true, trials:[], evidence:[],
      judge:$j, judge_model:"stub-model", cli_version:"9.9.9",
      prompt_sha256:"0000", judged_at:"2026-08-29T00:00:00Z",
      doc_words:{x:$wx, y:$wy}}' > "$dir/$4__vs__$5.json"
}

# build_batch DEST AB_B_WINS  — B beats A on the first AB_B_WINS tasks, ties on
# the rest; A-vs-D and B-vs-D are fixed.
build_batch() {
  local batch="$1" ab_wins="$2" judge="$3"
  local i=0 task
  for task in $TASKS; do
    i=$((i + 1))
    for cond in A B D; do mk_cell "$batch" "$task" "$cond"; done

    if (( i <= ab_wins )); then mk_verdict "$batch" "$task" "$judge" A B y
    else                        mk_verdict "$batch" "$task" "$judge" A B tie; fi

    # A-vs-D: D wins on tasks 1-6, A wins on 7-8.
    if (( i <= 6 )); then mk_verdict "$batch" "$task" "$judge" A D y
    else                  mk_verdict "$batch" "$task" "$judge" A D x; fi

    # B-vs-D: B wins on tasks 1-5, D wins on 6-8.
    if (( i <= 5 )); then mk_verdict "$batch" "$task" "$judge" B D x
    else                  mk_verdict "$batch" "$task" "$judge" B D y; fi
  done
}

judge_section() { # $1 = report file, $2 = judge
  awk -v j="$2" '
    $0 == "### Judge `" j "`" { on = 1; next }
    on && /^### Judge `/ { on = 0 }
    on && /^## / { on = 0 }
    on { print }
  ' "$1"
}

# --- R1: syntax ---------------------------------------------------------------
TOTAL=$((TOTAL + 1))
if bash -n "$REPORT"; then pass "R1: report.sh parses clean"; else fail "R1: bash -n failed"; fi

# --- R2: 7/8 batch — matrices, BT order, sign test ---------------------------
B7="$TEST_DIR/seven/b1"
build_batch "$B7" 7 fable
build_batch "$B7" 7 codex
# One deliberate cross-judge disagreement: codex calls t1's A-vs-B a tie.
mk_verdict "$B7" t1 codex A B tie
R7="$TEST_DIR/report-seven.md"
out=$(bash "$REPORT" --batch-dir "$B7" --out "$R7" --judges fable,codex \
  --corpus "$FIXTURES/corpus" --no-copy 2>&1); rc=$?

TOTAL=$((TOTAL + 1))
if (( rc == 0 )) && [[ -s "$R7" ]]; then
  pass "R2: report.sh exits 0 and writes a report"
else
  fail "R2: rc=$rc"; printf '%s\n' "$out" | tail -5
fi

TOTAL=$((TOTAL + 1))
judge_section "$R7" fable > "$TEST_DIR/fable-section.md"
matrix_ok=true
for expected in "(0.5/8)" "(2.0/8)" "(7.5/8)" "(5.0/8)" "(6.0/8)" "(3.0/8)"; do
  grep -qF -- "$expected" "$TEST_DIR/fable-section.md" || { matrix_ok=false; echo "  missing cell $expected"; }
done
if [[ "$matrix_ok" == true ]]; then
  pass "R3: win matrix matches the hand calculation (A 0.5/2.0, B 7.5/5.0, D 6.0/3.0)"
else
  fail "R3: win-matrix cells do not match"
fi

TOTAL=$((TOTAL + 1))
bt_order=$(awk -F'|' '/^\| [0-9]+ \| `/ { gsub(/[ `]/, "", $3); printf "%s", $3 }' "$TEST_DIR/fable-section.md")
bt_wins=$(awk -F'|' '/^\| [0-9]+ \| `/ { gsub(/ /, "", $5); printf "%s ", $5 }' "$TEST_DIR/fable-section.md")
if [[ "$bt_order" == "BDA" ]]; then
  pass "R4: Bradley-Terry ranking is B > D > A (total wins: $bt_wins)"
else
  fail "R4: BT order was '$bt_order', expected 'BDA' (wins: $bt_wins)"
fi

TOTAL=$((TOTAL + 1))
if [[ "$bt_wins" == "12.5 9.0 2.5 " ]]; then
  pass "R5: BT total-wins column matches the hand calculation (12.5 / 9.0 / 2.5)"
else
  fail "R5: total wins '$bt_wins', expected '12.5 9.0 2.5 '"
fi

TOTAL=$((TOTAL + 1))
if grep -qF -- '**B helps** — 7/8 decisive wins meets the pre-registered >=7/8 sign-test threshold' "$R7"; then
  pass "R6: sign test at 7/8 reports the pre-registered 'helps' outcome"
else
  fail "R6: 7/8 sign-test line missing; got: $(grep -F 'Primary-judge sign test' "$R7")"
fi

TOTAL=$((TOTAL + 1))
# Both judges scored all 24 pairs; they differ on exactly one (t1 A-vs-B).
# 23/24 exact agreement = 96%; of those 23, the decisive ones are A-B 6
# (t1 disagrees, t8 is a tie both ways), A-D 8, B-D 8 = 22.
if grep -qF 'Of 24 pair(s) scored by all 2 requested judges,' "$R7" \
   && grep -qF '23 agreed exactly (96%), and 22 of those were unanimous' "$R7"; then
  pass "R7: cross-judge agreement counts match the hand calculation (23/24, 22 decisive)"
else
  fail "R7: agreement line wrong: $(grep -F 'agreed exactly' "$R7")"
fi

TOTAL=$((TOTAL + 1))
# Decisive pairs for fable: 7 + 8 + 8 = 23; longer doc won 7 + 6 + 5 = 18.
if grep -qE '^\| `fable` \| 18 \| 23 \| 78% \|$' "$R7"; then
  pass "R8: length-bias row matches the hand calculation (18/23 = 78%)"
else
  fail "R8: length-bias row wrong: $(grep -E '^\| `fable` \| [0-9]+ \| [0-9]+ \|' "$R7")"
fi

TOTAL=$((TOTAL + 1))
words_ok=true
grep -qE '^\| `A` \| 100 \| 8 \|$' "$R7" || words_ok=false
grep -qE '^\| `B` \| 200 \| 8 \|$' "$R7" || words_ok=false
grep -qE '^\| `D` \| 150 \| 8 \|$' "$R7" || words_ok=false
if [[ "$words_ok" == true ]]; then
  pass "R9: per-condition word counts reported (A 100, B 200, D 150 over 8 docs each)"
else
  fail "R9: word-count table wrong"
fi

TOTAL=$((TOTAL + 1))
# 8 tasks x 3 conditions x 0.02 USD = 0.16 per condition.
if grep -qE '^\| `B` \| 8 \| 200 \| 30 \| 8 \| 0 \| 0 \| 0 \| 0\.1600 \|$' "$R7"; then
  pass "R10: process/cost row sums the meta.json token sidecars (8 cells, 0.1600 USD)"
else
  fail "R10: cost row wrong: $(grep -E '^\| `B` \| 8 \|' "$R7")"
fi

TOTAL=$((TOTAL + 1))
if grep -qF 'Unjudged |' "$R7" && grep -qE '^\| `fable` \| 24 \| 24 \| 0 \|$' "$R7"; then
  pass "R11: data-completeness table shows 24/24 pairs judged, 0 unjudged"
else
  fail "R11: completeness row wrong: $(grep -E '^\| `fable` \| 24' "$R7")"
fi

# --- R12: 5/8 batch — the underpowered band ----------------------------------
TOTAL=$((TOTAL + 1))
B5="$TEST_DIR/five/b1"
build_batch "$B5" 5 fable
R5F="$TEST_DIR/report-five.md"
out=$(bash "$REPORT" --batch-dir "$B5" --out "$R5F" --judges fable \
  --corpus "$FIXTURES/corpus" --no-copy 2>&1); rc=$?
if (( rc == 0 )) && grep -qF -- '**Directionally positive, underpowered** — 5/8 decisive wins falls in the pre-registered 5-6/8 band' "$R5F"; then
  pass "R12: sign test at 5/8 reports the pre-registered underpowered band"
else
  fail "R12: rc=$rc; got: $(grep -F 'Primary-judge sign test' "$R5F")"
fi

# --- R13: missing verdicts are surfaced, never papered over -------------------
TOTAL=$((TOTAL + 1))
rm -f "$B5/t3/judging/fable/A__vs__B.json"
R13="$TEST_DIR/report-missing.md"
out=$(bash "$REPORT" --batch-dir "$B5" --out "$R13" --judges fable \
  --corpus "$FIXTURES/corpus" --no-copy 2>&1); rc=$?
if (( rc == 0 )) \
   && grep -qE '^\| `fable` \| 23 \| 24 \| 1 \|$' "$R13" \
   && grep -qF '1 task(s) have no verdict for this pair' "$R13"; then
  pass "R13: a deleted verdict shows as unjudged and raises a sign-test caveat"
else
  fail "R13: rc=$rc; completeness row: $(grep -E '^\| `fable` \| 2[0-9]' "$R13")"
fi

# --- R14: an incomplete generation cell is surfaced ---------------------------
TOTAL=$((TOTAL + 1))
jq '.status = "pending-quota"' "$B5/t4/A/meta.json" > "$B5/t4/A/meta.tmp" \
  && mv -f "$B5/t4/A/meta.tmp" "$B5/t4/A/meta.json"
R14="$TEST_DIR/report-pending.md"
out=$(bash "$REPORT" --batch-dir "$B5" --out "$R14" --judges fable \
  --corpus "$FIXTURES/corpus" --no-copy 2>&1); rc=$?
if (( rc == 0 )) && grep -qF 'Generation cells not complete (1)' "$R14" \
   && grep -qF '`t4/A: pending-quota`' "$R14"; then
  pass "R14: an incomplete generation cell is named in the data-completeness block"
else
  fail "R14: rc=$rc; completeness block:"; sed -n '/## 0/,/## 1/p' "$R14" | head -12
fi

# --- R15: the committed copy lands in benchmarks/reports/ --------------------
TOTAL=$((TOTAL + 1))
COPY_SRC="$TEST_DIR/copy/bench-report-selftest"
build_batch "$COPY_SRC" 7 fable
COPY_ARTIFACT="$BENCH_DIR/reports/bench-report-selftest.md"
out=$(bash "$REPORT" --batch-dir "$COPY_SRC" --judges fable --corpus "$FIXTURES/corpus" 2>&1); rc=$?
if (( rc == 0 )) && [[ -s "$COPY_ARTIFACT" ]] && [[ -s "$COPY_SRC/REPORT.md" ]]; then
  pass "R15: default output is <batch>/REPORT.md with a copy in benchmarks/reports/"
else
  fail "R15: rc=$rc copy=$([[ -f "$COPY_ARTIFACT" ]] && echo yes || echo no)"
fi

# --- R16: no verdicts at all is a hard error, not an empty report ------------
TOTAL=$((TOTAL + 1))
EMPTY="$TEST_DIR/empty/b1"
mk_cell "$EMPTY" t1 A
out=$(bash "$REPORT" --batch-dir "$EMPTY" --out "$TEST_DIR/never.md" --judges fable --no-copy 2>&1); rc=$?
if (( rc == 1 )) && printf '%s' "$out" | grep -q 'no bench-pair/1.0 verdict files'; then
  pass "R16: a batch with no verdicts errors instead of emitting an empty report"
else
  fail "R16: rc=$rc; out: $out"
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
