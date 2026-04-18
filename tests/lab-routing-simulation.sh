#!/usr/bin/env bash
# tests/lab-routing-simulation.sh
# Phase 3 LAB-01: Hermetic simulation of --lab <mode> routing on both runners.
#
# Scenarios (all hermetic, no network, no Codex/Claude CLIs — only the
# arg-parser path of each runner is exercised):
#
#   A: Byte-parity (L-03 + SC-3) — `--help` on co-evolve-bouncer.sh retains
#      all v1.1 flags (--bounces, --agents) AND newly contains --lab row.
#      Proves Task 2 added --lab non-destructively.
#   B: Unknown-mode fail-fast on co-evolve-bouncer.sh (L-04) — emits
#      "unknown --lab mode: nonexistent-mode" + "Available:" + non-zero exit.
#   C: Unknown-mode fail-fast on dev-review/codex/dev-review.sh (L-04) —
#      identical semantics to Scenario B.
#   D: Mode-token validation (T-03-02-01) — both runners reject "../etc"
#      and "foo;rm" with "invalid --lab mode" message.
#
# Final line on success: `4/4 scenarios passed` (matches Phase 2
# evals/tests/scorer-verification.sh style).
#
# Exit 0 iff all 4 scenarios pass; exit 1 otherwise.

set -euo pipefail

TEST_DIR=$(mktemp -d -t lab-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# Scenario A: Byte-parity invariant (L-03 + SC-3)
# ---------------------------------------------------------------------------
# --help exits 0 before any arg-parser side effects, so it is a clean
# surface for "does --lab presence perturb the default code path" check.
# We spot-check pre-existing v1.1 flags (--bounces, --agents) remain in
# the usage heredoc AND confirm --lab was added to it.
# ---------------------------------------------------------------------------

TOTAL=$((TOTAL + 1))
(
  out_no_lab=$(bash "$REPO_ROOT/co-evolve-bouncer.sh" --help 2>&1)

  # Must contain the new --lab row (Task 2 byte-parity-preserving addition)
  echo "$out_no_lab" | grep -qF -- "--lab" \
    || { echo "A: --help missing --lab row (Task 2 regression)" >&2; exit 1; }

  # Must retain pre-existing v1.1 flags (byte-parity spot-check)
  echo "$out_no_lab" | grep -qF -- "--bounces" \
    || { echo "A: --help missing --bounces (v1.1 parity regression)" >&2; exit 1; }
  echo "$out_no_lab" | grep -qF -- "--agents" \
    || { echo "A: --help missing --agents (v1.1 parity regression)" >&2; exit 1; }

  # Core banner must be intact.
  echo "$out_no_lab" | grep -qF "Usage:" \
    || { echo "A: --help missing Usage header" >&2; exit 1; }
) && pass "Scenario A (byte-parity: --help intact, --lab added non-destructively)" \
  || fail "Scenario A (byte-parity)"

# ---------------------------------------------------------------------------
# Scenario B: Unknown-mode fail-fast on co-evolve-bouncer.sh (L-04)
# ---------------------------------------------------------------------------
# Invoke with a mode that has no lab/<mode>/entry.sh. Runner must die with
# the exact error substring AND an "Available:" listing.
# ---------------------------------------------------------------------------

TOTAL=$((TOTAL + 1))
(
  out=$(bash "$REPO_ROOT/co-evolve-bouncer.sh" --lab nonexistent-mode "trivial task" 2>&1 || true)

  echo "$out" | grep -qF "unknown --lab mode: nonexistent-mode" \
    || { echo "B: missing unknown-mode error; got: $out" >&2; exit 1; }
  echo "$out" | grep -qF "Available:" \
    || { echo "B: missing Available: listing; got: $out" >&2; exit 1; }
) && pass "Scenario B (co-evolve-bouncer.sh unknown-mode fail-fast)" \
  || fail "Scenario B (unknown mode on co-evolve)"

# ---------------------------------------------------------------------------
# Scenario C: Unknown-mode fail-fast on dev-review/codex/dev-review.sh (L-04)
# ---------------------------------------------------------------------------
# Same assertion as B but on the secondary runner. Proves both runners share
# identical --lab semantics via shared lib/co-evolution.sh helpers.
# ---------------------------------------------------------------------------

TOTAL=$((TOTAL + 1))
(
  out=$(bash "$REPO_ROOT/dev-review/codex/dev-review.sh" --lab nonexistent-mode "trivial task" 2>&1 || true)

  echo "$out" | grep -qF "unknown --lab mode: nonexistent-mode" \
    || { echo "C: missing unknown-mode error; got: $out" >&2; exit 1; }
  echo "$out" | grep -qF "Available:" \
    || { echo "C: missing Available: listing; got: $out" >&2; exit 1; }
) && pass "Scenario C (dev-review.sh unknown-mode fail-fast)" \
  || fail "Scenario C (unknown mode on dev-review)"

# ---------------------------------------------------------------------------
# Scenario D: Mode-token validation (T-03-02-01)
# ---------------------------------------------------------------------------
# Exercise both runners with path-traversal ("../etc") and shell-meta
# ("foo;rm") mode tokens. validate_lab_mode must reject before any fs op.
# This is the defense-in-depth injection-defense boundary.
# ---------------------------------------------------------------------------

TOTAL=$((TOTAL + 1))
(
  for runner in "$REPO_ROOT/co-evolve-bouncer.sh" "$REPO_ROOT/dev-review/codex/dev-review.sh"; do
    for bad_mode in "../etc" "foo;rm"; do
      out=$(bash "$runner" --lab "$bad_mode" "task" 2>&1 || true)
      echo "$out" | grep -qF "invalid --lab mode" \
        || { echo "D: $runner accepted bad mode $bad_mode; got: $out" >&2; exit 1; }
    done
  done
) && pass "Scenario D (mode-token validation rejects path-traversal + shell-meta)" \
  || fail "Scenario D (mode-token validation)"

# ---------------------------------------------------------------------------
# Summary footer
# ---------------------------------------------------------------------------

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
