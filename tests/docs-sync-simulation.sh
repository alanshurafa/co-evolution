#!/usr/bin/env bash
# tests/docs-sync-simulation.sh
# Hermetic sync-token gate for v1.5 Phase 5: pin the codex-build preset triple
# so the runner code and the user-facing docs cannot drift.
#
# The `codex-build` preset is defined in ONE place (dev-review/codex/dev-review.sh
# apply_preset) but DESCRIBED in two skill docs (skills/codex-build/SKILL.md and
# skills/dev-review/SKILL.md). If someone edits the seats in one and forgets the
# others, the docs lie. This gate greps the load-bearing seat tokens out of each
# file and asserts they all agree on the same triple:
#
#   composer  = Fable, effort high
#   executor  = Codex, effort xhigh (model unpinned — CLI config rules)
#   verifier  = Fable, effort max
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

# ===========================================================================
# Group 1: the runner's apply_preset() is the single source of truth.
# These pin the literal knob assignments so a doc edit can be diffed against
# the code, and a code edit that changes the triple breaks this gate too.
# ===========================================================================
assert_grep "runner: composer Fable seat (COMPOSER_MODEL:=fable)" \
  "$RUNNER" 'COMPOSER_MODEL:=fable'
assert_grep "runner: composer effort high (COMPOSER_EFFORT:=high)" \
  "$RUNNER" 'COMPOSER_EFFORT:=high'
assert_grep "runner: verifier Fable seat (VERIFIER_MODEL:=fable)" \
  "$RUNNER" 'VERIFIER_MODEL:=fable'
assert_grep "runner: verifier effort max (VERIFIER_EFFORT:=max)" \
  "$RUNNER" 'VERIFIER_EFFORT:=max'
assert_grep "runner: executor effort xhigh (EXECUTOR_EFFORT:=xhigh)" \
  "$RUNNER" 'EXECUTOR_EFFORT:=xhigh'
assert_grep "runner: bounces pinned to 2 (BOUNCES=2)" \
  "$RUNNER" 'BOUNCES=2'
# Executor model is deliberately unpinned: apply_preset must NOT set EXECUTOR_MODEL
# (the CLI's ~/.codex/config.toml model wins). Pin that invariant.
TOTAL=$((TOTAL + 1))
if sed -n '/^apply_preset()/,/^}/p' "$RUNNER" | grep -Eq 'EXECUTOR_MODEL'; then
  fail "runner: executor model unexpectedly pinned in apply_preset (must stay unpinned)"
else
  pass "runner: executor model unpinned in apply_preset (CLI config rules)"
fi

# ===========================================================================
# Group 2: skills/codex-build/SKILL.md must describe the SAME triple.
# Tokens kept loose enough to survive prose rewording but tight enough to catch
# a wrong seat (e.g. opus instead of Fable, high instead of xhigh on executor).
# ===========================================================================
assert_grep "codex-build skill: composer Fable at high" \
  "$CODEX_BUILD_SKILL" 'composer = Fable \(high\)'
assert_grep "codex-build skill: executor Codex at xhigh" \
  "$CODEX_BUILD_SKILL" 'executor = Codex \(xhigh'
assert_grep "codex-build skill: verifier Fable at max" \
  "$CODEX_BUILD_SKILL" 'verifier = Fable \(max\)'
assert_grep "codex-build skill: bounces 2" \
  "$CODEX_BUILD_SKILL" 'bounces 2'
assert_grep "codex-build skill: executor model unpinned (CLI config note)" \
  "$CODEX_BUILD_SKILL" "left to the CLI's config"

# ===========================================================================
# Group 3: skills/dev-review/SKILL.md cross-references the same preset triple.
# ===========================================================================
assert_grep "dev-review skill: Fable plans at high" \
  "$DEV_REVIEW_SKILL" 'Fable plans at .?high'
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
