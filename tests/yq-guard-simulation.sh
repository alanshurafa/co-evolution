#!/usr/bin/env bash
# tests/yq-guard-simulation.sh
# Hermetic gate for the mikefarah/yq guard (audit finding F-1).
#
# The project depends on mikefarah/Go yq v4 syntax. The Debian/Ubuntu
# `apt install yq` ships the incompatible python yq (kislyuk), and every guard
# site used to do only a presence check (`command -v yq`), so the wrong flavor
# passed and failed later with an opaque jq-ish error. The fix adds a
# version-string discriminator (mikefarah prints "mikefarah" in --version) via a
# shared require_mikefarah_yq helper in lib/, called from ensure_yq, and inlined
# at the two PEL sites that cannot source lib (self-containment invariants).
#
# Pattern: PATH-injected yq stubs (mikefarah-flavored vs python-flavored).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/lib/co-evolution.sh"
EVALS_LIB="$REPO_ROOT/evals/lib/co-evolution-evals.sh"
PROPOSER="$REPO_ROOT/lab/pel/proposer/policy/proposer.sh"
PR_EMITTER="$REPO_ROOT/lab/pel/pr-emitter/pr-emitter.sh"

TEST_DIR="$(mktemp -d -t yq-guard-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# mikefarah-flavored yq stub: --version mentions mikefarah.
mkdir -p "$TEST_DIR/mikefarah"
cat > "$TEST_DIR/mikefarah/yq" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then
  echo "yq (https://github.com/mikefarah/yq/) version v4.44.3"
  exit 0
fi
exit 0
STUB
chmod +x "$TEST_DIR/mikefarah/yq"

# python-flavored yq stub: --version does NOT mention mikefarah.
mkdir -p "$TEST_DIR/python"
cat > "$TEST_DIR/python/yq" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then
  echo "yq 3.4.3"
  exit 0
fi
exit 0
STUB
chmod +x "$TEST_DIR/python/yq"

# --- Scenario 1: helper accepts mikefarah yq ---
TOTAL=$((TOTAL + 1))
out="$( export PATH="$TEST_DIR/mikefarah:$PATH"; source "$LIB" >/dev/null 2>&1; require_mikefarah_yq 2>&1 )"; rc=$?
if [[ $rc -eq 0 ]]; then
  pass "require_mikefarah_yq accepts mikefarah yq"
else
  fail "mikefarah accept: expected rc 0, got $rc (out: $out)"
fi

# --- Scenario 2: helper rejects python yq with an actionable message ---
TOTAL=$((TOTAL + 1))
out="$( export PATH="$TEST_DIR/python:$PATH"; source "$LIB" >/dev/null 2>&1; require_mikefarah_yq 2>&1 )"; rc=$?
if [[ $rc -ne 0 && "$out" == *"mikefarah/yq"* ]]; then
  pass "require_mikefarah_yq rejects python yq (rc=$rc)"
else
  fail "python reject: expected non-zero + mikefarah message, got rc=$rc out: $out"
fi

# --- Scenario 3: ensure_yq routes through the shared helper ---
TOTAL=$((TOTAL + 1))
if grep -q 'require_mikefarah_yq' "$EVALS_LIB"; then
  pass "evals ensure_yq routes through require_mikefarah_yq"
else
  fail "evals/lib ensure_yq does not call require_mikefarah_yq"
fi

# --- Scenario 4: policy-proposer inline guard does the version check ---
TOTAL=$((TOTAL + 1))
if grep -q 'yq --version' "$PROPOSER"; then
  pass "policy proposer inline guard checks yq --version"
else
  fail "policy proposer guard still presence-only (no 'yq --version')"
fi

# --- Scenario 5: pr-emitter inline guard does the version check ---
TOTAL=$((TOTAL + 1))
if grep -q 'yq --version' "$PR_EMITTER"; then
  pass "pr-emitter inline guard checks yq --version"
else
  fail "pr-emitter guard still presence-only (no 'yq --version')"
fi

# --- Scenario 6: policy-proposer rejects python yq end-to-end (require_tools) ---
TOTAL=$((TOTAL + 1))
out="$( export PATH="$TEST_DIR/python:$PATH"; bash "$PROPOSER" </dev/null 2>&1 )"; rc=$?
if [[ $rc -ne 0 && "$out" == *"mikefarah/yq"* ]]; then
  pass "policy proposer rejects python yq end-to-end (rc=$rc)"
else
  fail "policy-proposer e2e: expected non-zero + mikefarah, got rc=$rc out(head): $(printf '%s' "$out" | head -3)"
fi

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
