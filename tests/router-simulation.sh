#!/usr/bin/env bash
# tests/router-simulation.sh
# Hermetic simulation gate for lab/pel/router/.
#
# Scenarios (5 primary — all hermetic, no network, no real claude):
#   A: NORMAL pick — template-tier small file → router emits complexity=NORMAL,
#      model=sonnet
#   B: COMPLEX pick — code-tier any size → router emits complexity=COMPLEX,
#      model=opus, thinking_budget=harder
#   C: --complexity user override — PEL_COMPLEXITY_OVERRIDE=COMPLEX skips
#      Haiku call; canonical JSON includes inputs.user_override="COMPLEX"
#   D: --no-adaptive bypass — caller (co-evolve-bouncer.sh + pr-emitter.sh)
#      respects PEL_NO_ADAPTIVE=1 by skipping router entirely (proxy test:
#      router.sh exits cleanly when invoked under PEL_NO_ADAPTIVE=1; in
#      production the caller never invokes it at all)
#   E: Router-failure fallback — Haiku stub forced to fail; router emits
#      canonical JSON with complexity="COMPLEX" + rationale="router-failure-
#      fallback" and exit 0
#
# Pattern: PATH-injected claude stub (mirrors tests/classifier-simulation.sh).

set -uo pipefail  # NOT -e: per-scenario subshells handle their own exit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d -t router-sim-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0

pass() {
  printf "PASS: %s\n" "$1"
}

fail() {
  printf "FAIL: %s\n" "$1" >&2
  FAILURES=$((FAILURES + 1))
}

# Build the PATH-injected claude stub.
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
# Hermetic claude stub for router-simulation.sh.
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (router-stub)"
  exit 0
fi
cat > /dev/null  # consume stdin
if [[ -n "${ROUTER_STUB_EXIT:-}" ]]; then
  exit "$ROUTER_STUB_EXIT"
fi
if [[ -z "${ROUTER_STUB_FILE:-}" || ! -f "${ROUTER_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: ROUTER_STUB_FILE not set or file missing" >&2
  exit 99
fi
cat "$ROUTER_STUB_FILE"
STUB
chmod +x "$TEST_DIR/bin/claude"

# Helper: write canned Haiku response.
write_stub() {
  local dest="$1" complexity="$2" rationale="$3"
  jq -n --arg complexity "$complexity" --arg rationale "$rationale" \
    '{complexity: $complexity, rationale: $rationale}' > "$dest"
}

# Tiny target files used by scenarios (need real files so target_size_bytes
# resolves correctly).
mkdir -p "$TEST_DIR/targets"
printf "small template" > "$TEST_DIR/targets/small.md"  # ~14 bytes
printf "%.0sX" {1..3000} > "$TEST_DIR/targets/big.md"   # 3000 bytes
printf "#!/bin/bash\necho hi\n" > "$TEST_DIR/targets/code.sh"

echo "Router simulation starting..."

# ---------------------------------------------------------------------------
# Scenario A: NORMAL pick (template tier, small target → bias NORMAL)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-A.json"
  write_stub "$stub_file" "NORMAL" "small template tweak"

  result=$(ROUTER_STUB_FILE="$stub_file" \
           PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/small.md" \
           PEL_TIER="template" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null)

  echo "$result" | jq -e '.complexity == "NORMAL"' >/dev/null \
    || { echo "A: .complexity expected NORMAL; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "sonnet"' >/dev/null \
    || { echo "A: .model expected sonnet; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.fallback_model == "sonnet"' >/dev/null \
    || { echo "A: .fallback_model expected sonnet; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.thinking_budget == null' >/dev/null \
    || { echo "A: .thinking_budget expected null; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.pel_tier == "template"' >/dev/null \
    || { echo "A: .inputs.pel_tier mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.user_override == null' >/dev/null \
    || { echo "A: .inputs.user_override expected null; got: $result" >&2; exit 1; }
) && pass "Scenario A (NORMAL pick — template tier small file)" \
  || fail "Scenario A (NORMAL pick)"

# ---------------------------------------------------------------------------
# Scenario B: COMPLEX pick (code tier — always escalate)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-B.json"
  write_stub "$stub_file" "COMPLEX" "code-tier mutation"

  result=$(ROUTER_STUB_FILE="$stub_file" \
           PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/code.sh" \
           PEL_TIER="code" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null)

  echo "$result" | jq -e '.complexity == "COMPLEX"' >/dev/null \
    || { echo "B: .complexity expected COMPLEX; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "opus"' >/dev/null \
    || { echo "B: .model expected opus; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.thinking_budget == "harder"' >/dev/null \
    || { echo "B: .thinking_budget expected harder; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.pel_tier == "code"' >/dev/null \
    || { echo "B: .inputs.pel_tier mismatch; got: $result" >&2; exit 1; }
) && pass "Scenario B (COMPLEX pick — code tier)" \
  || fail "Scenario B (COMPLEX pick)"

# ---------------------------------------------------------------------------
# Scenario C: --complexity user override (skip Haiku entirely)
# ---------------------------------------------------------------------------
# Marker file proves Haiku was NOT called.
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-C.json"
  write_stub "$stub_file" "NORMAL" "should not be called"
  marker_file="$TEST_DIR/marker-C"

  # Override the stub to write a marker on invocation, so we can assert it
  # was NOT called.
  cat > "$TEST_DIR/bin/claude" <<STUB
#!/usr/bin/env bash
echo "called" > "$marker_file"
[[ "\$*" == *"--version"* ]] && { echo "claude 1.0.0 (stub)"; exit 0; }
cat > /dev/null
cat "$stub_file"
STUB
  chmod +x "$TEST_DIR/bin/claude"

  result=$(PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/code.sh" \
           PEL_TIER="template" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           PEL_COMPLEXITY_OVERRIDE="COMPLEX" \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null)

  [[ -f "$marker_file" ]] && { echo "C: Haiku was called despite override" >&2; exit 1; }
  echo "$result" | jq -e '.complexity == "COMPLEX"' >/dev/null \
    || { echo "C: .complexity expected COMPLEX (from override); got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.user_override == "COMPLEX"' >/dev/null \
    || { echo "C: .inputs.user_override expected COMPLEX; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "opus"' >/dev/null \
    || { echo "C: .model expected opus (from override); got: $result" >&2; exit 1; }
) && pass "Scenario C (--complexity COMPLEX override skips Haiku)" \
  || fail "Scenario C (override)"

# Restore the standard stub for remaining scenarios.
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (router-stub)"
  exit 0
fi
cat > /dev/null
if [[ -n "${ROUTER_STUB_EXIT:-}" ]]; then
  exit "$ROUTER_STUB_EXIT"
fi
if [[ -z "${ROUTER_STUB_FILE:-}" || ! -f "${ROUTER_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: ROUTER_STUB_FILE not set or file missing" >&2
  exit 99
fi
cat "$ROUTER_STUB_FILE"
STUB
chmod +x "$TEST_DIR/bin/claude"

# ---------------------------------------------------------------------------
# Scenario D: PEL_NO_ADAPTIVE=1 bypass — router exits 0 cleanly without
# emitting JSON. (Caller is responsible for not invoking the router at all
# when PEL_NO_ADAPTIVE=1; this scenario documents that the router itself
# also short-circuits gracefully if accidentally called.)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-D.json"
  write_stub "$stub_file" "NORMAL" "should not run"

  exit_code=0
  result=$(ROUTER_STUB_FILE="$stub_file" \
           PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/small.md" \
           PEL_TIER="template" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           PEL_NO_ADAPTIVE=1 \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null) || exit_code=$?

  [[ "$exit_code" -eq 0 ]] || { echo "D: expected exit 0, got $exit_code" >&2; exit 1; }
  [[ -z "$result" ]] || { echo "D: expected empty stdout under PEL_NO_ADAPTIVE; got: $result" >&2; exit 1; }
) && pass "Scenario D (PEL_NO_ADAPTIVE=1 bypass — clean no-op)" \
  || fail "Scenario D (no-adaptive bypass)"

# ---------------------------------------------------------------------------
# Scenario E: Router-failure fallback — Haiku call fails, router emits
# safe-side COMPLEX default and exits 0
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-E.json"
  write_stub "$stub_file" "NORMAL" "should not be reached"

  result=$(ROUTER_STUB_FILE="$stub_file" \
           ROUTER_STUB_EXIT=1 \
           PATH="$TEST_DIR/bin:$PATH" \
           TARGET="$TEST_DIR/targets/small.md" \
           PEL_TIER="template" \
           PEL_FLAVOR="bug-catcher" \
           PEL_FEEDBACK="$TEST_DIR/dummy-feedback.json" \
           bash "$REPO_ROOT/lab/pel/router/router.sh" 2>/dev/null)

  echo "$result" | jq -e '.complexity == "COMPLEX"' >/dev/null \
    || { echo "E: .complexity expected COMPLEX (safe-side); got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.rationale == "router-failure-fallback"' >/dev/null \
    || { echo "E: .rationale expected router-failure-fallback; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "opus"' >/dev/null \
    || { echo "E: .model expected opus (safe-side); got: $result" >&2; exit 1; }
) && pass "Scenario E (router-failure fallback — safe-side COMPLEX)" \
  || fail "Scenario E (router-failure fallback)"

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
