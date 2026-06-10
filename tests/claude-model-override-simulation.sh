#!/usr/bin/env bash
# tests/claude-model-override-simulation.sh
# Hermetic gate for the Claude model override (audit finding F-5a).
#
# invoke_claude() previously hardcoded "--model claude-opus-4-6" in two places.
# After the fix it must read $CLAUDE_MODEL (default claude-opus-4-6), so the
# model is overridable via the CLAUDE_MODEL env var and the --claude-model flag
# without changing the default. Precedence: --claude-model > CLAUDE_MODEL > default.
#
# Coverage:
#   1. default model is the unchanged claude-opus-4-6
#   2. CLAUDE_MODEL env override reaches the claude invocation
#   3. co-evolve-bouncer.sh wires --claude-model to CLAUDE_MODEL
#   4. --help documents --claude-model
#
# Pattern: a PATH-injected claude stub records the --model value it receives.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/lib/co-evolution.sh"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"

TEST_DIR="$(mktemp -d -t claude-model-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# claude stub: record the value following --model, then emit a document body.
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then echo "claude 1.0.0 (model-stub)"; exit 0; fi
model=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--model" ]]; then model="${2:-}"; shift 2; continue; fi
  shift
done
[[ -n "${MODEL_MARKER:-}" ]] && printf '%s' "$model" > "$MODEL_MARKER"
cat > /dev/null  # consume stdin
echo "Stub document body with enough plain words to clear any downstream size check."
STUB
chmod +x "$TEST_DIR/bin/claude"

# --- Scenario 1: default model is claude-opus-4-6 ---
TOTAL=$((TOTAL + 1))
marker="$TEST_DIR/m_default"
(
  unset CLAUDE_MODEL
  export MODEL_MARKER="$marker"
  export PATH="$TEST_DIR/bin:$PATH"
  source "$LIB"
  invoke_claude /dev/null "$TEST_DIR/out1" "$TEST_DIR/err1" false
) >/dev/null 2>&1
got="$(cat "$marker" 2>/dev/null || true)"
if [[ "$got" == "claude-opus-4-6" ]]; then
  pass "default model is claude-opus-4-6 (got '$got')"
else
  fail "default: expected claude-opus-4-6, got '$got'"
fi

# --- Scenario 2: CLAUDE_MODEL env override reaches the invocation ---
TOTAL=$((TOTAL + 1))
marker="$TEST_DIR/m_env"
(
  export CLAUDE_MODEL="claude-test-env-xyz"
  export MODEL_MARKER="$marker"
  export PATH="$TEST_DIR/bin:$PATH"
  source "$LIB"
  invoke_claude /dev/null "$TEST_DIR/out2" "$TEST_DIR/err2" false
) >/dev/null 2>&1
got="$(cat "$marker" 2>/dev/null || true)"
if [[ "$got" == "claude-test-env-xyz" ]]; then
  pass "CLAUDE_MODEL env override honored (got '$got')"
else
  fail "env override: expected claude-test-env-xyz, got '$got'"
fi

# --- Scenario 3: runner wires --claude-model to CLAUDE_MODEL ---
TOTAL=$((TOTAL + 1))
if grep -Eq -- '--claude-model\)' "$BOUNCER" && grep -Fq 'CLAUDE_MODEL="$2"' "$BOUNCER"; then
  pass "co-evolve-bouncer.sh wires --claude-model to CLAUDE_MODEL"
else
  fail "co-evolve-bouncer.sh missing --claude-model -> CLAUDE_MODEL wiring"
fi

# --- Scenario 4: --help documents --claude-model ---
TOTAL=$((TOTAL + 1))
help_out="$(bash "$BOUNCER" --help 2>/dev/null || true)"
if [[ "$help_out" == *"--claude-model"* ]]; then
  pass "--help documents --claude-model"
else
  fail "--help does not document --claude-model"
fi

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
