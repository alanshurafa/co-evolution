#!/usr/bin/env bash

# benchmarks/tests/test-judging.sh — contract tests for benchmarks/judge-matrix.sh.
#
# Fully stubbed: every judge CLI and the direct Z.AI HTTP call is PATH-shadowed
# by a shell script with canned verdicts (the judge-lib extraction pattern), so
# this suite
# makes no live model calls and costs $0. No live-model assertions exist here by
# design — a judging harness that can only be verified by spending money is a
# harness nobody re-verifies.
#
# Exit 0 all scenarios pass, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures/judging"
JUDGE_MATRIX="$BENCH_DIR/judge-matrix.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required"; exit 1; }

TEST_DIR=$(mktemp -d -t bench-judging-XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

# --- Stub judge CLIs ----------------------------------------------------------
# Every stub logs one line per invocation to $STUB_LOG so "was this pair ever
# sent to a judge?" and "did the resume path re-spend?" are directly assertable.

mk_claude_stub() { # $1 = dir, $2 = behavior (honest|biased|liar|authfail)
  mkdir -p "$1"
  cat > "$1/claude" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == "--version" ]] && { echo "9.9.9 (stub claude)"; exit 0; }; done
input=\$(cat)
[[ -n "\${STUB_LOG:-}" ]] && printf 'claude %s\n' "$2" >> "\$STUB_LOG"
behavior="$2"
if [[ "\$behavior" == "authfail" ]]; then
  echo "Not logged in · Please run /login"
  exit 0
fi
a_part=\$(printf '%s' "\$input" | awk '/^## Plan A\$/{f=1;next} /^## Plan B\$/{f=0} f')
b_part=\$(printf '%s' "\$input" | awk '/^## Plan B\$/{f=1;next} f')
if [[ "\$behavior" == "biased" ]]; then
  printf '{"better":"A","confidence":"high","reasons":["the first plan reads better"],"evidence":[]}\n'
  exit 0
fi
if printf '%s' "\$a_part" | grep -q 'staged rollout behind a feature flag'; then
  winner=A; doc="\$a_part"
else
  winner=B; doc="\$b_part"
fi
if [[ "\$behavior" == "liar" ]]; then
  quote="this exact sentence appears nowhere in either plan at all"
else
  quote=\$(printf '%s' "\$doc" | grep -v '^#' | grep -v '^\$' | head -1 | cut -c1-60)
fi
printf '{"better":"%s","confidence":"high","reasons":["it is more actionable"],"evidence":[{"doc":"%s","quote":"%s"}]}\n' "\$winner" "\$winner" "\$quote"
STUB
  chmod +x "$1/claude"
}

mk_codex_stub() { # $1 = dir, $2 = model the CLI claims in its preamble
  mkdir -p "$1"
  cat > "$1/codex" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == "--version" ]] && { echo "codex-cli 9.9.9 (stub)"; exit 0; }; done
out=""
prev=""
for a in "\$@"; do
  [[ "\$prev" == "-o" ]] && out="\$a"
  prev="\$a"
done
input=\$(cat)
[[ -n "\${STUB_LOG:-}" ]] && printf 'codex\n' >> "\$STUB_LOG"
# codex exec announces its session config on stderr; that preamble is what the
# preflight model assertion reads.
printf 'workdir: .\nmodel: %s\napproval: never\n' "$2" >&2
if printf '%s' "\$input" | grep -q 'Preflight check'; then
  [[ -n "\$out" ]] && printf '{"model":"%s","ok":true}\n' "$2" > "\$out"
  exit 0
fi
a_part=\$(printf '%s' "\$input" | awk '/^## Plan A\$/{f=1;next} /^## Plan B\$/{f=0} f')
b_part=\$(printf '%s' "\$input" | awk '/^## Plan B\$/{f=1;next} f')
if printf '%s' "\$a_part" | grep -q 'staged rollout behind a feature flag'; then
  winner=A; doc="\$a_part"
else
  winner=B; doc="\$b_part"
fi
quote=\$(printf '%s' "\$doc" | grep -v '^#' | grep -v '^\$' | head -1 | cut -c1-60)
[[ -n "\$out" ]] && printf '{"better":"%s","confidence":"medium","reasons":["clearer cutover"],"evidence":[{"doc":"%s","quote":"%s"}]}\n' "\$winner" "\$winner" "\$quote" > "\$out"
exit 0
STUB
  chmod +x "$1/codex"
}

mk_curl_stub() { # $1 = dir, $2 = behavior (honest|biased|liar|authfail)
  mkdir -p "$1"
  cat > "$1/curl" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == "--version" ]] && { echo "curl 9.9.9 (stub)"; exit 0; }; done
request=\$(cat)
input=\$(printf '%s' "\$request" | jq -r '.messages[0].content // ""')
[[ -n "\${STUB_LOG:-}" ]] && printf 'glm %s\n' "$2" >> "\$STUB_LOG"
behavior="$2"
if [[ "\$behavior" == "authfail" ]]; then
  printf '{"error":{"message":"Invalid Authentication"}}\n'
  exit 22
fi
a_part=\$(printf '%s' "\$input" | awk '/^## Plan A\$/{f=1;next} /^## Plan B\$/{f=0} f')
b_part=\$(printf '%s' "\$input" | awk '/^## Plan B\$/{f=1;next} f')
if [[ "\$behavior" == "biased" ]]; then
  verdict='{"better":"A","confidence":"high","reasons":["the first plan reads better"],"evidence":[]}'
else
  if printf '%s' "\$a_part" | grep -q 'staged rollout behind a feature flag'; then winner=A; doc="\$a_part"; else winner=B; doc="\$b_part"; fi
  if [[ "\$behavior" == "liar" ]]; then quote='this exact sentence appears nowhere in either plan at all'; else quote=\$(printf '%s' "\$doc" | grep -v '^#' | grep -v '^\$' | head -1 | cut -c1-60); fi
  verdict=\$(jq -nc --arg w "\$winner" --arg q "\$quote" '{better:\$w,confidence:"high",reasons:["it is more actionable"],evidence:[{doc:\$w,quote:\$q}]}')
fi
jq -nc --arg c "\$verdict" '{choices:[{message:{content:\$c}}],usage:{prompt_tokens:11,completion_tokens:22}}'
STUB
  chmod +x "$1/curl"
}

BIN_HONEST="$TEST_DIR/bin-honest"
BIN_BIASED="$TEST_DIR/bin-biased"
BIN_LIAR="$TEST_DIR/bin-liar"
BIN_AUTHFAIL="$TEST_DIR/bin-authfail"
mk_claude_stub "$BIN_HONEST" honest
mk_claude_stub "$BIN_BIASED" biased
mk_claude_stub "$BIN_LIAR" liar
mk_claude_stub "$BIN_AUTHFAIL" authfail
mk_codex_stub "$BIN_HONEST" "gpt-5.5"
mk_codex_stub "$TEST_DIR/bin-badmodel" "gpt-4o-mini"
mk_claude_stub "$TEST_DIR/bin-badmodel" honest
mk_curl_stub "$BIN_HONEST" honest
mk_curl_stub "$BIN_BIASED" biased
mk_curl_stub "$BIN_LIAR" liar
mk_curl_stub "$BIN_AUTHFAIL" authfail
mk_curl_stub "$TEST_DIR/bin-badmodel" honest

# --- Fixture batches ----------------------------------------------------------
# cond→document mapping: A weak, B strong (the honest stub's winner), D neutral,
# L leaky (a document that survives sanitization still naming a vendor).

doc_for() {
  case "$1" in
    A) printf '%s' "$FIXTURES/docs/plan-weak.md" ;;
    B) printf '%s' "$FIXTURES/docs/plan-strong.md" ;;
    D) printf '%s' "$FIXTURES/docs/plan-neutral.md" ;;
    L) printf '%s' "$FIXTURES/docs/plan-leaky.md" ;;
  esac
}

write_meta() { # $1 = cell dir, $2 = status, $3 = degraded (true|false)
  local words; words=$(wc -w < "$1/final.md" | tr -d '[:space:]')
  jq -n --arg s "$2" --argjson d "$3" --argjson w "${words:-0}" \
    '{schema:"bench-cell/1.0", status:$s, wall_secs:42, word_count:$w,
      convergence_status:"converged", markers_final:0, glm_calls:0,
      kimi_status:"ok", degraded:$d,
      tokens:{compose:{input:1200,output:800,total_cost_usd:0.0125}}, error:null}' \
    > "$1/meta.json"
}

# make_batch NAME TASKS_CSV CONDS_CSV → prints the batch dir
make_batch() {
  local name="$1" tasks="$2" conds="$3"
  local batch="$TEST_DIR/$name/b1"
  local task cond cell
  for task in ${tasks//,/ }; do
    for cond in ${conds//,/ }; do
      cell="$batch/$task/$cond"
      mkdir -p "$cell"
      cp "$(doc_for "$cond")" "$cell/final.md"
      write_meta "$cell" complete false
    done
  done
  printf '%s' "$batch"
}

run_matrix() { # $1 = stub bin dir, rest = judge-matrix args; prints combined output
  local bin="$1"; shift
  env PATH="$bin:$PATH" STUB_LOG="${STUB_LOG:-$TEST_DIR/stub.log}" ZAI_API_KEY=stub-key \
    bash "$JUDGE_MATRIX" "$@" 2>&1
}

stub_calls() { [[ -f "$1" ]] && wc -l < "$1" | tr -d '[:space:]' || printf '0'; }

# --- S1: syntax ---------------------------------------------------------------
TOTAL=$((TOTAL + 1))
if bash -n "$JUDGE_MATRIX" && bash -n "$BENCH_DIR/report.sh"; then
  pass "S1: judge-matrix.sh and report.sh parse clean"
else
  fail "S1: bash -n failed"
fi

# --- S2: honest judge, agreement in both orders -> a winner -------------------
TOTAL=$((TOTAL + 1))
B2=$(make_batch s2 t1 A,B)
STUB_LOG="$TEST_DIR/s2.log"
out=$(STUB_LOG="$TEST_DIR/s2.log" run_matrix "$BIN_HONEST" --batch-dir "$B2" \
  --conditions A,B --judges fable --corpus "$FIXTURES/corpus"); rc=$?
V2="$B2/t1/judging/fable/A__vs__B.json"
if (( rc == 0 )) && [[ -f "$V2" ]] && jq -e '
      .schema == "bench-pair/1.0" and .verdict == "y" and .cond_x == "A" and
      .cond_y == "B" and .evidence_verified == true and (.trials | length) == 2 and
      (.judge_model | length) > 0 and (.cli_version | length) > 0 and
      (.prompt_sha256 | length) == 64 and .doc_words.y > .doc_words.x' "$V2" >/dev/null 2>&1; then
  pass "S2: winner in both orders -> verdict y (B), evidence verified, provenance recorded"
else
  fail "S2: rc=$rc verdict=$(jq -c '{verdict,evidence_verified,judge_model,prompt_sha256}' "$V2" 2>/dev/null)"
  printf '%s\n' "$out" | tail -5
fi

# --- S3: idempotency — a second run judges nothing ----------------------------
TOTAL=$((TOTAL + 1))
before=$(stub_calls "$TEST_DIR/s2.log")
out=$(STUB_LOG="$TEST_DIR/s2.log" run_matrix "$BIN_HONEST" --batch-dir "$B2" \
  --conditions A,B --judges fable --corpus "$FIXTURES/corpus"); rc=$?
after=$(stub_calls "$TEST_DIR/s2.log")
if (( rc == 0 )) && [[ "$before" == "$after" ]] && printf '%s' "$out" | grep -q 'already present, skipping'; then
  pass "S3: rerun is idempotent — 0 new judge calls ($before -> $after)"
else
  fail "S3: rc=$rc calls $before -> $after"
fi

# --- S4: order-swap disagreement -> position_biased ---------------------------
TOTAL=$((TOTAL + 1))
B4=$(make_batch s4 t1 A,B)
out=$(STUB_LOG="$TEST_DIR/s4.log" run_matrix "$BIN_BIASED" --batch-dir "$B4" \
  --conditions A,B --judges fable --corpus "$FIXTURES/corpus"); rc=$?
V4="$B4/t1/judging/fable/A__vs__B.json"
if (( rc == 0 )) && jq -e '.verdict == "position_biased"' "$V4" >/dev/null 2>&1; then
  pass "S4: a judge that always answers A -> position_biased"
else
  fail "S4: rc=$rc verdict=$(jq -r '.verdict' "$V4" 2>/dev/null)"
fi

# --- S5: fabricated evidence -> invalid-evidence ------------------------------
TOTAL=$((TOTAL + 1))
B5=$(make_batch s5 t1 A,B)
out=$(STUB_LOG="$TEST_DIR/s5.log" run_matrix "$BIN_LIAR" --batch-dir "$B5" \
  --conditions A,B --judges fable --corpus "$FIXTURES/corpus"); rc=$?
V5="$B5/t1/judging/fable/A__vs__B.json"
if (( rc == 0 )) && jq -e '.verdict == "invalid-evidence" and .evidence_verified == false' "$V5" >/dev/null 2>&1; then
  pass "S5: fabricated quotes -> invalid-evidence"
else
  fail "S5: rc=$rc verdict=$(jq -c '{verdict,evidence_verified}' "$V5" 2>/dev/null)"
fi

# --- S6: leaky document -> sanitize-leak on every pair, never judged ----------
TOTAL=$((TOTAL + 1))
B6=$(make_batch s6 t1 A,B,L)
out=$(STUB_LOG="$TEST_DIR/s6.log" run_matrix "$BIN_HONEST" --batch-dir "$B6" \
  --conditions A,B,L --judges fable --corpus "$FIXTURES/corpus"); rc=$?
JD6="$B6/t1/judging/fable"
leak_ok=true
for p in "A__vs__L" "B__vs__L"; do
  jq -e '.verdict == "sanitize-leak" and (.trials | length) == 0 and .leaked_conditions == "L"' \
    "$JD6/$p.json" >/dev/null 2>&1 || leak_ok=false
done
jq -e '.verdict == "y"' "$JD6/A__vs__B.json" >/dev/null 2>&1 || leak_ok=false
jq -e '.excluded | any(.condition == "L" and .reason == "sanitize-leak")' \
  "$B6/t1/judging/excluded.json" >/dev/null 2>&1 || leak_ok=false
calls6=$(stub_calls "$TEST_DIR/s6.log")
# Only the clean A-vs-B pair may reach the judge: 2 position-swapped trials.
if (( rc == 0 )) && [[ "$leak_ok" == true ]] && [[ "$calls6" == "2" ]]; then
  pass "S6: leaky condition -> sanitize-leak verdicts on both its pairs, never judged (2 calls)"
else
  fail "S6: rc=$rc leak_ok=$leak_ok judge_calls=$calls6 (expected 2)"
  ls "$JD6" 2>/dev/null
fi

# --- S7: leak_check runs through sanitize.sh, not grep -iF --------------------
TOTAL=$((TOTAL + 1))
if grep -nE '^[^#]*grep +-[a-zA-Z]*iF' "$JUDGE_MATRIX" >/dev/null 2>&1; then
  fail "S7: judge-matrix.sh uses 'grep -iF' — GNU grep 3.0 SIGABRTs on multi-word -iF patterns"
else
  pass "S7: no 'grep -iF' in judge-matrix.sh; banned-token checks go through leak_check"
fi

# --- S8: generation gate refuses a pending-quota cell -------------------------
TOTAL=$((TOTAL + 1))
B8=$(make_batch s8 t1 A,B)
write_meta "$B8/t1/B" pending-quota false
out=$(STUB_LOG="$TEST_DIR/s8.log" run_matrix "$BIN_HONEST" --batch-dir "$B8" \
  --conditions A,B --judges fable --corpus "$FIXTURES/corpus"); rc=$?
if (( rc == 1 )) && printf '%s' "$out" | grep -q 't1/B: status=pending-quota' \
   && [[ ! -d "$B8/t1/judging/fable" ]]; then
  pass "S8: a pending-quota cell aborts judging (exit 1) and names the offending cell"
else
  fail "S8: rc=$rc (expected 1); output tail:"
  printf '%s\n' "$out" | tail -5
fi

# --- S9: absent cell also aborts the gate -------------------------------------
TOTAL=$((TOTAL + 1))
B9=$(make_batch s9 t1 A,B)
out=$(STUB_LOG="$TEST_DIR/s9.log" run_matrix "$BIN_HONEST" --batch-dir "$B9" \
  --conditions A,B,D --judges fable --corpus "$FIXTURES/corpus"); rc=$?
if (( rc == 1 )) && printf '%s' "$out" | grep -q 't1/D: status=absent'; then
  pass "S9: a condition with no cell aborts the gate as absent"
else
  fail "S9: rc=$rc; output tail:"; printf '%s\n' "$out" | tail -5
fi

# --- S10: preflight aborts when the codex CLI reports a different model -------
TOTAL=$((TOTAL + 1))
B10=$(make_batch s10 t1 A,B)
out=$(STUB_LOG="$TEST_DIR/s10.log" run_matrix "$TEST_DIR/bin-badmodel" --batch-dir "$B10" \
  --conditions A,B --judges codex --corpus "$FIXTURES/corpus"); rc=$?
if (( rc == 1 )) && printf '%s' "$out" | grep -q "the CLI reports 'gpt-4o-mini'" \
   && [[ ! -f "$B10/t1/judging/codex/A__vs__B.json" ]]; then
  pass "S10: preflight model mismatch aborts before the first verdict"
else
  fail "S10: rc=$rc; output tail:"; printf '%s\n' "$out" | tail -5
fi

# --- S11: three judges, all three verdict files, codex model verified ---------
TOTAL=$((TOTAL + 1))
B11=$(make_batch s11 t1 A,B)
out=$(STUB_LOG="$TEST_DIR/s11.log" run_matrix "$BIN_HONEST" --batch-dir "$B11" \
  --conditions A,B --judges glm,fable,codex --corpus "$FIXTURES/corpus"); rc=$?
three_ok=true
for j in fable codex glm; do
  jq -e '.schema == "bench-pair/1.0" and .verdict == "y" and .judge == "'"$j"'"' \
    "$B11/t1/judging/$j/A__vs__B.json" >/dev/null 2>&1 || three_ok=false
done
jq -e '.judges | any(.judge == "codex" and .model_assert == "verified")' \
  "$B11/judging/preflight.json" >/dev/null 2>&1 || three_ok=false
jq -e '.judges | any(.judge == "fable" and .model == "claude-fable-5" and .model_assert == "configured-only")' \
  "$B11/judging/preflight.json" >/dev/null 2>&1 || three_ok=false
if (( rc == 0 )) && [[ "$three_ok" == true ]]; then
  pass "S11: fable+codex+glm each produce a verdict; preflight records model provenance"
else
  fail "S11: rc=$rc three_ok=$three_ok"
  printf '%s\n' "$out" | tail -8
fi

# --- S12: a judge-CLI failure leaves the pair unjudged and exits 75 -----------
TOTAL=$((TOTAL + 1))
B12=$(make_batch s12 t1 A,B)
out=$(STUB_LOG="$TEST_DIR/s12.log" run_matrix "$BIN_AUTHFAIL" --batch-dir "$B12" \
  --conditions A,B --judges fable --corpus "$FIXTURES/corpus"); rc=$?
if (( rc == 75 )) && [[ ! -f "$B12/t1/judging/fable/A__vs__B.json" ]] \
   && printf '%s' "$out" | grep -q 'not authenticated'; then
  pass "S12: judge auth failure records nothing and exits 75 (retryable)"
else
  fail "S12: rc=$rc (expected 75); verdict file present=$([[ -f "$B12/t1/judging/fable/A__vs__B.json" ]] && echo yes || echo no)"
  printf '%s\n' "$out" | tail -5
fi

# --- S13: a degraded cell is excluded from pairing and recorded ---------------
TOTAL=$((TOTAL + 1))
B13=$(make_batch s13 t1 A,B,D)
write_meta "$B13/t1/D" complete true
out=$(STUB_LOG="$TEST_DIR/s13.log" run_matrix "$BIN_HONEST" --batch-dir "$B13" \
  --conditions A,B,D --judges fable --corpus "$FIXTURES/corpus"); rc=$?
deg_ok=true
[[ -f "$B13/t1/judging/fable/A__vs__D.json" ]] && deg_ok=false
[[ -f "$B13/t1/judging/fable/B__vs__D.json" ]] && deg_ok=false
[[ -f "$B13/t1/judging/fable/A__vs__B.json" ]] || deg_ok=false
jq -e '.excluded | any(.condition == "D" and .reason == "degraded")' \
  "$B13/t1/judging/excluded.json" >/dev/null 2>&1 || deg_ok=false
if (( rc == 0 )) && [[ "$deg_ok" == true ]]; then
  pass "S13: a degraded cell is excluded from every pair and recorded in excluded.json"
else
  fail "S13: rc=$rc deg_ok=$deg_ok"; printf '%s\n' "$out" | tail -5
fi

# --- S14: sanitization actually blinds the document the judge sees ------------
TOTAL=$((TOTAL + 1))
SAN="$B6/t1/judging/sanitized/A.md"
if [[ -f "$SAN" ]] && [[ "$(head -1 "$SAN")" == "# Plan" ]] \
   && ! grep -q 'Ledger Migration Notes' "$SAN"; then
  pass "S14: the judged copy is sanitized (H1 normalized, original title gone)"
else
  fail "S14: sanitized doc unexpected: $(head -1 "$SAN" 2>/dev/null)"
fi

# --- S15: an unresolvable judge model is a hard configuration error ----------
TOTAL=$((TOTAL + 1))
B15=$(make_batch s15 t1 A,B)
out=$(env PATH="$BIN_HONEST:$PATH" STUB_LOG="$TEST_DIR/s15.log" ZAI_API_KEY=stub-key \
  BENCH_JUDGE_FABLE_MODEL="(inherit:fable)" \
  bash "$JUDGE_MATRIX" --batch-dir "$B15" --conditions A,B --judges fable \
  --corpus "$FIXTURES/corpus" 2>&1); rc=$?
if (( rc == 1 )) && printf '%s' "$out" | grep -q 'alias or inherit marker'; then
  pass "S15: an inherit/alias judge model aborts before any verdict"
else
  fail "S15: rc=$rc; output tail:"; printf '%s\n' "$out" | tail -3
fi

# ---------------------------------------------------------------------------
printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
