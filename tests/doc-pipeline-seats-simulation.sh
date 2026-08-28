#!/usr/bin/env bash
# tests/doc-pipeline-seats-simulation.sh
# Hermetic gate for v1.5 Phase 1 (A-4b): document-pipeline per-role seats in
# co-evolve-bouncer.sh.
#
# The bouncer runs two roles: the reviewer (odd passes / chain critique+tighten,
# default agent AGENT_A=claude) and the composer (even passes / chain defend,
# default agent AGENT_B=codex; the compose phase also runs the composer role on
# AGENT_A=claude). A-4b lets each role carry its own model/effort seat, layered
# onto the global CLAUDE_MODEL/CODEX_MODEL + effort vars around each invocation
# with the SAME cross-agent leak guard dev-review uses (a claude-shaped seat never
# reaches a codex argv and vice versa).
#
# Coverage:
#   1. REVIEWER_MODEL reaches the reviewer pass's claude argv (odd pass=claude),
#      COMPOSER_MODEL (a gpt- id) reaches the composer pass's codex argv (even
#      pass=codex), and NEITHER cross-leaks: the reviewer claude id never lands in
#      the codex argv, and the compose-phase claude argv (composer role on a claude
#      agent) does NOT carry the gpt- COMPOSER_MODEL — the leak guard drops it and
#      claude falls back to base.
#   2. REVIEWER_EFFORT reaches the reviewer claude argv as --effort.
#   3. Parity: a run with NO seat env/flags emits no --effort (claude) and no
#      model_reasoning_effort (codex) anywhere — byte-parity with the pre-Phase-1
#      bouncer. Claude argv shows the base default model (claude-opus-4-8).
#   4. --reviewer-model flag beats the REVIEWER_MODEL env var (flag last-wins).
#   5. --help documents the four new per-role flags and offers no global --effort.
#
# Pattern: PATH-injected claude + codex stubs append their full argv (one line per
# invocation) to phase-agnostic logs; assertions grep the logs. The claude stub
# can also record each call's ANTHROPIC_* environment in delimited blocks, which
# lets the GLM -> Claude regression inspect two sequential passes from one runner
# process. Both stubs drain stdin via a read-loop (NOT `cat`) to avoid SIGPIPE
# against the runner's stdin producer under strict-mode bash. Same discipline as
# preset-expansion-simulation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"

TEST_DIR="$(mktemp -d -t doc-seats-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# --- stub CLIs --------------------------------------------------------------
mkdir -p "$TEST_DIR/bin"

# claude stub: append full argv to $CLAUDE_ARGV_LOG, drain stdin, emit a body big
# enough to clear the bouncer's >=10-word compose gate and not look like an auth
# failure. It emits ONE [CONTESTED] marker so the bounce loop does NOT converge
# after pass 1 (the reviewer pass, on claude) — that keeps the loop running into
# pass 2 (the composer pass, on codex) so the codex composer argv is exercised.
# The codex stub emits a clean body (0 markers) so pass 2 converges the loop.
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --version|-v|version) echo "claude 1.0.0 (doc-seat-stub)"; exit 0 ;;
  esac
done
[[ -n "${CLAUDE_ARGV_LOG:-}" ]] && printf '%s\n' "$*" >> "$CLAUDE_ARGV_LOG"
if [[ -n "${CLAUDE_ENV_LOG:-}" ]]; then
  {
    printf '%s\n' '--- CALL ---'
    printf 'ARGV=%s\n' "$*"
    # Record only the two scoping signals under test. Never dump the wider
    # ANTHROPIC_* environment: a developer may carry a real API key there.
    [[ -n "${ANTHROPIC_BASE_URL+x}" ]] && \
      printf 'ANTHROPIC_BASE_URL=%s\n' "$ANTHROPIC_BASE_URL"
    [[ -n "${ANTHROPIC_AUTH_TOKEN+x}" ]] && \
      printf '%s\n' 'ANTHROPIC_AUTH_TOKEN_PRESENT=1'
    for provider_var in \
      ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS CLAUDE_CODE_OAUTH_TOKEN \
      CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
      [[ -n "${!provider_var+x}" ]] && printf '%s_PRESENT=1\n' "$provider_var"
    done
    printf '%s\n' '--- END CALL ---'
  } >> "$CLAUDE_ENV_LOG"
fi
while IFS= read -r _line; do :; done   # drain stdin, no SIGPIPE
echo "Stub reviewer/composer body with plenty of plain words to clear the bouncer minimum word count and any downstream size or auth check applied to it."
if [[ "${CLAUDE_CLEAN_WITHOUT_ANTHROPIC:-}" != "1" || -n "${ANTHROPIC_BASE_URL:-}" ]]; then
  echo "[CONTESTED] one open marker so the loop advances into the next composer pass."
fi
STUB
chmod +x "$TEST_DIR/bin/claude"

# codex stub: append full argv to $CODEX_ARGV_LOG, parse -o FILE, drain stdin,
# emit a clean body (no markers) to -o FILE so pass 2 converges the loop.
cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --version|-v|version) echo "codex 0.117.0 (doc-seat-stub)"; exit 0 ;;
  esac
done
[[ -n "${CODEX_ARGV_LOG:-}" ]] && printf '%s\n' "$*" >> "$CODEX_ARGV_LOG"
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

# A document fixture to bounce (--bounce-only skips compose so we drive only the
# bounce loop for the reviewer/composer argv assertions; scenario 1 uses compose
# to also cover the compose-phase leak-guard fallback).
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

# ===========================================================================
# Scenario 1: seat propagation + no cross-leak (compose + 2 bounce passes).
#   REVIEWER_MODEL=claude-reviewer-xyz  -> reviewer pass (claude) argv.
#   COMPOSER_MODEL=gpt-composer-xyz     -> composer pass (codex) argv.
#   Compose phase (claude, composer role) must NOT carry the gpt- id (leak guard
#   drops it) — it falls back to the base default claude-opus-4-8.
# ===========================================================================
TOTAL=$((TOTAL + 1))
claude_log="$TEST_DIR/s1_claude.log"; codex_log="$TEST_DIR/s1_codex.log"
: > "$claude_log"; : > "$codex_log"
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  export REVIEWER_MODEL="claude-reviewer-xyz"
  export COMPOSER_MODEL="gpt-composer-xyz"
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  export CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs1"
  bash "$BOUNCER" --vanilla --no-report --bounces 2 "$DOC"
) >"$TEST_DIR/s1.out" 2>&1 || true

s1_ok=true
# reviewer pass (odd, claude) carries REVIEWER_MODEL.
if ! grep -Eq -- '--model claude-reviewer-xyz' "$claude_log"; then s1_ok=false; fi
# composer pass (even, codex) carries COMPOSER_MODEL as -c model=.
if ! grep -Eq -- '-c model=gpt-composer-xyz' "$codex_log"; then s1_ok=false; fi
# No cross-leak: the reviewer's claude id never reaches the codex argv.
if grep -Eq -- 'claude-reviewer-xyz' "$codex_log"; then s1_ok=false; fi
# No cross-leak: the gpt- composer id never reaches ANY claude argv (compose phase
# runs the composer role on a claude agent; the guard must drop the gpt- id).
if grep -Eq -- 'gpt-composer-xyz' "$claude_log"; then s1_ok=false; fi
# Compose-phase claude fell back to the base default model.
if ! grep -Eq -- '--model claude-opus-4-8' "$claude_log"; then s1_ok=false; fi
# v1.5 Phase 1 (M2): the drop is surfaced, not silent — the run log carries the
# explicit drop NOTE and the startup banner shows the compose phase's own seat.
s1_run_log=$(ls -dt "$TEST_DIR"/runs1/co-evolve-*/run.log 2>/dev/null | head -1)
if [[ -z "$s1_run_log" ]]; then
  s1_ok=false
else
  if ! grep -Fq 'composer seat override dropped for compose phase: agent mismatch (codex override, claude phase)' "$s1_run_log"; then s1_ok=false; fi
  if ! grep -Eq '^ Compose seat:  claude:' "$s1_run_log"; then s1_ok=false; fi
fi
if [[ "$s1_ok" == true ]]; then
  pass "doc seats: REVIEWER_MODEL->claude argv, COMPOSER_MODEL->codex argv, no cross-leak, compose falls back to base + drop NOTE + banner seat"
else
  fail "doc seat propagation/leak-guard mismatch (logs below)"
  { echo "--- claude argv ---"; cat "$claude_log"; echo "--- codex argv ---"; cat "$codex_log"
    [[ -n "${s1_run_log:-}" ]] && { echo "--- run.log seat/NOTE lines ---"; grep -E 'seat|NOTE' "$s1_run_log" || true; }
  } >&2
fi

# ===========================================================================
# Scenario 2: REVIEWER_EFFORT reaches the reviewer claude argv as --effort.
# ===========================================================================
TOTAL=$((TOTAL + 1))
claude_log="$TEST_DIR/s2_claude.log"; codex_log="$TEST_DIR/s2_codex.log"
: > "$claude_log"; : > "$codex_log"
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT COMPOSER_MODEL COMPOSER_EFFORT
  export REVIEWER_MODEL="claude-reviewer-xyz" REVIEWER_EFFORT="high"
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  export CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs2"
  bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 2 "$DOC"
) >"$TEST_DIR/s2.out" 2>&1 || true
# The reviewer argv is the claude line carrying the reviewer model + effort.
s2_reviewer_argv=$(grep -- '--model claude-reviewer-xyz' "$claude_log" || true)
if [[ -n "$s2_reviewer_argv" ]] && printf '%s' "$s2_reviewer_argv" | grep -Eq -- '--effort high'; then
  pass "doc seats: REVIEWER_EFFORT reaches the reviewer claude argv as --effort high"
else
  fail "REVIEWER_EFFORT did not reach the reviewer argv (claude argv below)"
  cat "$claude_log" >&2
fi

# ===========================================================================
# Scenario 3: parity — no seat env/flags => no --effort, no model_reasoning_effort
# anywhere; claude argv shows the bumped base default (claude-opus-4-8).
# ===========================================================================
TOTAL=$((TOTAL + 1))
claude_log="$TEST_DIR/s3_claude.log"; codex_log="$TEST_DIR/s3_codex.log"
: > "$claude_log"; : > "$codex_log"
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT REVIEWER_MODEL REVIEWER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  export CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs3"
  bash "$BOUNCER" --vanilla --no-report --bounces 2 "$DOC"
) >"$TEST_DIR/s3.out" 2>&1 || true
s3_ok=true
if grep -Eq -- '--effort ' "$claude_log"; then s3_ok=false; fi
if grep -Eq -- 'model_reasoning_effort=' "$codex_log"; then s3_ok=false; fi
if ! grep -Eq -- '--model claude-opus-4-8' "$claude_log"; then s3_ok=false; fi
if [[ "$s3_ok" == true ]]; then
  pass "doc seats parity: no --effort / no model_reasoning_effort; claude base = claude-opus-4-8"
else
  fail "doc seats parity leak (logs below)"
  { echo "--- claude argv ---"; cat "$claude_log"; echo "--- codex argv ---"; cat "$codex_log"; } >&2
fi

# ===========================================================================
# Scenario 4: --reviewer-model flag beats the REVIEWER_MODEL env var (last-wins).
# ===========================================================================
TOTAL=$((TOTAL + 1))
claude_log="$TEST_DIR/s4_claude.log"; codex_log="$TEST_DIR/s4_codex.log"
: > "$claude_log"; : > "$codex_log"
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT COMPOSER_MODEL COMPOSER_EFFORT
  export REVIEWER_MODEL="claude-env-loser"
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  export CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs4"
  bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 2 \
    --reviewer-model claude-flag-winner "$DOC"
) >"$TEST_DIR/s4.out" 2>&1 || true
if grep -Eq -- '--model claude-flag-winner' "$claude_log" \
   && ! grep -Eq -- '--model claude-env-loser' "$claude_log"; then
  pass "doc seats: --reviewer-model flag beats REVIEWER_MODEL env (last-wins)"
else
  fail "--reviewer-model flag did not beat the env var (claude argv below)"
  cat "$claude_log" >&2
fi

# ===========================================================================
# Scenario 5: --help documents the four per-role flags and NO global --effort.
# ===========================================================================
TOTAL=$((TOTAL + 1))
help_out="$(bash "$BOUNCER" --help 2>/dev/null || true)"
h5_ok=true
for flag in -- '--composer-model' '--composer-effort' '--reviewer-model' '--reviewer-effort'; do
  [[ "$flag" == "--" ]] && continue
  printf '%s' "$help_out" | grep -Eq -- "$flag" || h5_ok=false
done
# Deliberately NO bare global --effort flag (only the per-role effort flags).
if printf '%s' "$help_out" | grep -Eq -- '^[[:space:]]*--effort '; then h5_ok=false; fi
if [[ "$h5_ok" == true ]]; then
  pass "--help documents the four per-role seat flags and offers no global --effort"
else
  fail "--help missing a per-role flag or leaks a global --effort"
  printf '%s\n' "$help_out" | grep -E -- '--(composer|reviewer|effort)' >&2 || true
fi

# ===========================================================================
# Scenario 6: GLM endpoint credentials are child-scoped within ONE runner.
# Pass 1 is glm and must receive the Z.AI endpoint/token. Pass 2 is plain Claude
# in the same bouncer process and must receive neither variable. Separate runs
# would not detect an export leak, so this scenario deliberately uses one
# --agents glm,claude invocation with two sequential bounce passes.
# ===========================================================================
TOTAL=$((TOTAL + 1))
claude_log="$TEST_DIR/s6_claude.log"; env_log="$TEST_DIR/s6_env.log"
: > "$claude_log"; : > "$env_log"
(
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN
  export ANTHROPIC_API_KEY="inherited-secret-sentinel"
  export ANTHROPIC_CUSTOM_HEADERS="x-secret: inherited-sentinel"
  export CLAUDE_CODE_OAUTH_TOKEN="inherited-oauth-sentinel"
  export CLAUDE_CODE_USE_BEDROCK=1
  export CLAUDE_CODE_USE_VERTEX=1
  export CLAUDE_CODE_USE_FOUNDRY=1
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT REVIEWER_MODEL REVIEWER_EFFORT
  export ZAI_API_KEY="zai-hermetic-test-token"
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CLAUDE_ENV_LOG="$env_log"
  export CLAUDE_CLEAN_WITHOUT_ANTHROPIC=1
  export CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs6"
  bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 2 \
    --agents glm,claude "$DOC"
) >"$TEST_DIR/s6.out" 2>&1
s6_rc=$?

# Flatten each delimited call block to one line so the env assertions remain
# tied to the corresponding model argv rather than merely checking the file.
awk '
  /^--- CALL ---$/ { block=""; next }
  /^--- END CALL ---$/ { print block; next }
  { block = block (block == "" ? "" : " | ") $0 }
' "$env_log" > "$TEST_DIR/s6_calls.log"
s6_glm_call=$(grep -- '--model glm-5.3-flash' "$TEST_DIR/s6_calls.log" || true)
s6_claude_call=$(grep -- '--model claude-opus-4-8' "$TEST_DIR/s6_calls.log" || true)
s6_call_count=$(wc -l < "$TEST_DIR/s6_calls.log" | tr -d '\r\n ')
s6_ok=true
[[ "$s6_rc" -eq 0 ]] || s6_ok=false
[[ "$s6_call_count" == "2" ]] || s6_ok=false
printf '%s' "$s6_glm_call" | grep -Fq 'ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic' || s6_ok=false
printf '%s' "$s6_glm_call" | grep -Fq 'ANTHROPIC_AUTH_TOKEN_PRESENT=1' || s6_ok=false
printf '%s' "$s6_glm_call" | grep -Fq -- '--safe-mode' || s6_ok=false
printf '%s' "$s6_glm_call" | grep -Fq -- '--tools=' || s6_ok=false
if printf '%s' "$s6_claude_call" | grep -Eq 'ANTHROPIC_(BASE_URL|AUTH_TOKEN_PRESENT)='; then s6_ok=false; fi
for provider_var in \
  ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS CLAUDE_CODE_OAUTH_TOKEN \
  CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY; do
  if printf '%s' "$s6_glm_call" | grep -Fq "${provider_var}_PRESENT=1"; then s6_ok=false; fi
  printf '%s' "$s6_claude_call" | grep -Fq "${provider_var}_PRESENT=1" || s6_ok=false
done
if [[ "$s6_ok" == true ]]; then
  pass "GLM env scope: one glm,claude run gives Z.AI vars only to GLM, never the following Claude pass"
else
  fail "GLM env scope leaked or the single-run two-pass contract was not exercised"
  { echo "--- bouncer output ---"; cat "$TEST_DIR/s6.out"
    echo "--- per-call env ---"; cat "$TEST_DIR/s6_calls.log"; } >&2
fi

# ===========================================================================
# Scenario 7: an unknown agent fails from an explicit case arm before any agent
# process starts. This locks out the historical binary "codex else claude"
# fallback that could silently reinterpret a typo as a Claude seat.
# ===========================================================================
TOTAL=$((TOTAL + 1))
: > "$TEST_DIR/s7_claude.log"
s7_rc=0
(
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$TEST_DIR/s7_claude.log"
  export CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs7"
  bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 1 \
    --agents claude,nonsense "$DOC"
) >"$TEST_DIR/s7.out" 2>&1 || s7_rc=$?
if [[ "$s7_rc" -ne 0 ]] \
   && grep -Fq 'ERROR: Unknown agent: nonsense' "$TEST_DIR/s7.out" \
   && [[ ! -s "$TEST_DIR/s7_claude.log" ]]; then
  pass "unknown agent: claude,nonsense dies explicitly before invoking Claude"
else
  fail "unknown agent did not die from the explicit case path"
  { cat "$TEST_DIR/s7.out"; cat "$TEST_DIR/s7_claude.log"; } >&2
fi

# ===========================================================================
# Scenario 8: WSL must die loudly before invoking the Windows Claude dispatch.
# A Bash-side `env` prefix cannot cross cmd.exe, so continuing could otherwise
# send a GLM-intended prompt to the operator's real Anthropic account.
# ===========================================================================
TOTAL=$((TOTAL + 1))
cat > "$TEST_DIR/bin/cmd.exe" <<'STUB'
#!/usr/bin/env bash
echo "cmd.exe must not be invoked for a GLM seat" >&2
exit 99
STUB
chmod +x "$TEST_DIR/bin/cmd.exe"
: > "$TEST_DIR/s8_claude.log"
s8_rc=0
(
  export ZAI_API_KEY="zai-hermetic-test-token"
  export WSL_DISTRO_NAME="co-evolve-test-wsl"
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$TEST_DIR/s8_claude.log"
  export CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs8"
  bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 1 \
    --agents glm,claude "$DOC"
) >"$TEST_DIR/s8.out" 2>&1 || s8_rc=$?
if [[ "$s8_rc" -ne 0 ]] \
   && grep -Fq 'ERROR: glm seat unsupported under WSL claude dispatch' "$TEST_DIR/s8.out" \
   && [[ ! -s "$TEST_DIR/s8_claude.log" ]]; then
  pass "GLM WSL guard: dies loudly before cmd.exe or Claude dispatch"
else
  fail "GLM WSL guard did not fail before agent dispatch"
  { cat "$TEST_DIR/s8.out"; cat "$TEST_DIR/s8_claude.log"; } >&2
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
