#!/usr/bin/env bash
# benchmarks/tests/test-panel.sh
# Contract tests for benchmarks/run-panel.sh (benchmark condition C).
#
# Hermetic: every agent CLI and direct-provider HTTP call is PATH-shadowed by a
# stub (the evals/tests/fake-runner pattern). No live model calls, no network,
# no cost. The stubs record each
# invocation to $STUB_LOG and their prompt to $STUB_STDIN_DIR so the tests can
# assert BOTH what ran and what it was asked.
#
# Covered: full run + panel-state schema, resume-after-kill (only synthesis
# re-invokes), the Kimi size gate, vendor blindness of the synthesis prompt,
# reviewer subsetting/order, all-critiques-fail (exit 1), compose auth (exit 4).
#
# Exit 0 when every scenario passes, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_PANEL="$BENCH_DIR/run-panel.sh"
FIXTURES="$SCRIPT_DIR/fixtures/panel"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required"; exit 1; }
[[ -f "$RUN_PANEL" ]] || { echo "SKIP-FAIL: $RUN_PANEL not found"; exit 1; }

TEST_DIR=$(mktemp -d -t panel-test-XXXXXX) || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf -- "$TEST_DIR"' EXIT

TOTAL=0
FAILED=0
pass() { TOTAL=$((TOTAL + 1)); printf 'PASS: %s\n' "$1"; }
fail() { TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1"; }

check_eq() { # NAME EXPECTED ACTUAL
  if [[ "$2" == "$3" ]]; then pass "$1"; else
    fail "$1"; printf '  expected: %s\n  actual:   %s\n' "$2" "$3"
  fi
}
check_file() { # NAME PATH
  if [[ -s "$2" ]]; then pass "$1"; else fail "$1 (missing or empty: $2)"; fi
}
check_nofile() { # NAME PATH
  if [[ ! -e "$2" ]]; then pass "$1"; else fail "$1 (should not exist: $2)"; fi
}
check_grep() { # NAME FILE PATTERN
  if grep -qE -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1 (no /$3/ in $2)"; fi
}
check_nogrep() { # NAME FILE PATTERN
  if grep -qiE -- "$3" "$2" 2>/dev/null; then
    fail "$1 (found /$3/ in $2)"
    grep -inE -- "$3" "$2" | head -3 | sed 's/^/    /'
  else pass "$1"; fi
}

# --- Stub CLIs ---------------------------------------------------------------
# Each stub appends a seat name to $STUB_LOG and dumps its prompt to
# $STUB_STDIN_DIR/<seat>.txt. Behaviour is switched by STUB_*_MODE so one stub
# set serves every scenario.

STUB_BIN="$TEST_DIR/bin"
mkdir -p "$STUB_BIN"

# claude: serves compose and synthesis. Direct GLM/Kimi calls use the curl stub
# below, so compose vs synthesis is identified only from the prompt.
cat > "$STUB_BIN/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
model=""; fmt="text"; prev=""
for a in "$@"; do
  case "$prev" in
    --model) model="$a" ;;
    --output-format) fmt="$a" ;;
  esac
  prev="$a"
done
input=$(cat)

if [[ "$input" == *"## YOUR DRAFT PLAN"* ]]; then
  seat="synthesis"
else
  seat="compose"
fi
printf '%s\n' "$seat" >> "$STUB_LOG"
printf '%s' "$input" > "$STUB_STDIN_DIR/$seat.txt"
printf '%s\n' "$model" > "$STUB_STDIN_DIR/$seat.model"

emit() { # RESULT
  # --rawfile, not --arg: the big-plan mode's result is larger than the Windows
  # argv ceiling and jq would die with "Argument list too long".
  local tmpf
  tmpf=$(mktemp) || exit 1
  printf '%s' "$1" > "$tmpf"
  if [[ "$fmt" == "json" ]]; then
    jq -n --rawfile r "$tmpf" '{result: $r, usage: {input_tokens: 11, output_tokens: 22}, total_cost_usd: 0.01}'
  else
    cat "$tmpf"
  fi
  rm -f "$tmpf"
}

case "$seat" in
  compose)
    if [[ "${STUB_CLAUDE_MODE:-normal}" == "auth-fail" ]]; then
      emit "Not logged in · Please run /login"
      exit 0
    fi
    if [[ "${STUB_CLAUDE_MODE:-normal}" == "big-plan" ]]; then
      # ~15 KB of plan: enough to push the assembled Kimi prompt past 11500.
      emit "# Draft Plan $(yes 'spoilage window handoff coordinator' | head -400 | tr '\n' ' ')"
      exit 0
    fi
    emit "# Draft Plan"$'\n\n'"Stage one covers routing. Stage two covers volunteers. Stage three covers measurement."
    ;;
  synthesis)
    if [[ "${STUB_CLAUDE_MODE:-normal}" == "synth-auth-fail" ]]; then
      emit "Not logged in · Please run /login"
      exit 0
    fi
    emit "# Plan"$'\n\n'"Revised: routing, volunteers, cold chain, measurement, phased rollout."
    ;;
esac
STUB

cat > "$STUB_BIN/codex" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
out=""; prev=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out="$a"
  prev="$a"
done
input=$(cat)
printf '%s\n' "codex" >> "$STUB_LOG"
printf '%s' "$input" > "$STUB_STDIN_DIR/codex.txt"
# The real codex CLI reports usage on stderr; run-panel.sh mines this line for
# the tokens block because codex writes no usage sidecar.
printf 'tokens used\n1,234\n' >&2
[[ -n "$out" ]] || exit 0
if [[ "${STUB_CODEX_MODE:-normal}" == "empty" ]]; then
  : > "$out"
  exit 0
fi
printf '%s\n' "1. **Claim** ALPHA-CRITIQUE-TOKEN: cold-chain limits are asserted, not measured. 2. **Claim** no owner is named for the spreadsheet cutover." > "$out"
STUB

# curl: serves the direct GLM and Kimi Chat Completions adapters. The request
# body identifies the model and contains the prompt; the config remains opaque.
cat > "$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
for a in "$@"; do
  [[ "$a" == "--version" ]] && { printf 'curl 9.9.9 (stub)\n'; exit 0; }
done
request=$(cat)
model=$(printf '%s' "$request" | jq -r '.model // ""')
prompt=$(printf '%s' "$request" | jq -r '.messages[0].content // ""')
if [[ "$model" == *glm* ]]; then seat=glm; mode="${STUB_GLM_MODE:-normal}"; else seat=kimi; mode="${STUB_KIMI_MODE:-normal}"; fi
printf '%s\n' "$seat" >> "$STUB_LOG"
printf '%s' "$prompt" > "$STUB_STDIN_DIR/$seat.txt"
if [[ "$mode" == "empty" ]]; then
  content=x
elif [[ "$seat" == "glm" ]]; then
  content='1. **Claim** BETA-CRITIQUE-TOKEN: the cancellation path is undefined. 2. **Claim** the rollout has no exit criteria.'
else
  content='1. **Claim** GAMMA-CRITIQUE-TOKEN: volunteer confirmation has no deadline. 2. **Claim** spoilage is not baselined before the change.'
fi
jq -nc --arg c "$content" '{choices:[{message:{content:$c}}],usage:{prompt_tokens:11,completion_tokens:22,prompt_tokens_details:{cached_tokens:0}}}'
STUB

chmod +x "$STUB_BIN/claude" "$STUB_BIN/codex" "$STUB_BIN/curl"

# --- Harness -----------------------------------------------------------------

SCENARIO=""
STUB_LOG=""
STUB_STDIN_DIR=""
OUT=""

scenario() { # NAME
  SCENARIO="$1"
  STUB_LOG="$TEST_DIR/$SCENARIO.log"
  STUB_STDIN_DIR="$TEST_DIR/$SCENARIO.stdin"
  OUT="$TEST_DIR/$SCENARIO.out"
  mkdir -p "$STUB_STDIN_DIR" "$OUT"
  : > "$STUB_LOG"
  printf '\n--- %s ---\n' "$SCENARIO"
}

run_panel() { # extra args...
  PATH="$STUB_BIN:$PATH" \
  STUB_LOG="$STUB_LOG" \
  STUB_STDIN_DIR="$STUB_STDIN_DIR" \
  ZAI_API_KEY="test-key-not-real" \
  KIMI_API_KEY="test-key-not-real" \
  bash "$RUN_PANEL" --out-dir "$OUT" "$@" > "$TEST_DIR/$SCENARIO.stdout" 2>&1
}

seat_count() { # SEAT
  local n
  n=$(grep -c "^$1\$" "$STUB_LOG" 2>/dev/null) || n=0
  printf '%s' "$n"
}

phase_field() { # PHASE FIELD
  jq -r --arg p "$1" --arg f "$2" \
    '(.phases[] | select(.phase == $p) | .[$f]) // "MISSING"' "$OUT/panel-state.json" 2>/dev/null
}

# --- 1. Full run -------------------------------------------------------------

scenario full
rc=0
run_panel --task-file "$FIXTURES/task-basic.md" || rc=$?
check_eq "full: exit 0" "0" "$rc"
check_file "full: compose-output.md" "$OUT/compose-output.md"
check_file "full: critique-codex.md" "$OUT/critique-codex.md"
check_file "full: critique-glm.md" "$OUT/critique-glm.md"
check_file "full: critique-kimi.md" "$OUT/critique-kimi.md"
check_file "full: final.md" "$OUT/final.md"
check_file "full: panel-state.json" "$OUT/panel-state.json"
check_nofile "full: no kimi skip marker" "$OUT/critique-kimi.SKIPPED"

check_eq "full: state schema" "bench-panel/1.0" "$(jq -r '.schema' "$OUT/panel-state.json")"
check_eq "full: state status" "complete" "$(jq -r '.status' "$OUT/panel-state.json")"
check_eq "full: not degraded" "false" "$(jq -r '.degraded' "$OUT/panel-state.json")"
check_eq "full: five phases" "5" "$(jq -r '.phases | length' "$OUT/panel-state.json")"
check_eq "full: all phases complete" "true" \
  "$(jq -r '[.phases[].status] | all(. == "complete")' "$OUT/panel-state.json")"
check_eq "full: every phase has both timestamps" "true" \
  "$(jq -r '[.phases[] | (.started_at | length > 0) and (.finished_at | length > 0)] | all' "$OUT/panel-state.json")"
check_eq "full: every phase records bytes in and out" "true" \
  "$(jq -r '[.phases[] | (.bytes_in > 0) and (.bytes_out > 0)] | all' "$OUT/panel-state.json")"
check_eq "full: compose model resolved from the fable alias" "claude-fable-5" \
  "$(phase_field compose model)"
check_eq "full: glm seat model recorded" "glm-5.3-flash" "$(phase_field critique-glm model)"
check_eq "full: composer seat model in state" "claude-fable-5" \
  "$(jq -r '.composer_model' "$OUT/panel-state.json")"
check_eq "full: reviewer order preserved" "codex glm kimi" \
  "$(jq -r '.reviewers | join(" ")' "$OUT/panel-state.json")"

# Fields run-benchmark.sh reads straight out of panel-state.json.
check_eq "full: kimi_status ok" "ok" "$(jq -r '.kimi_status' "$OUT/panel-state.json")"
check_eq "full: codex tokens mined from stderr" "1234" \
  "$(jq -r '.tokens.totals.codex_total_tokens' "$OUT/panel-state.json")"
check_eq "full: two Claude usage sidecars folded in" "2" \
  "$(jq -r '[.tokens.phases[] | select(.source == "claude-json")] | length' "$OUT/panel-state.json")"
check_eq "full: direct provider usage sidecars folded in" "2" \
  "$(jq -r '[.tokens.phases[] | select(.source == "zai-chat-completions" or .source == "kimi-chat-completions")] | length' "$OUT/panel-state.json")"
check_eq "full: claude cost summed across composer calls" "true" \
  "$(jq -r '.tokens.totals.claude_cost_usd > 0.01' "$OUT/panel-state.json")"
check_eq "full: claude input tokens summed" "22" \
  "$(jq -r '.tokens.totals.claude_input' "$OUT/panel-state.json")"

check_eq "full: compose invoked once" "1" "$(seat_count compose)"
check_eq "full: codex invoked once" "1" "$(seat_count codex)"
check_eq "full: glm invoked once" "1" "$(seat_count glm)"
check_eq "full: kimi invoked once" "1" "$(seat_count kimi)"
check_eq "full: synthesis invoked once" "1" "$(seat_count synthesis)"

# Compose-prompt parity with conditions A, B and D: the bouncer's string-input
# compose prompt over the frontmatter-stripped, blank-trimmed body. The
# reference below is built independently (write_cell_input's transform plus
# bench_compose_prompt) and compared byte-for-byte — a leading blank line or a
# stray newline here is a confound in the primary comparison, not cosmetics.
cat > "$TEST_DIR/ref-compose-prompt.sh" <<'REF'
#!/usr/bin/env bash
set -euo pipefail
source "$1/lib/benchmark-lib.sh"
body=$(_bench_body "$2" | awk 'NF { blank = 0; if (!seen) seen = 1 } !NF { if (!seen) next; blank++; next } seen { while (blank-- > 0) print ""; print }')
bench_compose_prompt "$body"
REF
if bash "$TEST_DIR/ref-compose-prompt.sh" "$BENCH_DIR" "$FIXTURES/task-basic.md" \
     > "$TEST_DIR/ref-compose-prompt.md" 2>"$TEST_DIR/ref-compose-prompt.err" \
   && cmp -s "$TEST_DIR/ref-compose-prompt.md" "$OUT/compose-prompt.md"; then
  pass "full: compose prompt is byte-identical to conditions A/B/D"
else
  fail "full: compose prompt is byte-identical to conditions A/B/D"
  diff <(od -c "$TEST_DIR/ref-compose-prompt.md") <(od -c "$OUT/compose-prompt.md") | head -10
fi
check_grep "full: compose prompt uses the bouncer preamble" "$STUB_STDIN_DIR/compose.txt" \
  '^Respond to the following thoroughly and substantively\.$'
check_nogrep "full: compose prompt has no frontmatter" "$STUB_STDIN_DIR/compose.txt" \
  'expected_plan_words'

# The critique prompt must carry the persona and the plan, and must NOT carry
# the template's benchmark-naming HTML comment.
check_grep "full: critique prompt carries the persona" "$STUB_STDIN_DIR/codex.txt" \
  'Your job: find what is wrong'
check_grep "full: critique prompt carries the plan" "$STUB_STDIN_DIR/codex.txt" \
  'Stage one covers routing'
check_nogrep "full: critique prompt drops the template comment" "$STUB_STDIN_DIR/codex.txt" \
  '<!--|run-panel\.sh|condition C'
check_nogrep "full: critique prompt has no unsubstituted placeholders" "$STUB_STDIN_DIR/codex.txt" \
  '\{TASK\}|\{PLAN_CONTENT\}'

# --- 2. Vendor blindness of the synthesis prompt ------------------------------

SYNTH="$STUB_STDIN_DIR/synthesis.txt"
check_grep "blind: Reviewer 1 label" "$SYNTH" '^### Reviewer 1$'
check_grep "blind: Reviewer 2 label" "$SYNTH" '^### Reviewer 2$'
check_grep "blind: Reviewer 3 label" "$SYNTH" '^### Reviewer 3$'
check_grep "blind: codex critique reached synthesis" "$SYNTH" 'ALPHA-CRITIQUE-TOKEN'
check_grep "blind: glm critique reached synthesis" "$SYNTH" 'BETA-CRITIQUE-TOKEN'
check_grep "blind: kimi critique reached synthesis" "$SYNTH" 'GAMMA-CRITIQUE-TOKEN'
check_nogrep "blind: no vendor names in the synthesis prompt" "$SYNTH" 'codex|glm|kimi|claude|anthropic|openai'
check_grep "blind: word target repeated" "$SYNTH" 'Produce a plan of roughly 600 words'
check_grep "blind: accept/reject instruction present" "$SYNTH" 'decide each one on its merits'
check_grep "blind: plan-only instruction present" "$SYNTH" 'Output ONLY the revised plan'
check_grep "blind: no-acknowledgments instruction present" "$SYNTH" 'no acknowledgments section'

# --- 3. Resume after kill ----------------------------------------------------
# Same out-dir; only final.md is removed. Nothing but synthesis may re-invoke.

PREV_OUT="$OUT"
PREV_STDIN="$STUB_STDIN_DIR"
scenario resume
OUT="$PREV_OUT"
rm -f "$OUT/final.md"
rc=0
run_panel --task-file "$FIXTURES/task-basic.md" || rc=$?
check_eq "resume: exit 0" "0" "$rc"
check_file "resume: final.md rewritten" "$OUT/final.md"
check_eq "resume: compose not re-invoked" "0" "$(seat_count compose)"
check_eq "resume: codex not re-invoked" "0" "$(seat_count codex)"
check_eq "resume: glm not re-invoked" "0" "$(seat_count glm)"
check_eq "resume: kimi not re-invoked" "0" "$(seat_count kimi)"
check_eq "resume: synthesis re-invoked once" "1" "$(seat_count synthesis)"
check_eq "resume: total invocations" "1" "$(wc -l < "$STUB_LOG" | tr -d '[:space:]')"
check_eq "resume: compose phase reused" "reused" "$(phase_field compose status)"
check_eq "resume: codex phase reused" "reused" "$(phase_field critique-codex status)"
check_eq "resume: kimi phase reused" "reused" "$(phase_field critique-kimi status)"
check_eq "resume: synthesis phase complete" "complete" "$(phase_field synthesis status)"
check_eq "resume: still not degraded" "false" "$(jq -r '.degraded' "$OUT/panel-state.json")"

# A fully-complete out-dir must be a no-op.
scenario resume_noop
OUT="$PREV_OUT"
rc=0
run_panel --task-file "$FIXTURES/task-basic.md" || rc=$?
check_eq "resume-noop: exit 0" "0" "$rc"
check_eq "resume-noop: zero invocations" "0" "$(wc -l < "$STUB_LOG" | tr -d '[:space:]')"
check_eq "resume-noop: synthesis reused" "reused" "$(phase_field synthesis status)"

# --- 4. Kimi size gate -------------------------------------------------------

scenario sizegate
rc=0
STUB_CLAUDE_MODE=big-plan run_panel --task-file "$FIXTURES/task-basic.md" || rc=$?
check_eq "sizegate: exit 0 (run continues)" "0" "$rc"
check_file "sizegate: skip marker written" "$OUT/critique-kimi.SKIPPED"
check_nofile "sizegate: no kimi critique" "$OUT/critique-kimi.md"
check_grep "sizegate: marker names the reason" "$OUT/critique-kimi.SKIPPED" 'reason: size'
check_grep "sizegate: marker names the byte count" "$OUT/critique-kimi.SKIPPED" '[0-9]{5} bytes'
check_eq "sizegate: kimi never invoked" "0" "$(seat_count kimi)"
check_eq "sizegate: kimi phase skipped" "skipped" "$(phase_field critique-kimi status)"
check_grep "sizegate: skip_reason recorded in state" "$OUT/panel-state.json" '"skip_reason": "size: prompt is'
check_eq "sizegate: degraded true" "true" "$(jq -r '.degraded' "$OUT/panel-state.json")"
check_eq "sizegate: kimi_status skipped" "skipped" "$(jq -r '.kimi_status' "$OUT/panel-state.json")"
check_eq "sizegate: state status complete" "complete" "$(jq -r '.status' "$OUT/panel-state.json")"
check_file "sizegate: final.md still written" "$OUT/final.md"
check_grep "sizegate: synthesis has Reviewer 2" "$STUB_STDIN_DIR/synthesis.txt" '^### Reviewer 2$'
check_nogrep "sizegate: synthesis has no Reviewer 3" "$STUB_STDIN_DIR/synthesis.txt" '^### Reviewer 3$'

# --- 5. Reviewer subset, order, and a task without frontmatter ---------------

scenario subset
rc=0
run_panel --task-file "$FIXTURES/task-nofrontmatter.md" --reviewers kimi,codex || rc=$?
check_eq "subset: exit 0" "0" "$rc"
check_eq "subset: glm not invoked" "0" "$(seat_count glm)"
check_eq "subset: two phases plus compose and synthesis" "4" \
  "$(jq -r '.phases | length' "$OUT/panel-state.json")"
check_eq "subset: reviewer order kept" "kimi codex" \
  "$(jq -r '.reviewers | join(" ")' "$OUT/panel-state.json")"
# Reviewer 1 is the first --reviewers entry (kimi → GAMMA), Reviewer 2 the second.
SUB_SYNTH="$STUB_STDIN_DIR/synthesis.txt"
check_eq "subset: Reviewer 1 is the first listed reviewer" "GAMMA" \
  "$(awk '/^### Reviewer 1$/{f=1;next} /^### Reviewer 2$/{f=0} f' "$SUB_SYNTH" | grep -oE '(ALPHA|BETA|GAMMA)' | head -1)"
check_eq "subset: Reviewer 2 is the second listed reviewer" "ALPHA" \
  "$(awk '/^### Reviewer 2$/{f=1;next} /^## INSTRUCTIONS$/{f=0} f' "$SUB_SYNTH" | grep -oE '(ALPHA|BETA|GAMMA)' | head -1)"
check_grep "subset: word target from a frontmatter-less task" "$SUB_SYNTH" \
  'Produce a plan of roughly 500 words'
check_eq "subset: no glm sidecar in the tokens block" "2" \
  "$(jq -r '[.tokens.phases[] | select(.source == "claude-json")] | length' "$OUT/panel-state.json")"

# --- 6. Every critique invalid → exit 1 --------------------------------------

scenario allfail
rc=0
STUB_CODEX_MODE=empty \
  run_panel --task-file "$FIXTURES/task-basic.md" --reviewers codex || rc=$?
check_eq "allfail: exit 1" "1" "$rc"
check_nofile "allfail: no final.md" "$OUT/final.md"
check_eq "allfail: synthesis never invoked" "0" "$(seat_count synthesis)"
check_eq "allfail: state status failed" "failed" "$(jq -r '.status' "$OUT/panel-state.json")"
check_eq "allfail: degraded true" "true" "$(jq -r '.degraded' "$OUT/panel-state.json")"
check_eq "allfail: all critiques invalid" "true" \
  "$(jq -r '[.phases[] | select(.phase | startswith("critique-")) | .status] | all(. == "invalid")' "$OUT/panel-state.json")"
check_file "allfail: compose artifact kept for resume" "$OUT/compose-output.md"
check_eq "allfail: kimi_status absent" "null" "$(jq -r '.kimi_status' "$OUT/panel-state.json")"

# --- 7. Auth failures → exit 4, artifact withheld ----------------------------

scenario composeauth
rc=0
STUB_CLAUDE_MODE=auth-fail run_panel --task-file "$FIXTURES/task-basic.md" || rc=$?
check_eq "compose-auth: exit 4" "4" "$rc"
check_nofile "compose-auth: compose artifact withheld" "$OUT/compose-output.md"
check_nofile "compose-auth: no final.md" "$OUT/final.md"
check_eq "compose-auth: no reviewer invoked" "0" "$(seat_count codex)"
check_eq "compose-auth: state status retryable" "retryable" "$(jq -r '.status' "$OUT/panel-state.json")"
check_eq "compose-auth: compose phase retryable" "retryable" "$(phase_field compose status)"

scenario synthauth
rc=0
STUB_CLAUDE_MODE=synth-auth-fail run_panel --task-file "$FIXTURES/task-basic.md" || rc=$?
check_eq "synth-auth: exit 4" "4" "$rc"
check_nofile "synth-auth: no final.md" "$OUT/final.md"
check_file "synth-auth: critiques kept for resume" "$OUT/critique-codex.md"
check_eq "synth-auth: state status retryable" "retryable" "$(jq -r '.status' "$OUT/panel-state.json")"

# --- 8. Argument validation --------------------------------------------------

scenario argv
rc=0
run_panel --task-file "$FIXTURES/task-basic.md" --reviewers codex,codex || rc=$?
check_eq "argv: duplicate reviewer rejected" "1" "$rc"
rc=0
run_panel --task-file "$FIXTURES/task-basic.md" --reviewers opus || rc=$?
check_eq "argv: unknown reviewer rejected" "1" "$rc"
rc=0
run_panel --task-file "$TEST_DIR/does-not-exist.md" || rc=$?
check_eq "argv: missing task file rejected" "1" "$rc"

# --- Summary -----------------------------------------------------------------

printf '\n'
if (( FAILED == 0 )); then
  printf 'test-panel.sh: %d/%d PASS\n' "$TOTAL" "$TOTAL"
  exit 0
fi
printf 'test-panel.sh: %d/%d FAILED\n' "$FAILED" "$TOTAL"
exit 1
