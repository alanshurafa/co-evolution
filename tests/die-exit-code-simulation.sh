#!/usr/bin/env bash
# tests/die-exit-code-simulation.sh
# Hermetic unit gate for die() exit-code propagation (audit finding F-6).
#
# die() historically ignored its optional second argument and always exited 1,
# silently collapsing ~50 call sites that pass meaningful codes (2,3,5,6,8,9,10)
# down to 1. After the fix die() must `exit "${2:-1}"`: honor an explicit code,
# default to 1 when none is given. Both definitions are covered — the canonical
# one in lib/co-evolution.sh and the guarded fallback in
# evals/lib/co-evolution-evals.sh — so the two cannot drift.
#
# Pattern: each case runs in a pristine `bash -c` that sources one lib and calls
# die, so no function definition leaks between cases and the
# sourced-in-production path is exercised faithfully.

set -uo pipefail  # NOT -e: cases capture their own exit codes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LIB="$REPO_ROOT/lib/co-evolution.sh"
EVALS_LIB="$REPO_ROOT/evals/lib/co-evolution-evals.sh"

TOTAL=0
FAILURES=0

pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# run_die <lib-path> <die-call> -> prints the exit code die produced.
run_die() {
  local lib="$1" call="$2"
  bash -c "source \"$lib\"; $call" >/dev/null 2>&1
  printf '%s' "$?"
}

# check <description> <lib-path> <die-call> <expected-code>
check() {
  TOTAL=$((TOTAL + 1))
  local got
  got="$(run_die "$2" "$3")"
  if [[ "$got" == "$4" ]]; then
    pass "$1 (exit $got)"
  else
    fail "$1: expected exit $4, got $got"
  fi
}

check "lib die: no code defaults to 1"   "$LIB"       'die "boom"'    1
check "lib die: explicit 2 honored"      "$LIB"       'die "boom" 2'  2
check "lib die: explicit 5 honored"      "$LIB"       'die "boom" 5'  5
check "lib die: explicit 10 honored"     "$LIB"       'die "boom" 10' 10
check "evals die: no code defaults to 1" "$EVALS_LIB" 'die "boom"'    1
check "evals die: explicit 3 honored"    "$EVALS_LIB" 'die "boom" 3'  3

# die() must still log the message before exiting (fix preserves logging).
TOTAL=$((TOTAL + 1))
msg_out="$(bash -c "source \"$LIB\"; die \"distinct-marker-xyz\" 2" 2>&1 || true)"
if [[ "$msg_out" == *"ERROR: distinct-marker-xyz"* ]]; then
  pass "lib die: logs ERROR message before exit"
else
  fail "lib die: expected ERROR message in output, got: $msg_out"
fi

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
