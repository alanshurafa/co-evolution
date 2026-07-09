#!/usr/bin/env bash
# tests/adversarial-persona-simulation.sh
# Hermetic gate for the --adversarial reviewer persona in co-evolve-bouncer.sh.
#
# --adversarial swaps the reviewer's 1-line role preamble for the structured
# falsification persona (templates/co-evolve/role-reviewer-adversarial.md); in
# chain mode it swaps only the pass-1 critique stage template
# (chain-critique-adversarial.md). It composes with --lens (lens becomes a
# focus line appended to the persona) and is recorded in state.json as the
# additive reviewer_persona field (adversarial > lens > light).
#
# Coverage:
#   1. Bounce mode: persona text lands in the pass-1 (reviewer) prompt, NOT in
#      the pass-2 (composer) prompt; state.json reviewer_persona=adversarial.
#   2. Chain mode: pass-1 prompt carries the adversarial critique variant and
#      not the default critique text; defend (pass 2) is untouched.
#   3. --adversarial --lens composes: persona + focus line in the same prompt.
#   4. Parity: without --adversarial the pass-1 prompt carries the light role
#      and no persona text; reviewer_persona=light (and =lens with --lens).
#   5. Same-model pair (--agents claude,claude) logs the cross-vendor warning.
#   6. --help documents --adversarial.
#
# Pattern: PATH-injected claude + codex stubs (same discipline as
# doc-pipeline-seats-simulation.sh); assertions grep the run dir's prompt
# files, state.json, and run.log. Both stubs drain stdin via a read-loop (NOT
# `cat`) to avoid SIGPIPE against the runner's stdin producer.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"

TEST_DIR="$(mktemp -d -t adv-persona-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# Distinctive tokens per template (quoted from the template files; if a
# template is reworded these greps are the tripwire that docs/tests drifted).
PERSONA_TOKEN='try to falsify this document'
CHAIN_ADV_TOKEN='CRITIQUE by falsification'
CHAIN_DEFAULT_TOKEN='Your job this pass: CRITIQUE\. Find every weakness'
LIGHT_TOKEN='find what is wrong, missing, weak, or unsupported'
LENS_FOCUS_TOKEN='Focus your adversarial review through this lens: security auditor'

# --- stub CLIs --------------------------------------------------------------
mkdir -p "$TEST_DIR/bin"

# claude stub: drain stdin, emit a body that clears the >=10-word gate and one
# [CONTESTED] marker so the loop always advances past the reviewer pass.
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --version|-v|version) echo "claude 1.0.0 (adv-persona-stub)"; exit 0 ;;
  esac
done
while IFS= read -r _line; do :; done   # drain stdin, no SIGPIPE
echo "Stub reviewer/composer body with plenty of plain words to clear the bouncer minimum word count and any downstream size or auth check applied to it."
echo "[CONTESTED] one open marker so the loop advances into the next pass."
STUB
chmod +x "$TEST_DIR/bin/claude"

# codex stub: parse -o FILE, drain stdin, emit a clean body (0 markers) so an
# even codex pass converges the loop.
cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --version|-v|version) echo "codex 0.117.0 (adv-persona-stub)"; exit 0 ;;
  esac
done
output_file=""; prev=""
for arg in "$@"; do
  case "$prev" in -o) output_file="$arg" ;; esac
  prev="$arg"
done
while IFS= read -r _line; do :; done   # drain stdin, no SIGPIPE
body="Stub composer body with plenty of plain words to clear the bouncer minimum word count and any downstream size or auth check applied to it."
if [[ -n "$output_file" ]]; then printf '%s\n' "$body" > "$output_file"; else printf '%s\n' "$body"; fi
STUB
chmod +x "$TEST_DIR/bin/codex"

DOC="$TEST_DIR/doc.md"
cat > "$DOC" <<'DOCEOF'
# Sample Document

## Claim
This is a sample document with enough plain words that the bouncer treats it as a
real document to review and improve across a couple of passes.

## Detail
It has multiple sections and sentences so the marker accounting and word counts
have real content to operate on during the bounce loop.
DOCEOF

# run_bouncer <runs-subdir> <args...>  — hermetic invocation; never fails the
# harness (stuck/adjudicated terminals are valid runs for these assertions).
run_bouncer() {
  local runs_dir="$1"; shift
  (
    unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
    unset COMPOSER_MODEL COMPOSER_EFFORT REVIEWER_MODEL REVIEWER_EFFORT
    export PATH="$TEST_DIR/bin:$PATH"
    export CO_EVOLVE_RUNS_DIR="$TEST_DIR/$runs_dir"
    bash "$BOUNCER" --vanilla --no-report "$@" "$DOC"
  ) >"$TEST_DIR/$runs_dir.out" 2>&1 || true
  ls -dt "$TEST_DIR/$runs_dir"/co-evolve-* 2>/dev/null | head -1
}

# ===========================================================================
# Scenario 1: bounce mode — persona in the reviewer prompt only; state field.
# ===========================================================================
TOTAL=$((TOTAL + 1))
run1=$(run_bouncer runs1 --adversarial --bounce-only --bounces 2)
s1_ok=true
if [[ -z "$run1" ]]; then
  s1_ok=false
else
  grep -Fq "$PERSONA_TOKEN" "$run1/.bounce-pass-1-prompt.md" 2>/dev/null || s1_ok=false
  # Composer (pass 2) keeps its own preamble — the persona must not leak in.
  if grep -Fq "$PERSONA_TOKEN" "$run1/.bounce-pass-2-prompt.md" 2>/dev/null; then s1_ok=false; fi
  # Light role text must be absent from the reviewer prompt (swap, not append).
  if grep -Fq "$LIGHT_TOKEN" "$run1/.bounce-pass-1-prompt.md" 2>/dev/null; then s1_ok=false; fi
  grep -Eq '"reviewer_persona": *"adversarial"' "$run1/state.json" 2>/dev/null || s1_ok=false
fi
if [[ "$s1_ok" == true ]]; then
  pass "bounce mode: persona in pass-1 prompt only; reviewer_persona=adversarial in state.json"
else
  fail "bounce-mode persona placement or state field wrong (run dir: ${run1:-missing})"
  [[ -n "$run1" ]] && ls "$run1" >&2
fi

# ===========================================================================
# Scenario 2: chain mode — adversarial critique variant on pass 1 only.
# ===========================================================================
TOTAL=$((TOTAL + 1))
run2=$(run_bouncer runs2 --adversarial --chain --bounce-only)
s2_ok=true
if [[ -z "$run2" ]]; then
  s2_ok=false
else
  grep -Fq "$CHAIN_ADV_TOKEN" "$run2/.bounce-pass-1-prompt.md" 2>/dev/null || s2_ok=false
  if grep -Eq "$CHAIN_DEFAULT_TOKEN" "$run2/.bounce-pass-1-prompt.md" 2>/dev/null; then s2_ok=false; fi
  # Defend stage (pass 2) must not carry the adversarial critique variant.
  if grep -Fq "$CHAIN_ADV_TOKEN" "$run2/.bounce-pass-2-prompt.md" 2>/dev/null; then s2_ok=false; fi
fi
if [[ "$s2_ok" == true ]]; then
  pass "chain mode: pass-1 uses chain-critique-adversarial.md; defend untouched"
else
  fail "chain-mode adversarial critique swap wrong (run dir: ${run2:-missing})"
  [[ -n "$run2" ]] && ls "$run2" >&2
fi

# ===========================================================================
# Scenario 3: --adversarial --lens compose — persona + focus line together.
# ===========================================================================
TOTAL=$((TOTAL + 1))
run3=$(run_bouncer runs3 --adversarial --lens "security auditor" --bounce-only --bounces 2)
s3_ok=true
if [[ -z "$run3" ]]; then
  s3_ok=false
else
  grep -Fq "$PERSONA_TOKEN" "$run3/.bounce-pass-1-prompt.md" 2>/dev/null || s3_ok=false
  grep -Fq "$LENS_FOCUS_TOKEN" "$run3/.bounce-pass-1-prompt.md" 2>/dev/null || s3_ok=false
  grep -Eq '"reviewer_persona": *"adversarial"' "$run3/state.json" 2>/dev/null || s3_ok=false
fi
if [[ "$s3_ok" == true ]]; then
  pass "--adversarial --lens composes: persona + lens focus line in the reviewer prompt"
else
  fail "adversarial+lens composition wrong (run dir: ${run3:-missing})"
  [[ -n "$run3" ]] && head -40 "$run3/.bounce-pass-1-prompt.md" >&2
fi

# ===========================================================================
# Scenario 4: parity — no --adversarial => light role, no persona text; and
# --lens alone records reviewer_persona=lens with the pre-persona lens text.
# ===========================================================================
TOTAL=$((TOTAL + 1))
run4=$(run_bouncer runs4 --bounce-only --bounces 2)
run4b=$(run_bouncer runs4b --lens "security auditor" --bounce-only --bounces 2)
s4_ok=true
if [[ -z "$run4" || -z "$run4b" ]]; then
  s4_ok=false
else
  grep -Fq "$LIGHT_TOKEN" "$run4/.bounce-pass-1-prompt.md" 2>/dev/null || s4_ok=false
  if grep -Fq "$PERSONA_TOKEN" "$run4/.bounce-pass-1-prompt.md" 2>/dev/null; then s4_ok=false; fi
  grep -Eq '"reviewer_persona": *"light"' "$run4/state.json" 2>/dev/null || s4_ok=false
  # Lens-only path: pre-persona lens preamble, no adversarial persona text.
  grep -Fq 'You are the security auditor reviewing this work' "$run4b/.bounce-pass-1-prompt.md" 2>/dev/null || s4_ok=false
  if grep -Fq "$PERSONA_TOKEN" "$run4b/.bounce-pass-1-prompt.md" 2>/dev/null; then s4_ok=false; fi
  grep -Eq '"reviewer_persona": *"lens"' "$run4b/state.json" 2>/dev/null || s4_ok=false
fi
if [[ "$s4_ok" == true ]]; then
  pass "parity: default path keeps the light role (persona=light); lens-only path unchanged (persona=lens)"
else
  fail "adversarial-off parity broken (run dirs: ${run4:-missing}, ${run4b:-missing})"
fi

# ===========================================================================
# Scenario 5: same-model pair logs the cross-vendor warning.
# ===========================================================================
TOTAL=$((TOTAL + 1))
run5=$(run_bouncer runs5 --adversarial --agents claude,claude --bounce-only --bounces 2)
s5_ok=true
if [[ -z "$run5" ]]; then
  s5_ok=false
else
  grep -Fq 'same-model bounce (claude vs claude)' "$run5/run.log" 2>/dev/null || s5_ok=false
fi
# Cross-vendor default must NOT trip the warning.
if [[ -n "${run1:-}" ]] && grep -Fq 'same-model bounce' "$run1/run.log" 2>/dev/null; then s5_ok=false; fi
if [[ "$s5_ok" == true ]]; then
  pass "same-model pair logs the no-cross-vendor-disagreement warning; default pair does not"
else
  fail "same-model warning wrong (run dir: ${run5:-missing})"
  [[ -n "$run5" ]] && grep -F 'NOTE' "$run5/run.log" >&2 || true
fi

# ===========================================================================
# Scenario 6: --help documents --adversarial.
# ===========================================================================
TOTAL=$((TOTAL + 1))
help_out="$(bash "$BOUNCER" --help 2>/dev/null || true)"
if printf '%s' "$help_out" | grep -Eq -- '^[[:space:]]*--adversarial[[:space:]]'; then
  pass "--help documents --adversarial"
else
  fail "--help does not document --adversarial"
fi

# --- summary ----------------------------------------------------------------
passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
