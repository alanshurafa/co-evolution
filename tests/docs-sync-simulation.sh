#!/usr/bin/env bash
# tests/docs-sync-simulation.sh
# Hermetic sync-token gate for v1.5 Phase 5/Feature 6: pin the build preset
# triples so the runner code and the user-facing docs cannot drift.
#
# The `codex-build` preset is defined in ONE place (dev-review/codex/dev-review.sh
# apply_preset) but DESCRIBED in two skill docs (skills/codex-build/SKILL.md and
# skills/dev-review/SKILL.md). The `claude-build` preset is defined beside it and
# described in dev-review/codex/claude-build.md. If someone edits the seats in one
# and forgets the others, the docs lie. This gate greps the load-bearing seat
# tokens out of each file and asserts they all agree on the same triples:
#
#   composer  = best (currently Opus), effort high
#   executor  = Codex, effort xhigh, model pinned to gpt-5.5 (A-3)
#   verifier  = best (currently Opus), effort max
#   bounces   = 2
#
#   claude-build:
#   composer  = Codex, effort xhigh, model pinned to gpt-5.5 (A-3)
#   executor  = best (currently Opus), effort high
#   verifier  = Codex, effort xhigh, model pinned to gpt-5.5 (A-3)
#   bounces   = 2
#
# Pattern: pure-grep assertions over the real files (no agents, no stubs). Each
# scenario is a (file, required-token) pair. This is a structural invariant test,
# the same flavour as the frozen-surface grep checks in classifier-simulation.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RUNNER="$REPO_ROOT/dev-review/codex/dev-review.sh"
CODEX_BUILD_SKILL="$REPO_ROOT/skills/codex-build/SKILL.md"
CLAUDE_BUILD_DOC="$REPO_ROOT/dev-review/codex/claude-build.md"
DEV_REVIEW_SKILL="$REPO_ROOT/skills/dev-review/SKILL.md"

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# assert_grep <label> <file> <ERE-pattern>
# One scenario: the pattern must match somewhere in the file.
assert_grep() {
  local label="$1" file="$2" pat="$3"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$file" ]]; then
    fail "$label — file missing: $file"
    return
  fi
  if grep -Eiq -- "$pat" "$file"; then
    pass "$label"
  else
    fail "$label — pattern not found in $(basename "$file"): /$pat/"
  fi
}

# assert_not_grep <label> <file> <ERE-pattern>
# One scenario: the pattern must NOT match (used for the "executor model unpinned"
# invariant — no `-c model=` is pinned for the executor seat in the preset).
assert_not_grep() {
  local label="$1" file="$2" pat="$3"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$file" ]]; then
    fail "$label — file missing: $file"
    return
  fi
  if grep -Eq -- "$pat" "$file"; then
    fail "$label — pattern unexpectedly found in $(basename "$file"): /$pat/"
  else
    pass "$label"
  fi
}

# assert_text_grep <label> <text> <ERE-pattern>
# One scenario: the pattern must match inside an already-extracted text block.
assert_text_grep() {
  local label="$1" text="$2" pat="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$text" | grep -Eiq -- "$pat"; then
    pass "$label"
  else
    fail "$label — pattern not found in extracted preset arm: /$pat/"
  fi
}

# assert_text_not_grep <label> <text> <ERE-pattern>
# One scenario: the pattern must NOT match inside an already-extracted text block.
assert_text_not_grep() {
  local label="$1" text="$2" pat="$3"
  TOTAL=$((TOTAL + 1))
  if printf '%s\n' "$text" | grep -Eq -- "$pat"; then
    fail "$label — pattern unexpectedly found in extracted preset arm: /$pat/"
  else
    pass "$label"
  fi
}

# ===========================================================================
# Group 1: the runner's apply_preset() is the single source of truth.
# These pin the literal knob assignments so a doc edit can be diffed against
# the code, and a code edit that changes the triple breaks this gate too.
# ===========================================================================
CODEX_BUILD_ARM=$(sed -n '/codex-build).*build with codex/,/^[[:space:]]*;;/p' "$RUNNER")
CLAUDE_BUILD_ARM=$(sed -n '/claude-build).*build with claude/,/^[[:space:]]*;;/p' "$RUNNER")

assert_text_grep "runner codex-build: composer opus / executor codex / verifier opus" \
  "$CODEX_BUILD_ARM" 'COMPOSER="opus"; EXECUTOR="codex"; VERIFIER_OVERRIDE="opus"'
assert_text_grep "runner codex-build: composer best seat (COMPOSER_MODEL:=best)" \
  "$CODEX_BUILD_ARM" 'COMPOSER_MODEL:=best'
assert_text_grep "runner codex-build: composer effort high (COMPOSER_EFFORT:=high)" \
  "$CODEX_BUILD_ARM" 'COMPOSER_EFFORT:=high'
assert_text_grep "runner codex-build: verifier best seat (VERIFIER_MODEL:=best)" \
  "$CODEX_BUILD_ARM" 'VERIFIER_MODEL:=best'
assert_text_grep "runner codex-build: verifier effort max (VERIFIER_EFFORT:=max)" \
  "$CODEX_BUILD_ARM" 'VERIFIER_EFFORT:=max'
assert_text_grep "runner codex-build: executor effort xhigh (EXECUTOR_EFFORT:=xhigh)" \
  "$CODEX_BUILD_ARM" 'EXECUTOR_EFFORT:=xhigh'
assert_text_grep "runner codex-build: bounces pinned to 2 (BOUNCES=2)" \
  "$CODEX_BUILD_ARM" 'BOUNCES=2'
# v1.5 Phase 1 (A-3): the codex executor seat is now MODEL-PINNED to gpt-5.5.
assert_text_grep "runner codex-build: executor model pinned to gpt-5.5 (EXECUTOR_MODEL:=gpt-5.5)" \
  "$CODEX_BUILD_ARM" 'EXECUTOR_MODEL:=gpt-5.5'

assert_text_grep "runner claude-build: composer codex / executor opus / verifier codex" \
  "$CLAUDE_BUILD_ARM" 'COMPOSER="codex"; EXECUTOR="opus"; VERIFIER_OVERRIDE="codex"'
assert_text_grep "runner claude-build: executor best seat (EXECUTOR_MODEL:=best)" \
  "$CLAUDE_BUILD_ARM" 'EXECUTOR_MODEL:=best'
assert_text_grep "runner claude-build: executor effort high (EXECUTOR_EFFORT:=high)" \
  "$CLAUDE_BUILD_ARM" 'EXECUTOR_EFFORT:=high'
assert_text_grep "runner claude-build: composer effort xhigh (COMPOSER_EFFORT:=xhigh)" \
  "$CLAUDE_BUILD_ARM" 'COMPOSER_EFFORT:=xhigh'
assert_text_grep "runner claude-build: verifier effort xhigh (VERIFIER_EFFORT:=xhigh)" \
  "$CLAUDE_BUILD_ARM" 'VERIFIER_EFFORT:=xhigh'
assert_text_grep "runner claude-build: bounces pinned to 2 (BOUNCES=2)" \
  "$CLAUDE_BUILD_ARM" 'BOUNCES=2'
# v1.5 Phase 1 (A-3): the codex composer + verifier seats are now pinned to gpt-5.5.
assert_text_grep "runner claude-build: composer model pinned to gpt-5.5 (COMPOSER_MODEL:=gpt-5.5)" \
  "$CLAUDE_BUILD_ARM" 'COMPOSER_MODEL:=gpt-5.5'
assert_text_grep "runner claude-build: verifier model pinned to gpt-5.5 (VERIFIER_MODEL:=gpt-5.5)" \
  "$CLAUDE_BUILD_ARM" 'VERIFIER_MODEL:=gpt-5.5'

# ===========================================================================
# Group 2: skills/codex-build/SKILL.md must describe the SAME triple.
# Tokens kept loose enough to survive prose rewording but tight enough to catch
# a wrong seat (e.g. opus instead of Fable, high instead of xhigh on executor).
# ===========================================================================
assert_grep "codex-build skill: composer Opus at high" \
  "$CODEX_BUILD_SKILL" 'composer = Opus \(high\)'
assert_grep "codex-build skill: executor Codex at xhigh" \
  "$CODEX_BUILD_SKILL" 'executor = Codex \(xhigh'
assert_grep "codex-build skill: verifier Opus at max" \
  "$CODEX_BUILD_SKILL" 'verifier = Opus \(max\)'
assert_grep "codex-build skill: bounces 2" \
  "$CODEX_BUILD_SKILL" 'bounces 2'
# v1.5 Phase 1 (A-3): executor codex model is now pinned to gpt-5.5 (was CLI config).
assert_grep "codex-build skill: executor model pinned to gpt-5.5" \
  "$CODEX_BUILD_SKILL" 'executor = Codex \(xhigh, model.*pinned to .?gpt-5\.5'

# ===========================================================================
# Group 3: dev-review/codex/claude-build.md must describe the SAME reverse
# triple and its synchronous/hard-auth orchestration contract.
# ===========================================================================
assert_grep "claude-build doc: composer Codex at xhigh" \
  "$CLAUDE_BUILD_DOC" 'composer = Codex \(xhigh'
assert_grep "claude-build doc: executor Opus at best/high" \
  "$CLAUDE_BUILD_DOC" 'executor = Opus \(best/high\)'
assert_grep "claude-build doc: verifier Codex at xhigh" \
  "$CLAUDE_BUILD_DOC" 'verifier = Codex \(xhigh'
# v1.5 Phase 1 (A-3): codex composer + verifier models are now pinned to gpt-5.5.
assert_grep "claude-build doc: composer codex model pinned to gpt-5.5" \
  "$CLAUDE_BUILD_DOC" 'composer = Codex \(xhigh, model pinned to .?gpt-5\.5'
assert_grep "claude-build doc: verifier codex model pinned to gpt-5.5" \
  "$CLAUDE_BUILD_DOC" 'verifier = Codex \(xhigh, model pinned to .?gpt-5\.5'
assert_grep "claude-build doc: bounces 2" \
  "$CLAUDE_BUILD_DOC" 'bounces 2'
assert_grep "claude-build doc: revise-loop 1" \
  "$CLAUDE_BUILD_DOC" 'revise-loop 1'
assert_grep "claude-build doc: hard stop on missing claude auth" \
  "$CLAUDE_BUILD_DOC" 'HARD STOP'
assert_grep "claude-build doc: blocking run contract" \
  "$CLAUDE_BUILD_DOC" 'RUN \(BLOCKING\)'
assert_grep "claude-build doc: future detached mode design-only" \
  "$CLAUDE_BUILD_DOC" 'Future: detached mode \(design only\)'

# ===========================================================================
# Group 4: skills/dev-review/SKILL.md cross-references the codex-build preset
# triple.
# ===========================================================================
assert_grep "dev-review skill: Opus plans at high" \
  "$DEV_REVIEW_SKILL" 'Opus plans at .?high'
assert_grep "dev-review skill: Codex executes at xhigh" \
  "$DEV_REVIEW_SKILL" 'Codex executes at .?xhigh'
assert_grep "dev-review skill: reviews at max" \
  "$DEV_REVIEW_SKILL" 'reviews at .?max'
assert_grep "dev-review skill: bounces 2" \
  "$DEV_REVIEW_SKILL" 'bounces .?2'
assert_grep "dev-review skill: names --preset codex-build" \
  "$DEV_REVIEW_SKILL" '--preset codex-build'

# --- summary ----------------------------------------------------------------
passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
