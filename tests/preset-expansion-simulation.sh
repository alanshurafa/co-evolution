#!/usr/bin/env bash
# tests/preset-expansion-simulation.sh
# Hermetic gate for v1.5 Phase 2: --preset codex-build + claude-verifier
# verdict hardening (dev-review/codex/dev-review.sh).
#
# The codex-build preset expands to the post's ladder — best (currently Opus)
# plans (high), Codex executes (xhigh), best reviews (max) — behind one flag.
# The claude-build preset mirrors it: Codex plans/reviews (xhigh, model
# unpinned), Claude executes (best/high).
# This gate pins:
#   a. seat argv under the preset (composer claude --model claude-opus-4-8
#      [the `best` alias resolved] --effort high; executor codex PINNED
#      -c model=gpt-5.5 + -c model_reasoning_effort=xhigh [A-3]; verifier claude
#      --effort max).
#   b. claude-verifier verdict hardening: a verdict wrapped in markdown
#      fences/prose lands in verdict.json jq-parseable (brace-block fallback).
#   c. last-wins parsing: --verifier codex after --preset wins.
#   d. fill-if-empty: a pre-set COMPOSER_EFFORT env var beats the preset.
#   e. unknown preset dies with the right message.
#   f. --help mentions --preset.
#   g. parity guard: a default run emits no --effort and no
#      model_reasoning_effort anywhere.
#   h. cross-agent leak guard: --verifier codex over the preset must NOT leak
#      the claude verifier's best@max into the codex verify argv (live HTTP 400
#      on a ChatGPT account); seat_models.verifier falls back to default.
#   i. alias resolution: resolve_claude_model_alias maps best/opus ->
#      claude-opus-4-8, keeps fable -> claude-fable-5, passes ids through.
#   j. --preset claude-build: composer=codex gpt-5.5/xhigh, executor=claude
#      best/high, verifier=codex gpt-5.5/xhigh, with no codex model leaking
#      into the claude executor argv.
#   k. bounce counterparty seat (A-8): BOUNCER_MODEL reaches the bounce reviewer
#      argv and state.json seat_models.bouncer records it; no leak into codex.
#
# Pattern: PATH-injected claude + codex stubs append their full argv (one line
# per invocation) to phase-agnostic logs; assertions grep the logs. Both stubs
# drain stdin via a read-loop (NOT `cat`) to avoid SIGPIPE against the runner's
# stdin producer under strict-mode bash (same discipline as the scorer Tier-4
# stubs in evals/tests/scorer-verification.sh).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/dev-review/codex/dev-review.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP-FAIL: jq required for this gate" >&2; exit 1; }

TEST_DIR="$(mktemp -d -t preset-expand-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# --- hermetic git env (mirrors tests/run-all.sh so the scratch repo is
# independent of the host's identity / autocrlf / hooks) ---------------------
export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
cat > "$TEST_DIR/gitconfig" <<'GITCFG'
[user]
	name = preset-sim
	email = preset-sim@invalid.local
[init]
	defaultBranch = master
[core]
	autocrlf = false
[commit]
	gpgsign = false
GITCFG

# --- stub CLIs --------------------------------------------------------------
mkdir -p "$TEST_DIR/bin"

# claude stub: append full argv to $CLAUDE_ARGV_LOG (one line per invocation),
# drain stdin via read-loop, then emit a phase-appropriate body. The verify
# phase is detected by the review-prompt heading on stdin; for it the stub
# emits a verdict whose JSON object lives at column 0 wrapped in prose + fences
# (exercises the brace-block hardening fallback). The Opus execute phase appends
# to touched.txt when the runner grants a writable --add-dir. All other phases
# emit a plan.
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --version|-v|version) echo "claude 1.0.0 (preset-stub)"; exit 0 ;;
  esac
done
[[ -n "${CLAUDE_ARGV_LOG:-}" ]] && printf '%s\n' "$*" >> "$CLAUDE_ARGV_LOG"
workdir=""; prev=""
for arg in "$@"; do
  case "$prev" in
    --add-dir) workdir="$arg" ;;
  esac
  prev="$arg"
done
# Drain stdin via read-loop (no SIGPIPE); capture it so we can detect the phase.
stdin_capture=""
while IFS= read -r _line; do stdin_capture+="$_line"$'\n'; done
if [[ "$stdin_capture" == *"Verification Instructions"* ]]; then
  # Verify phase: prose-wrapped, fenced verdict. The JSON object's braces sit at
  # column 0 so the runner's `sed -n '/^{/,/^}/p'` brace-block fallback recovers
  # clean JSON after normalize_json_artifact rejects the mixed fence+prose.
  cat <<'VERDICT'
Here is my assessment of the diff against the plan.

```json
{
  "verdict": "APPROVED",
  "confidence": 90,
  "summary": "Stub verifier approves the hermetic change.",
  "issues": []
}
```

That concludes the review.
VERDICT
  exit 0
fi
if [[ "$stdin_capture" == *"Execution Instructions (Opus)"* \
      && -n "$workdir" && -f "$workdir/touched.txt" ]]; then
  printf 'claude-stub-change\n' >> "$workdir/touched.txt"
fi
# Compose / bounce phase: emit a minimal valid plan that clears the plan_quality
# gate (validate_plan_artifact wants >= 60 words, >= 5 non-empty lines, >= 2
# structural lines) so PLAN_EXIT stays 0 and the execute + verify phases run.
cat <<'PLAN'
# Preset Expansion Stub Plan

## Approach

This is a hermetic stub plan emitted by the preset-expansion simulation claude
stub. It exists solely to satisfy the plan heading regex, the minimum word
count, and the structural-line check so the compose phase validates and the run
proceeds into execute and verify. It is not a real plan and the executor stub
performs only a single harmless append to a tracked file so the run produces a
diff for the verify phase to score. No external commands run and no network is
touched anywhere in this hermetic path.

## Files to Change

- `touched.txt` — the executor stub appends a line so the run produces a diff.

## Risks

- None identified. Stubbed CLI produces a fixed plan with no side effects.
PLAN
STUB
chmod +x "$TEST_DIR/bin/claude"

# codex stub: append full argv to $CODEX_ARGV_LOG, parse -o FILE and -C DIR,
# drain stdin, then (a) emit the same stub plan to -o FILE (compose/bounce) and
# (b) make a real file change inside -C DIR so the execute phase yields a
# non-empty diff (so verify actually runs). The execute phase is the one that
# carries -C to the workdir; for it we append a line to a tracked file.
cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --version|-v|version) echo "codex 0.117.0 (preset-stub)"; exit 0 ;;
  esac
done
[[ -n "${CODEX_ARGV_LOG:-}" ]] && printf '%s\n' "$*" >> "$CODEX_ARGV_LOG"
output_file=""; workdir=""; prev=""
for arg in "$@"; do
  case "$prev" in
    -o) output_file="$arg" ;;
    -C) workdir="$arg" ;;
  esac
  prev="$arg"
done
# Capture stdin (no SIGPIPE) so we can detect the execute phase by its prompt.
stdin_capture=""
while IFS= read -r _line; do stdin_capture+="$_line"$'\n'; done
# Only the EXECUTE phase may mutate the workdir — bounce passes (also codex
# under the preset, since composer=opus → reviewer=codex) run BEFORE the runner
# snapshots INITIAL_GIT_STATUS, so a bounce-time edit would make execute look
# like a no-op ("no changes detected"). Gate on the execute-prompt heading.
if [[ "$stdin_capture" == *"Execution Instructions (Codex)"* \
      && -n "$workdir" && -f "$workdir/touched.txt" ]]; then
  printf 'codex-stub-change\n' >> "$workdir/touched.txt"
fi
plan_content=$(cat <<'PLAN'
# Preset Expansion Stub Plan

## Approach

This is a hermetic stub plan emitted by the preset-expansion simulation codex
stub. It satisfies the plan heading regex, the minimum word count, and the
structural-line check so the compose phase validates and the run proceeds into
execute and verify. It is not a real plan and the only side effect is a single
harmless append to a tracked file so the run produces a diff for the verify
phase to score. No external commands run and no network is touched anywhere.

## Files to Change

- `touched.txt` — appended to by the executor stub.

## Risks

- None identified. Stubbed codex produces a fixed plan with no side effects.
PLAN
)
if [[ -n "$output_file" ]]; then
  printf '%s\n' "$plan_content" > "$output_file"
else
  printf '%s\n' "$plan_content"
fi
exit 0
STUB
chmod +x "$TEST_DIR/bin/codex"

# --- helpers ----------------------------------------------------------------

# Make a fresh scratch git repo with one tracked file. Echoes the repo path.
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

# A pre-existing plan fixture so scenarios that don't need to test compose can
# use --skip-plan and run faster. Scenario (a) deliberately does NOT use it (it
# must exercise compose to capture the composer argv).
PLAN_FIXTURE="$TEST_DIR/plan-fixture.md"
cat > "$PLAN_FIXTURE" <<'PLAN'
# Skip-Plan Fixture

## Approach

A pre-baked plan so the --skip-plan scenarios bypass the compose phase entirely
and drive only the execute and verify phases. It satisfies the plan heading
regex, the minimum word count, and the structural-line check. The executor stub
appends one harmless line to a tracked file so the run produces a diff for the
verify phase to score, and nothing else happens in this hermetic path.

## Files to Change

- `touched.txt` — the executor stub appends a line.

## Risks

- None identified.
PLAN

# ===========================================================================
# Scenario (a): --preset codex-build → seat argv (exercises compose).
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo a)
claude_log="$TEST_DIR/a_claude.log"; codex_log="$TEST_DIR/a_codex.log"
: > "$claude_log"; : > "$codex_log"
run_dir_before=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1 || true)
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT BOUNCER_MODEL BOUNCER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  bash "$RUNNER" --preset codex-build --workdir "$repo" --timeout 60 -- "preset seat argv probe"
) >"$TEST_DIR/a.out" 2>&1 || true
a_run_dir_k=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1)

a_ok=true
# composer = claude with the `best` model alias resolved (-> claude-opus-4-8) + high effort.
if ! grep -Eq -- '--model claude-opus-4-8' "$claude_log"; then a_ok=false; fi
if ! grep -Eq -- '--effort high' "$claude_log"; then a_ok=false; fi
# v1.5 Phase 1 (A-3): executor = codex PINNED to gpt-5.5 with xhigh effort.
# The pin is the whole point of A-3 — both -c model=gpt-5.5 and the xhigh effort
# must reach the executor codex argv (was previously unpinned: model=CLI config).
if ! grep -Eq -- '-c model=gpt-5.5' "$codex_log"; then a_ok=false; fi
if ! grep -Eq -- '-c model_reasoning_effort=xhigh' "$codex_log"; then a_ok=false; fi
# verifier = claude with max effort.
if ! grep -Eq -- '--effort max' "$claude_log"; then a_ok=false; fi
# v1.5 Phase 1 acceptance: a PRESET run's state.json must carry NO (default) seat
# — every seat (incl. the A-8 bounce counterparty, codex here) is pinned concrete.
if [[ -n "$a_run_dir_k" && "$a_run_dir_k" != "$run_dir_before" ]]; then
  if ! jq -e '.seat_models.bouncer == "codex:gpt-5.5@xhigh"' "$a_run_dir_k/state.json" >/dev/null 2>&1; then a_ok=false; fi
  if ! jq -e '[.seat_models[] | select(contains("(default)"))] | length == 0' "$a_run_dir_k/state.json" >/dev/null 2>&1; then a_ok=false; fi
else
  a_ok=false
fi
if [[ "$a_ok" == true ]]; then
  pass "preset codex-build: composer best->opus/high, executor codex gpt-5.5/xhigh (A-3 pin), verifier claude/max, bouncer codex gpt-5.5/xhigh, no (default) seat"
else
  fail "preset codex-build seat argv mismatch (claude_log + codex_log below)"
  { echo "--- claude argv ---"; cat "$claude_log"; echo "--- codex argv ---"; cat "$codex_log"; } >&2
fi

# ===========================================================================
# Scenario (b): claude-verifier verdict hardening — fenced/prose verdict ends
# up jq-parseable at verdict.json. Reuses the run dir from scenario (a) (same
# preset run already produced a claude verdict through the hardening path).
# ===========================================================================
TOTAL=$((TOTAL + 1))
# Find the run dir the scenario-(a) run created (newest under runs/).
a_run_dir=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1)
b_ok=false
if [[ -n "$a_run_dir" && -f "$a_run_dir/verdict.json" ]]; then
  if jq -e '.verdict == "APPROVED" and (.confidence | type) == "number" and has("summary") and has("issues")' \
       "$a_run_dir/verdict.json" >/dev/null 2>&1; then
    b_ok=true
  fi
fi
if [[ "$b_ok" == true ]]; then
  pass "verdict hardening: prose/fence-wrapped verdict.json is jq-parseable with expected fields"
else
  fail "verdict.json not jq-parseable after hardening (run dir: ${a_run_dir:-<none>})"
  [[ -n "${a_run_dir:-}" && -f "$a_run_dir/verdict.json" ]] && { echo "--- verdict.json ---"; cat "$a_run_dir/verdict.json"; } >&2
fi
# Clean up the runs/ artifacts this gate created so it leaves no side effects.
[[ -n "${a_run_dir:-}" ]] && rm -rf "$a_run_dir"

# ===========================================================================
# Scenario (c): --preset codex-build --verifier codex → verifier is codex
# (last-wins parsing; flags after --preset override it).
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo c)
codex_log="$TEST_DIR/c_codex.log"; claude_log="$TEST_DIR/c_claude.log"
: > "$codex_log"; : > "$claude_log"
run_dir_before=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1 || true)
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  bash "$RUNNER" --preset codex-build --verifier codex --skip-plan --plan "$PLAN_FIXTURE" \
    --workdir "$repo" --timeout 60 -- "preset verifier override probe"
) >"$TEST_DIR/c.out" 2>&1 || true
c_run_dir=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1)
c_ok=false
if [[ -n "$c_run_dir" && "$c_run_dir" != "$run_dir_before" ]]; then
  # state.json seat_models.verifier must report codex; banner Verifier line too.
  if jq -e '.seat_models.verifier | startswith("codex:")' "$c_run_dir/state.json" >/dev/null 2>&1 \
     && grep -Eq '^ Verifier:  codex' "$c_run_dir/run.log"; then
    c_ok=true
  fi
fi
if [[ "$c_ok" == true ]]; then
  pass "preset codex-build --verifier codex: verifier seat is codex (last-wins)"
else
  fail "verifier override did not win over preset (run dir: ${c_run_dir:-<none>})"
  [[ -n "${c_run_dir:-}" ]] && grep -E '^ Verifier:' "$c_run_dir/run.log" >&2 || true
fi
[[ -n "${c_run_dir:-}" && "$c_run_dir" != "$run_dir_before" ]] && rm -rf "$c_run_dir"

# ===========================================================================
# Scenario (d): COMPOSER_EFFORT=low pre-set + preset → composer gets
# --effort low (fill-if-empty: env beats the preset's high default).
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo d)
claude_log="$TEST_DIR/d_claude.log"; codex_log="$TEST_DIR/d_codex.log"
: > "$claude_log"; : > "$codex_log"
run_dir_before=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1 || true)
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export COMPOSER_EFFORT="low"
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  bash "$RUNNER" --preset codex-build --workdir "$repo" --timeout 60 -- "preset composer effort env probe"
) >"$TEST_DIR/d.out" 2>&1 || true
d_run_dir=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1)
if grep -Eq -- '--effort low' "$claude_log" && ! grep -Eq -- '--effort high' "$claude_log"; then
  pass "preset + COMPOSER_EFFORT=low: composer gets --effort low (fill-if-empty env wins)"
else
  fail "COMPOSER_EFFORT env did not beat preset high (claude argv below)"
  cat "$claude_log" >&2
fi
[[ -n "${d_run_dir:-}" && "$d_run_dir" != "$run_dir_before" ]] && rm -rf "$d_run_dir"

# ===========================================================================
# Scenario (e): --preset bogus dies with the unknown-preset message.
# ===========================================================================
TOTAL=$((TOTAL + 1))
e_out=$(bash "$RUNNER" --preset bogus -- "x" 2>&1 || true)
if printf '%s' "$e_out" | grep -Eq 'Unknown preset: bogus \(available: codex-build, claude-build\)'; then
  pass "unknown preset dies with the unknown-preset message and available presets"
else
  fail "unknown preset did not produce the expected die message (got: $e_out)"
fi

# ===========================================================================
# Scenario (f): --help mentions --preset.
# ===========================================================================
TOTAL=$((TOTAL + 1))
help_out=$(bash "$RUNNER" --help 2>/dev/null || true)
if printf '%s' "$help_out" | grep -Eq -- '--preset' \
   && printf '%s' "$help_out" | grep -Eq -- 'codex-build, claude-build' \
   && printf '%s' "$help_out" | grep -Eq -- 'claude-build = Codex plans'; then
  pass "--help mentions --preset and both build presets"
else
  fail "--help does not mention --preset and both build presets"
fi

# ===========================================================================
# Scenario (g): parity guard — a default run (no preset, no new envs) emits no
# --effort (claude) and no model_reasoning_effort (codex) anywhere.
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo g)
claude_log="$TEST_DIR/g_claude.log"; codex_log="$TEST_DIR/g_codex.log"
: > "$claude_log"; : > "$codex_log"
run_dir_before=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1 || true)
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  # Default flavor: codex composes + executes, opus verifies. --verify so a
  # claude verdict path runs too. No preset, no effort knobs.
  bash "$RUNNER" --verify --bounces 0 --skip-plan --plan "$PLAN_FIXTURE" \
    --workdir "$repo" --timeout 60 -- "parity guard probe"
) >"$TEST_DIR/g.out" 2>&1 || true
g_run_dir=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1)
g_ok=true
if grep -Eq -- '--effort ' "$claude_log"; then g_ok=false; fi
if grep -Eq -- 'model_reasoning_effort=' "$codex_log"; then g_ok=false; fi
if [[ "$g_ok" == true ]]; then
  pass "parity guard: default run emits no --effort and no model_reasoning_effort"
else
  fail "parity guard: an effort flag leaked into a default run (logs below)"
  { echo "--- claude argv ---"; cat "$claude_log"; echo "--- codex argv ---"; cat "$codex_log"; } >&2
fi
[[ -n "${g_run_dir:-}" && "$g_run_dir" != "$run_dir_before" ]] && rm -rf "$g_run_dir"

# ===========================================================================
# Scenario (h): cross-agent leak guard — --preset codex-build --verifier codex.
# The preset fills VERIFIER_MODEL=best / VERIFIER_EFFORT=max for its DEFAULT
# claude verifier; --verifier codex flips that seat to codex. Without the guard
# in apply_seat_env, the codex verify argv would carry `-c model=best` (a Claude
# alias codex/ChatGPT rejects with HTTP 400) and `-c model_reasoning_effort=max`
# (off codex's xhigh scale). Assert the codex verify argv carries NEITHER the
# `best` alias NOR its resolved id (claude-opus-4-8), and state.json seat_models
# .verifier reports the fallback (codex:(default)@(default)), not codex:best@max.
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo h)
codex_log="$TEST_DIR/h_codex.log"; claude_log="$TEST_DIR/h_claude.log"
: > "$codex_log"; : > "$claude_log"
run_dir_before=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1 || true)
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  bash "$RUNNER" --preset codex-build --verifier codex --skip-plan --plan "$PLAN_FIXTURE" \
    --workdir "$repo" --timeout 60 -- "preset codex-verifier leak guard probe"
) >"$TEST_DIR/h.out" 2>&1 || true
h_run_dir=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1)
# The verify invocation is the codex argv line carrying --output-schema.
h_verify_argv=$(grep -- '--output-schema' "$codex_log" || true)
h_ok=true
# No leaked claude model (alias `best` or its resolved id) and no off-scale max
# effort in the codex verify argv.
if printf '%s' "$h_verify_argv" | grep -Eq -- '-c model=best'; then h_ok=false; fi
if printf '%s' "$h_verify_argv" | grep -Eq -- '-c model=claude-opus-4-8'; then h_ok=false; fi
if printf '%s' "$h_verify_argv" | grep -Eq -- 'model_reasoning_effort=max'; then h_ok=false; fi
# Sanity: the codex verify invocation actually happened (so the asserts are real).
if [[ -z "$h_verify_argv" ]]; then h_ok=false; fi
# state.json must report the fallback seat, not the leaked fable@max pair.
if [[ -n "$h_run_dir" && "$h_run_dir" != "$run_dir_before" ]]; then
  if ! jq -e '.seat_models.verifier == "codex:(default)@(default)"' "$h_run_dir/state.json" >/dev/null 2>&1; then
    h_ok=false
  fi
else
  h_ok=false
fi
if [[ "$h_ok" == true ]]; then
  pass "preset codex-build --verifier codex: no best/opus or max leak into codex verify argv; seat falls back to default"
else
  fail "cross-agent leak guard failed (run dir: ${h_run_dir:-<none>})"
  { echo "--- codex verify argv ---"; printf '%s\n' "$h_verify_argv"
    [[ -n "${h_run_dir:-}" && -f "$h_run_dir/state.json" ]] && { echo "--- seat_models ---"; jq -c '.seat_models' "$h_run_dir/state.json"; }
  } >&2
fi
[[ -n "${h_run_dir:-}" && "$h_run_dir" != "$run_dir_before" ]] && rm -rf "$h_run_dir"

# ===========================================================================
# Scenario (i): alias resolution. v1.5 Phase 1 (A-4a) moved
# resolve_claude_model_alias into lib/co-evolution.sh (single source), so extract
# it from the LIB, not the runner (sed range + source — bash 3.2 silently sources
# nothing from a process substitution, so use a temp file; same discipline as
# tests/revise-loop-simulation.sh). Assert the `best`/`opus` aliases resolve to
# the current Opus id, `fable` stays mapped for back-compat, and an explicit id
# passes through untouched.
# ===========================================================================
TOTAL=$((TOTAL + 1))
LIB="$REPO_ROOT/lib/co-evolution.sh"
sed -n '/^resolve_claude_model_alias() {/,/^}$/p' "$LIB" > "$TEST_DIR/_alias.sh"
# shellcheck disable=SC1090,SC1091
source "$TEST_DIR/_alias.sh"
i_ok=true
if ! declare -F resolve_claude_model_alias >/dev/null; then i_ok=false; fi
[[ "$(resolve_claude_model_alias best)"  == "claude-opus-4-8" ]] || i_ok=false
[[ "$(resolve_claude_model_alias opus)"  == "claude-opus-4-8" ]] || i_ok=false
[[ "$(resolve_claude_model_alias fable)" == "claude-fable-5"  ]] || i_ok=false
[[ "$(resolve_claude_model_alias claude-opus-4-8[1m])" == "claude-opus-4-8[1m]" ]] || i_ok=false
if [[ "$i_ok" == true ]]; then
  pass "resolve_claude_model_alias: best/opus -> claude-opus-4-8, fable kept, ids passthrough"
else
  fail "alias resolution mismatch (best=$(resolve_claude_model_alias best 2>/dev/null), opus=$(resolve_claude_model_alias opus 2>/dev/null), fable=$(resolve_claude_model_alias fable 2>/dev/null))"
fi

# ===========================================================================
# Scenario (j): --preset claude-build -> seat argv. This is the reverse ladder:
# codex composes/reviews at xhigh with no pinned model; claude executes with
# best resolved to the current Opus id and high effort. Also asserts the
# symmetric leak guard direction: no codex-shaped model reaches the claude
# executor argv.
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo j)
claude_log="$TEST_DIR/j_claude.log"; codex_log="$TEST_DIR/j_codex.log"
: > "$claude_log"; : > "$codex_log"
run_dir_before=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1 || true)
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  bash "$RUNNER" --preset claude-build --workdir "$repo" --timeout 60 -- "preset claude-build seat argv probe"
) >"$TEST_DIR/j.out" 2>&1 || true
j_run_dir=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1)
j_claude_execute_argv=$(grep -- '--permission-mode bypassPermissions' "$claude_log" || true)
j_codex_verify_argv=$(grep -- '--output-schema' "$codex_log" || true)
j_ok=true

# v1.5 Phase 1 (A-3): composer/verifier = codex PINNED to gpt-5.5 at xhigh.
if ! grep -Eq -- '-c model=gpt-5.5' "$codex_log"; then j_ok=false; fi
if ! grep -Eq -- '-c model_reasoning_effort=xhigh' "$codex_log"; then j_ok=false; fi
if [[ -z "$j_codex_verify_argv" ]]; then j_ok=false; fi
if ! printf '%s' "$j_codex_verify_argv" | grep -Eq -- '-c model=gpt-5.5'; then j_ok=false; fi
if ! printf '%s' "$j_codex_verify_argv" | grep -Eq -- '-c model_reasoning_effort=xhigh'; then j_ok=false; fi

# Executor = claude writable argv with best -> claude-opus-4-8 and effort high.
if [[ -z "$j_claude_execute_argv" ]]; then j_ok=false; fi
if ! printf '%s' "$j_claude_execute_argv" | grep -Eq -- '--model claude-opus-4-8'; then j_ok=false; fi
if ! printf '%s' "$j_claude_execute_argv" | grep -Eq -- '--effort high'; then j_ok=false; fi
if printf '%s' "$j_claude_execute_argv" | grep -Eq -- '--model (gpt-|codex)'; then j_ok=false; fi

if [[ -n "$j_run_dir" && "$j_run_dir" != "$run_dir_before" ]]; then
  if ! jq -e '.seat_models.composer == "codex:gpt-5.5@xhigh"
              and .seat_models.executor == "opus:claude-opus-4-8@high"
              and .seat_models.verifier == "codex:gpt-5.5@xhigh"' \
       "$j_run_dir/state.json" >/dev/null 2>&1; then
    j_ok=false
  fi
else
  j_ok=false
fi

if [[ "$j_ok" == true ]]; then
  pass "preset claude-build: composer codex gpt-5.5/xhigh (A-3 pin), executor best->opus/high, verifier codex gpt-5.5/xhigh"
else
  fail "preset claude-build seat argv mismatch (run dir: ${j_run_dir:-<none>})"
  { echo "--- claude execute argv ---"; printf '%s\n' "$j_claude_execute_argv"
    echo "--- codex argv ---"; cat "$codex_log"
    [[ -n "${j_run_dir:-}" && -f "$j_run_dir/state.json" ]] && { echo "--- seat_models ---"; jq -c '.seat_models' "$j_run_dir/state.json"; }
  } >&2
fi
[[ -n "${j_run_dir:-}" && "$j_run_dir" != "$run_dir_before" ]] && rm -rf "$j_run_dir"

# ===========================================================================
# Scenario (k): v1.5 Phase 1 (A-8) bounce counterparty seat. Default flavor
# (composer=codex => reviewer=opus/claude), --bounces 2 --plan-only so the bounce
# reviewer pass (pass 1, claude) runs but execute/verify do not. BOUNCER_MODEL
# must reach that claude reviewer argv, and state.json seat_models.bouncer must
# record it (opus:claude-bouncer-xyz@...). --bounces 2 (explicit int) sets
# AUTO_CONVERGE=false so both passes run unconditionally (no marker early-exit).
# ===========================================================================
TOTAL=$((TOTAL + 1))
repo=$(make_scratch_repo k)
claude_log="$TEST_DIR/k_claude.log"; codex_log="$TEST_DIR/k_codex.log"
: > "$claude_log"; : > "$codex_log"
run_dir_before=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1 || true)
(
  unset CLAUDE_MODEL CLAUDE_EFFORT CODEX_MODEL CODEX_REASONING_EFFORT
  unset COMPOSER_MODEL COMPOSER_EFFORT EXECUTOR_MODEL EXECUTOR_EFFORT VERIFIER_MODEL VERIFIER_EFFORT
  export BOUNCER_MODEL="claude-bouncer-xyz" BOUNCER_EFFORT="high"
  export PATH="$TEST_DIR/bin:$PATH"
  export CLAUDE_ARGV_LOG="$claude_log" CODEX_ARGV_LOG="$codex_log"
  bash "$RUNNER" --bounces 2 --plan-only --workdir "$repo" --timeout 60 -- "bouncer seat probe"
) >"$TEST_DIR/k.out" 2>&1 || true
k_run_dir=$(ls -dt "$REPO_ROOT"/runs/dev-review-* 2>/dev/null | head -1)
k_ok=true
# The bounce reviewer pass (claude) argv must carry BOUNCER_MODEL + effort.
if ! grep -Eq -- '--model claude-bouncer-xyz' "$claude_log"; then k_ok=false; fi
if ! grep -Eq -- '--effort high' "$claude_log"; then k_ok=false; fi
# No leak: the bouncer claude id must not reach any codex argv.
if grep -Eq -- 'claude-bouncer-xyz' "$codex_log"; then k_ok=false; fi
# state.json seat_models.bouncer records the resolved reviewer seat.
if [[ -n "$k_run_dir" && "$k_run_dir" != "$run_dir_before" ]]; then
  if ! jq -e '.seat_models.bouncer == "opus:claude-bouncer-xyz@high"' "$k_run_dir/state.json" >/dev/null 2>&1; then
    k_ok=false
  fi
else
  k_ok=false
fi
if [[ "$k_ok" == true ]]; then
  pass "bounce counterparty seat: BOUNCER_MODEL reaches the reviewer argv; seat_models.bouncer recorded"
else
  fail "bouncer seat propagation failed (run dir: ${k_run_dir:-<none>})"
  { echo "--- claude argv ---"; cat "$claude_log"
    [[ -n "${k_run_dir:-}" && -f "$k_run_dir/state.json" ]] && { echo "--- seat_models ---"; jq -c '.seat_models' "$k_run_dir/state.json"; }
  } >&2
fi
[[ -n "${k_run_dir:-}" && "$k_run_dir" != "$run_dir_before" ]] && rm -rf "$k_run_dir"

# --- summary ----------------------------------------------------------------
passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
