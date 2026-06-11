#!/usr/bin/env bash
# tests/protocol-parity-simulation.sh — v1.3 Phase 6 (audit A-01).
#
# bounce-protocol.md exists in several places because each runner ships a
# self-contained template set. The canonical copy is
# agent-bouncer/templates/bounce-protocol.md; every other copy must be
# byte-identical to it. This is the same drift-pinning pattern as the F-2
# review-verdict schema test: editing one copy without the others fails CI.
#
# To change the protocol: edit the canonical copy, then `cp` it over the
# others (listed below), and update BOUNCE-PROTOCOL.md (the human spec) if
# the semantics changed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CANONICAL="$REPO_ROOT/agent-bouncer/templates/bounce-protocol.md"

# Every runtime copy a runner actually reads, plus the PEL template-tier
# fixture (a mutation TARGET seeded from canonical — if canonical moves,
# the fixture must be re-seeded deliberately).
COPIES=(
  "$REPO_ROOT/skills/dev-review/templates/bounce-protocol.md"
  "$REPO_ROOT/runners/codex-ps/templates/bounce-protocol.md"
  "$REPO_ROOT/tests/fixtures/templates/bounce-protocol.md"
)

TOTAL=0
PASSED=0
pass() { printf 'PASS: %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; }

TOTAL=$((TOTAL + 1))
if [[ -f "$CANONICAL" && -s "$CANONICAL" ]]; then
  pass "canonical copy exists ($CANONICAL)"
else
  fail "canonical copy missing: $CANONICAL"
fi

for copy in "${COPIES[@]}"; do
  TOTAL=$((TOTAL + 1))
  rel=${copy#"$REPO_ROOT/"}
  if [[ ! -f "$copy" ]]; then
    fail "$rel: missing"
  elif cmp -s "$CANONICAL" "$copy"; then
    pass "$rel: byte-identical to canonical"
  else
    fail "$rel: DRIFTED from canonical — sync it: cp agent-bouncer/templates/bounce-protocol.md $rel"
  fi
done

# The human-facing spec must at least agree on the marker vocabulary.
TOTAL=$((TOTAL + 1))
if grep -q '\[CONTESTED\]' "$REPO_ROOT/BOUNCE-PROTOCOL.md" && grep -q '\[CLARIFY\]' "$REPO_ROOT/BOUNCE-PROTOCOL.md"; then
  pass "BOUNCE-PROTOCOL.md (human spec) covers both marker types"
else
  fail "BOUNCE-PROTOCOL.md no longer mentions both marker types"
fi

printf '%d/%d scenarios passed' "$PASSED" "$TOTAL"
if (( PASSED != TOTAL )); then
  printf ' (%d failed)\n' "$((TOTAL - PASSED))"
  exit 1
fi
printf '\n'
