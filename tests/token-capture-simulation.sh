#!/usr/bin/env bash
# tests/token-capture-simulation.sh
# Hermetic gate for v1.5 Phase 4: CO_EVOLVE_TOKEN_CAPTURE=1 token capture in
# lib/co-evolution.sh (invoke_claude gated JSON mode + collect_token_usage) and
# the runner's EOF aggregation into state.json.
#
# The capture is gated behind CO_EVOLVE_TOKEN_CAPTURE=1 AND jq present; default
# OFF must be byte-identical to today (argv, artifacts, no state.json `tokens`
# key). This gate pins:
#   a. flag ON, mixed run (claude compose+verify + codex execute) → state.json
#      .tokens.phases has both kinds of entries, totals are correct, the *.usage
#      and *.envelope sidecars are cleaned up, and the claude output files hold
#      the extracted `.result` text (NOT the raw envelope).
#   b. flag ON, malformed claude envelope → the output file falls back to the
#      envelope copy (non-empty), the run does not die, and that phase's tokens
#      entry carries nulls.
#   c. flag OFF (default) → claude argv contains `--output-format text` (not
#      json), NO *.envelope.json / *.usage.json sidecars survive, and state.json
#      has NO `tokens` key (the byte-parity guard).
#   d. flag OFF → `--help` is unaffected (still exits 0, still emits usage) and
#      no token machinery leaks into the help path.
#
# Pattern: PATH-injected claude + codex stubs (same discipline as
# tests/preset-expansion-simulation.sh) — drain stdin via a read-loop (NOT
# `cat`) to avoid SIGPIPE under strict-mode bash. The claude stub branches on
# whether `--output-format json` is in its argv: when present it emits a canned
# R1-shaped envelope (real token numbers) on stdout; otherwise the plain text
# body. Phase (compose/bounce vs verify) is detected from the prompt on stdin.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/dev-review/codex/dev-review.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required for this gate" >&2; exit 1; }

TEST_DIR="$(mktemp -d -t token-capture-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# --- hermetic git env (mirrors tests/run-all.sh) ----------------------------
export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
cat > "$TEST_DIR/gitconfig" <<'GITCFG'
[user]
	name = token-capture-sim
	email = token-capture-sim@invalid.local
[init]
	defaultBranch = master
[core]
	autocrlf = false
[commit]
	gpgsign = false
GITCFG

# --- canned R1 envelope numbers (the assertions key off these) --------------
# These are the per-claude-invocation token counts the stub reports. The runner
# calls claude once for compose and once for verify in the scenario-(a) run
# (bounces 0, so no bounce passes), so claude totals = 2x each field.
CLAUDE_IN=1111
CLAUDE_OUT=222
CLAUDE_CACHE_READ=33333
CLAUDE_CACHE_CREATE=44
CODEX_TOKENS=12345

# --- stub CLIs --------------------------------------------------------------
mkdir -p "$TEST_DIR/bin"

# claude stub. If `--output-format json` is in argv → emit a canned R1 envelope
# on stdout whose `.result` is a phase-appropriate body (plan or verdict).
# Otherwise → emit the body as plain text (the default text path). The
# MALFORMED_ENVELOPE env var (scenario b) makes the json path emit a body that
# is NOT valid JSON, exercising invoke_claude's envelope-copy fallback.
cat > "$TEST_DIR/bin/claude" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\$arg" in
    --version|-v|version) echo "claude 1.0.0 (token-capture-stub)"; exit 0 ;;
  esac
done
[[ -n "\${CLAUDE_ARGV_LOG:-}" ]] && printf '%s\n' "\$*" >> "\$CLAUDE_ARGV_LOG"
json_mode=false
for arg in "\$@"; do
  if [[ "\$arg" == "json" ]]; then json_mode=true; fi
done
# Drain stdin via read-loop (no SIGPIPE); capture to detect the phase.
stdin_capture=""
while IFS= read -r _line; do stdin_capture+="\$_line"\$'\n'; done

# Phase-appropriate text body.
if [[ "\$stdin_capture" == *"Verification Instructions"* ]]; then
  body=\$(cat <<'VERDICT'
{
  "verdict": "APPROVED",
  "confidence": 88,
  "summary": "Token-capture stub verifier approves the hermetic change.",
  "issues": []
}
VERDICT
)
else
  body=\$(cat <<'PLAN'
# Token Capture Stub Plan

## Approach

This is a hermetic stub plan emitted by the token-capture simulation claude
stub. It satisfies the plan heading regex, the minimum word count, and the
structural-line check so the compose phase validates and the run proceeds into
execute and verify. It is not a real plan and the only side effect is a single
harmless append to a tracked file so the run produces a diff for the verify
phase to score. No external commands run and no network is touched anywhere.

## Files to Change

- \`touched.txt\` — the executor stub appends a line so the run yields a diff.

## Risks

- None identified. Stubbed CLI produces a fixed plan with no side effects.
PLAN
)
fi

if [[ "\$json_mode" == true ]]; then
  if [[ "\${MALFORMED_ENVELOPE:-}" == "1" ]]; then
    # NOT a valid JSON envelope — invoke_claude must copy the raw stdout to the
    # output file (non-empty fallback) and write an all-null usage sidecar
    # (jq can't extract .usage from non-JSON). We emit the plain plan body so the
    # copied fallback still clears the compose plan-quality gate; the point under
    # test is the fallback + null-usage path, not the plan validator.
    printf '%s\n' "\$body"
    exit 1
  fi
  # Canned R1-shaped envelope on stdout. .result carries the text body. jq -n
  # builds it so .result is correctly JSON-escaped regardless of body content.
  jq -n --arg result "\$body" \
        --argjson it ${CLAUDE_IN} --argjson ot ${CLAUDE_OUT} \
        --argjson cr ${CLAUDE_CACHE_READ} --argjson cc ${CLAUDE_CACHE_CREATE} '
    {
      type: "result", subtype: "success", is_error: false,
      duration_ms: 100, num_turns: 1, result: \$result,
      total_cost_usd: 0.05,
      usage: {
        input_tokens: \$it, output_tokens: \$ot,
        cache_read_input_tokens: \$cr, cache_creation_input_tokens: \$cc
      }
    }'
  exit 0
fi
# Plain text path (flag OFF): just the body.
printf '%s\n' "\$body"
STUB
chmod +x "$TEST_DIR/bin/claude"

# codex stub: append argv, parse -o/-C, drain stdin, emit plan to -o (or make a
# real change in -C for the execute phase), and ALWAYS write the R2 token line
# to stderr so the harvest path has something to find.
cat > "$TEST_DIR/bin/codex" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\$arg" in
    --version|-v|version) echo "codex 0.140.0 (token-capture-stub)"; exit 0 ;;
  esac
done
[[ -n "\${CODEX_ARGV_LOG:-}" ]] && printf '%s\n' "\$*" >> "\$CODEX_ARGV_LOG"
output_file=""; workdir=""; prev=""
for arg in "\$@"; do
  case "\$prev" in
    -o) output_file="\$arg" ;;
    -C) workdir="\$arg" ;;
  esac
  prev="\$arg"
done
stdin_capture=""
while IFS= read -r _line; do stdin_capture+="\$_line"\$'\n'; done
if [[ "\$stdin_capture" == *"Execution Instructions (Codex)"* \
      && -n "\$workdir" && -f "\$workdir/touched.txt" ]]; then
  printf 'codex-stub-change\n' >> "\$workdir/touched.txt"
fi
# R2 token line on stderr (always — codex prints it at end of every run).
printf 'OpenAI Codex stub\ntokens used\n%s\n' "${CODEX_TOKENS}" >&2
plan_content=\$(cat <<'PLAN'
# Token Capture Stub Plan

## Approach

This is a hermetic stub plan emitted by the token-capture simulation codex
stub. It satisfies the plan heading regex, the minimum word count, and the
structural-line check so the compose phase validates and the run proceeds into
execute and verify. The only side effect is a single harmless append to a
tracked file so the run produces a diff. No external commands run and no
network is touched anywhere in this hermetic path.

## Files to Change

- \`touched.txt\` — appended to by the executor stub.

## Risks

- None identified. Stubbed codex produces a fixed plan with no side effects.
PLAN
)
if [[ -n "\$output_file" ]]; then
  printf '%s\n' "\$plan_content" > "\$output_file"
else
  printf '%s\n' "\$plan_content"
fi
exit 0
STUB
chmod +x "$TEST_DIR/bin/codex"

# --- helpers ----------------------------------------------------------------
make_scratch_repo() {
  local repo
  repo="$TEST_DIR/repo-$1"
  rm -rf "$repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  printf 'baseline\n' > "$repo/touched.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "baseline"
  printf '%s' "$repo"
}

# Explicit per-scenario run dirs (policy a) — avoids the `ls -dt runs/dev-review-*`
# newest-mtime race that cross-reads another concurrent suite's run dir. Each
# scenario passes --run-dir under this sim's own $TEST_DIR, so cleanup rides the
# existing TEST_DIR EXIT trap instead of a per-scenario rm -rf.

# ===========================================================================
# Scenario (a): flag ON, mixed run — claude composes + verifies, codex executes.
# Asserts: both kinds of phase entries, correct totals, sidecars cleaned, claude
# output files contain the extracted .result text (not the raw envelope).
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo a)
claude_log="$TEST_DIR/a_claude.log"; codex_log="$TEST_DIR/a_codex.log"
: > "$claude_log"; : > "$codex_log"
a_run_dir="$TEST_DIR/run-a"
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT MALFORMED_ENVELOPE
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  export CO_EVOLVE_TOKEN_CAPTURE=1
  # composer=claude, executor=codex, verifier=claude (opus alias). bounces 0 so
  # exactly two claude calls (compose + verify) and one codex call (execute).
  bash "$RUNNER" --composer opus --executor codex --verifier opus \
    --verify --bounces 0 --run-dir "$a_run_dir" --workdir "$repo" --timeout 60 -- "token capture mixed run"
) >"$TEST_DIR/a.out" 2>&1 || true
a_ok=true
a_msg=""
if [[ ! -f "$a_run_dir/state.json" ]]; then
  a_ok=false; a_msg="no run dir/state.json produced"
else
  state="$a_run_dir/state.json"
  # tokens block present, both phase kinds.
  if ! jq -e '.tokens.phases.compose.source == "claude-json"' "$state" >/dev/null 2>&1; then
    a_ok=false; a_msg="compose not claude-json"
  fi
  if ! jq -e '.tokens.phases.verify.source == "claude-json"' "$state" >/dev/null 2>&1; then
    a_ok=false; a_msg="verify not claude-json"
  fi
  if ! jq -e '.tokens.phases.execute.source == "codex-stderr"' "$state" >/dev/null 2>&1; then
    a_ok=false; a_msg="execute not codex-stderr"
  fi
  # totals: claude (compose+verify) = 2x each; codex = one execute line.
  exp_in=$((CLAUDE_IN * 2)); exp_out=$((CLAUDE_OUT * 2)); exp_cr=$((CLAUDE_CACHE_READ * 2))
  if ! jq -e --argjson v "$exp_in"  '.tokens.totals.claude_input == $v'      "$state" >/dev/null 2>&1; then a_ok=false; a_msg="claude_input total"; fi
  if ! jq -e --argjson v "$exp_out" '.tokens.totals.claude_output == $v'     "$state" >/dev/null 2>&1; then a_ok=false; a_msg="claude_output total"; fi
  if ! jq -e --argjson v "$exp_cr"  '.tokens.totals.claude_cache_read == $v' "$state" >/dev/null 2>&1; then a_ok=false; a_msg="claude_cache_read total"; fi
  if ! jq -e --argjson v "$CODEX_TOKENS" '.tokens.totals.codex_total_tokens == $v' "$state" >/dev/null 2>&1; then a_ok=false; a_msg="codex total"; fi
  # sidecars cleaned up (neither *.usage.json nor *.envelope.json survive).
  if ls "$a_run_dir"/*.usage.json "$a_run_dir"/.*.usage.json >/dev/null 2>&1; then a_ok=false; a_msg="usage sidecars survived"; fi
  if ls "$a_run_dir"/*.envelope.json "$a_run_dir"/.*.envelope.json >/dev/null 2>&1; then a_ok=false; a_msg="envelope sidecars survived"; fi
  # claude output files hold the extracted .result text — verdict.json must be
  # the verdict object (not the raw envelope, which would carry a "usage" key).
  if ! jq -e '.verdict == "APPROVED" and (has("usage") | not)' "$a_run_dir/verdict.json" >/dev/null 2>&1; then
    a_ok=false; a_msg="verdict.json is not the extracted .result"
  fi
fi
if [[ "$a_ok" == true ]]; then
  pass "flag ON mixed run: claude+codex phases captured, totals correct, sidecars cleaned, .result extracted"
else
  fail "flag ON mixed run failed ($a_msg) — run dir: ${a_run_dir:-<none>}"
  [[ -n "${a_run_dir:-}" ]] && jq -c '.tokens // "<no tokens key>"' "$a_run_dir/state.json" >&2 2>/dev/null || true
fi

# ===========================================================================
# Scenario (b): flag ON, malformed claude envelope. The compose output file
# falls back to the envelope copy (non-empty → run does not die mid-compose),
# and the compose tokens entry carries nulls.
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo b)
b_run_dir="$TEST_DIR/run-b"
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  export CO_EVOLVE_TOKEN_CAPTURE=1
  export MALFORMED_ENVELOPE=1
  # Only the compose phase is claude here; --bounces 0 and no --verify so the
  # malformed compose envelope is the one under test. plan-only keeps it short:
  # the run reaches the plan-only terminal (still calls maybe_collect_token_usage).
  bash "$RUNNER" --composer opus --plan-only --bounces 0 \
    --run-dir "$b_run_dir" --workdir "$repo" --timeout 60 -- "token capture malformed envelope"
) >"$TEST_DIR/b.out" 2>&1 || true
b_ok=true
b_msg=""
if [[ ! -f "$b_run_dir/state.json" ]]; then
  b_ok=false; b_msg="no run dir/state.json produced"
else
  state="$b_run_dir/state.json"
  # The run produced a plan.md from the envelope-copy fallback (non-empty).
  if [[ ! -s "$b_run_dir/plan.md" ]]; then b_ok=false; b_msg="plan.md empty (fallback did not copy envelope)"; fi
  # tokens block exists and the compose entry has null token fields.
  if ! jq -e '.tokens.phases.compose.source == "claude-json"' "$state" >/dev/null 2>&1; then
    b_ok=false; b_msg="compose entry missing"
  fi
  if ! jq -e '.tokens.phases.compose.input_tokens == null' "$state" >/dev/null 2>&1; then
    b_ok=false; b_msg="compose input_tokens not null on malformed envelope"
  fi
  # totals sum nulls as 0 → claude_input 0; state.json valid.
  if ! jq -e '.tokens.totals.claude_input == 0' "$state" >/dev/null 2>&1; then
    b_ok=false; b_msg="malformed totals not zeroed"
  fi
  if ! jq empty "$state" >/dev/null 2>&1; then b_ok=false; b_msg="state.json invalid JSON"; fi
fi
if [[ "$b_ok" == true ]]; then
  pass "flag ON malformed envelope: output falls back to envelope copy, run survives, tokens nulled"
else
  fail "flag ON malformed envelope failed ($b_msg) — run dir: ${b_run_dir:-<none>}"
fi

# ===========================================================================
# Scenario (c): flag OFF (default) — byte-parity guard. claude argv carries
# `--output-format text` (not json), NO envelope/usage sidecars survive, and
# state.json has NO `tokens` key.
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo c)
claude_log="$TEST_DIR/c_claude.log"; codex_log="$TEST_DIR/c_codex.log"
: > "$claude_log"; : > "$codex_log"
c_run_dir="$TEST_DIR/run-c"
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT MALFORMED_ENVELOPE
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  unset CO_EVOLVE_TOKEN_CAPTURE
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  bash "$RUNNER" --composer opus --executor codex --verifier opus \
    --verify --bounces 0 --run-dir "$c_run_dir" --workdir "$repo" --timeout 60 -- "token capture parity off"
) >"$TEST_DIR/c.out" 2>&1 || true
c_ok=true
c_msg=""
# claude argv: text mode, never json.
if ! grep -Eq -- '--output-format text' "$claude_log"; then c_ok=false; c_msg="claude not in text mode"; fi
if grep -Eq -- '--output-format json' "$claude_log"; then c_ok=false; c_msg="claude leaked json mode with flag off"; fi
if [[ ! -f "$c_run_dir/state.json" ]]; then
  c_ok=false; c_msg="no run dir/state.json produced"
else
  # No sidecars anywhere (they were never written).
  if ls "$c_run_dir"/*.usage.json "$c_run_dir"/.*.usage.json >/dev/null 2>&1; then c_ok=false; c_msg="usage sidecar exists with flag off"; fi
  if ls "$c_run_dir"/*.envelope.json "$c_run_dir"/.*.envelope.json >/dev/null 2>&1; then c_ok=false; c_msg="envelope sidecar exists with flag off"; fi
  # state.json has NO tokens key.
  if jq -e 'has("tokens")' "$c_run_dir/state.json" >/dev/null 2>&1; then c_ok=false; c_msg="state.json has tokens key with flag off"; fi
fi
if [[ "$c_ok" == true ]]; then
  pass "flag OFF parity: claude argv is --output-format text, no sidecars, no state.json tokens key"
else
  fail "flag OFF parity guard failed ($c_msg) — run dir: ${c_run_dir:-<none>}"
  [[ -s "$claude_log" ]] && { echo "--- claude argv ---"; cat "$claude_log"; } >&2
fi

# ===========================================================================
# Scenario (d): --help is unaffected by the capture machinery (exits 0, emits
# usage) regardless of the flag, and never references the token internals.
# ===========================================================================
TOTAL=$((TOTAL + 1))
d_ok=true
d_msg=""
# Help with flag explicitly ON must still behave exactly as the normal help.
help_on=$(CO_EVOLVE_TOKEN_CAPTURE=1 bash "$RUNNER" --help 2>/dev/null; echo "EXIT=$?")
help_off=$(bash "$RUNNER" --help 2>/dev/null; echo "EXIT=$?")
if [[ "$help_on" != *"EXIT=0"* ]]; then d_ok=false; d_msg="--help exit nonzero with flag on"; fi
if ! printf '%s' "$help_off" | grep -Eq -- '--composer|Usage|usage'; then d_ok=false; d_msg="--help did not emit usage"; fi
# The flag must not change help output (no token sidecars, no env-dependent text).
if [[ "${help_on%EXIT=*}" != "${help_off%EXIT=*}" ]]; then d_ok=false; d_msg="--help output differs by flag"; fi
if [[ "$d_ok" == true ]]; then
  pass "flag ON/OFF: --help unaffected (exit 0, usage emitted, byte-identical across the flag)"
else
  fail "--help affected by capture flag ($d_msg)"
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
