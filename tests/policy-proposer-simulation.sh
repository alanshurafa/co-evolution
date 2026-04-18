#!/usr/bin/env bash
# tests/policy-proposer-simulation.sh
# Phase 6 PEL-03: Hermetic simulation of lab/pel/proposer/policy/ behavior.
#
# Scenarios (8 SC-4 scenarios per CONTEXT.md D-19):
#   A: Flavor=bug-catcher            — valid delta, passes bounds, applies via yq
#   B: Flavor=faster-converger       — same
#   C: Flavor=blind-spot-surfacer    — max_passes nudge higher per D-16
#   D: Flavor=general                — arbitrate_threshold nudge
#   E: Out-of-bounds delta           — bounds.jq rejects with exit 4
#   F: Non-enumerated knob           — bounds.jq rejects with exit 5
#   G: Malformed JSON delta          — validate_delta_response rejects with exit 3
#   H: Missing/invalid env           — proposer.sh rejects with exit 1
#                                      (sub-cases: missing PEL_FEEDBACK,
#                                       missing PEL_FLAVOR, shell-meta model,
#                                       path traversal)
#
# Final line: "8/8 scenarios passed" (matches Phase 2/3/4 phase-gate convention).
# Exit 0 iff all 8 scenarios pass; exit 1 otherwise.
#
# Dependencies: bash, jq, yq. No claude CLI, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

# TEST_DIR must be INSIDE REPO_ROOT so proposer.sh's T-06-07 containment
# check accepts fixture/test-policy paths that live under it. Using /tmp
# (mktemp's default) would make every fixture "outside repo root" and the
# proposer would die exit 1 before any scenario's true failure mode is
# exercised. Create under tests/ so the gitignore-friendly prefix ".sim-"
# makes it obvious this is scratch space.
TEST_DIR=$(mktemp -d -p "$REPO_ROOT/tests" ".sim-policy-XXXXXX")
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# Stub claude CLI (PATH-injected). Echoes whatever canned JSON the test
# placed in $POLICY_STUB_FILE. Writes a fingerprint marker per call so
# adversarial scenarios can assert invocation state.
# ---------------------------------------------------------------------------

mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
# PATH-injected stub for hermetic policy-proposer simulation.
if [[ -n "${POLICY_STUB_MARKER:-}" ]]; then
  printf 'called\n' >> "$POLICY_STUB_MARKER"
fi
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (stub)"
  exit 0
fi
cat > /dev/null   # drain stdin
if [[ -n "${POLICY_STUB_EXIT:-}" ]]; then
  exit "$POLICY_STUB_EXIT"
fi
if [[ -z "${POLICY_STUB_FILE:-}" || ! -f "${POLICY_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: POLICY_STUB_FILE not set or file missing" >&2
  exit 99
fi
cat "$POLICY_STUB_FILE"
STUB
chmod +x "$TEST_DIR/bin/claude"

# Helper: write a canned D-10 delta stub response.
#   write_stub <dest-file> <key> <old_json> <new_json> <rationale> <flavor> <policy_path>
# Handles numeric, string, and boolean values via --argjson.
#
# MSYS_NO_PATHCONV=1 is required on Git Bash for Windows: without it, MSYS
# rewrites any argv that LOOKS like a Unix path (e.g. `/c/Users/...`) into
# DOS form (`C:/Users/...`) before handing it to the native jq binary.
# proposer.sh's adapter then sees the rewritten path in the stub's
# .policy_path field but the Unix-form $PEL_POLICY_PATH env var, and the
# verbatim-match check in validate_delta_response fails. Disabling path
# conversion for the jq call keeps both sides in the same form.
write_stub() {
  local dest="$1" key="$2" old_json="$3" new_json="$4" rationale="$5" flavor="$6" policy_path="$7"
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq -n \
    --arg key "$key" \
    --argjson old "$old_json" \
    --argjson new "$new_json" \
    --arg rationale "$rationale" \
    --arg flavor "$flavor" \
    --arg policy_path "$policy_path" \
    '{mutations: [{key: $key, old: $old, new: $new}], rationale: $rationale, flavor: $flavor, policy_path: $policy_path}' > "$dest"
}

# Test policy.yaml copy (used by scenarios A-D for yq-apply verification).
# D-11 discipline: simulations never touch the real committed policy.yaml.
TEST_POLICY="$TEST_DIR/policy-test-copy.yaml"
cp "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml" "$TEST_POLICY"

# ---------------------------------------------------------------------------
# Scenario A: Flavor=bug-catcher (retry_cap nudge lower per D-16)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub="$TEST_DIR/stub-A.json"
  write_stub "$stub" "retry_cap" "3" "1" \
    "bug-catcher bias: lower retry_cap to fail fast on latent issues" \
    "bug-catcher" "$TEST_POLICY"

  # Reset test copy to committed defaults before the run.
  cp "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml" "$TEST_POLICY"

  result=$(POLICY_STUB_FILE="$stub" \
           POLICY_STUB_MARKER="$TEST_DIR/marker-A" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/retry-failure.json" \
           PEL_POLICY_PATH="$TEST_POLICY" \
           PEL_FLAVOR=bug-catcher \
           bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" "hint" 2>/dev/null)

  echo "$result" | jq -e '.mutations[0].key == "retry_cap"' >/dev/null \
    || { echo "A: .mutations[0].key mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.mutations[0].new == 1' >/dev/null \
    || { echo "A: .mutations[0].new mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.flavor == "bug-catcher"' >/dev/null \
    || { echo "A: .flavor mismatch; got: $result" >&2; exit 1; }

  # Sanity: the proposer did NOT mutate the test copy (D-11).
  new_value=$(yq ".retry_cap" "$TEST_POLICY")
  test "$new_value" = "3" \
    || { echo "A: proposer mutated test policy (D-11 violation); expected 3, got $new_value" >&2; exit 1; }

  # Apply delta to the test copy via yq and verify the new value lands.
  yq -i ".retry_cap = 1" "$TEST_POLICY"
  applied=$(yq ".retry_cap" "$TEST_POLICY")
  test "$applied" = "1" \
    || { echo "A: yq-apply failed; expected 1, got $applied" >&2; exit 1; }
) && pass "Scenario A (flavor=bug-catcher delta applies via yq)" \
  || fail "Scenario A (bug-catcher)"

# ---------------------------------------------------------------------------
# Scenario B: Flavor=faster-converger (max_passes nudge lower per D-16)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub="$TEST_DIR/stub-B.json"
  write_stub "$stub" "max_passes" "4" "2" \
    "faster-converger bias: lower max_passes to exit earlier" \
    "faster-converger" "$TEST_POLICY"

  cp "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml" "$TEST_POLICY"

  result=$(POLICY_STUB_FILE="$stub" \
           POLICY_STUB_MARKER="$TEST_DIR/marker-B" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/convergence-slow.json" \
           PEL_POLICY_PATH="$TEST_POLICY" \
           PEL_FLAVOR=faster-converger \
           bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" "hint" 2>/dev/null)

  echo "$result" | jq -e '.mutations[0].key == "max_passes"' >/dev/null \
    || { echo "B: .mutations[0].key mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.mutations[0].new == 2' >/dev/null \
    || { echo "B: .mutations[0].new mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.flavor == "faster-converger"' >/dev/null \
    || { echo "B: .flavor mismatch; got: $result" >&2; exit 1; }

  new_value=$(yq ".max_passes" "$TEST_POLICY")
  test "$new_value" = "4" \
    || { echo "B: proposer mutated test policy (D-11 violation); expected 4, got $new_value" >&2; exit 1; }

  yq -i ".max_passes = 2" "$TEST_POLICY"
  applied=$(yq ".max_passes" "$TEST_POLICY")
  test "$applied" = "2" \
    || { echo "B: yq-apply failed; expected 2, got $applied" >&2; exit 1; }
) && pass "Scenario B (flavor=faster-converger delta applies via yq)" \
  || fail "Scenario B (faster-converger)"

# ---------------------------------------------------------------------------
# Scenario C: Flavor=blind-spot-surfacer (max_passes nudge HIGHER per D-16)
# ---------------------------------------------------------------------------
# Plan-issue W-1: the plan describes Scenario C ambiguously (marker_semantics
# strict→strict is a no-op; max_passes new=8 is the load-bearing mutation).
# Implemented as max_passes old=4 new=8 per D-16 blind-spot bias + orchestrator
# guidance.
TOTAL=$((TOTAL + 1))
(
  stub="$TEST_DIR/stub-C.json"
  write_stub "$stub" "max_passes" "4" "8" \
    "blind-spot-surfacer bias: higher max_passes to allocate more budget for unknown failure modes" \
    "blind-spot-surfacer" "$TEST_POLICY"

  cp "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml" "$TEST_POLICY"

  result=$(POLICY_STUB_FILE="$stub" \
           POLICY_STUB_MARKER="$TEST_DIR/marker-C" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/blind-spot-missed.json" \
           PEL_POLICY_PATH="$TEST_POLICY" \
           PEL_FLAVOR=blind-spot-surfacer \
           bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" "hint" 2>/dev/null)

  echo "$result" | jq -e '.mutations[0].key == "max_passes"' >/dev/null \
    || { echo "C: .mutations[0].key mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.mutations[0].new == 8' >/dev/null \
    || { echo "C: .mutations[0].new mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.flavor == "blind-spot-surfacer"' >/dev/null \
    || { echo "C: .flavor mismatch; got: $result" >&2; exit 1; }

  new_value=$(yq ".max_passes" "$TEST_POLICY")
  test "$new_value" = "4" \
    || { echo "C: proposer mutated test policy (D-11 violation); expected 4, got $new_value" >&2; exit 1; }

  yq -i ".max_passes = 8" "$TEST_POLICY"
  applied=$(yq ".max_passes" "$TEST_POLICY")
  test "$applied" = "8" \
    || { echo "C: yq-apply failed; expected 8, got $applied" >&2; exit 1; }
) && pass "Scenario C (flavor=blind-spot-surfacer delta applies via yq)" \
  || fail "Scenario C (blind-spot-surfacer)"

# ---------------------------------------------------------------------------
# Scenario D: Flavor=general (arbitrate_threshold nudge)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub="$TEST_DIR/stub-D.json"
  write_stub "$stub" "arbitrate_threshold" "0.7" "0.6" \
    "general bias: balanced nudge of a single knob based on cost pressure" \
    "general" "$TEST_POLICY"

  cp "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml" "$TEST_POLICY"

  result=$(POLICY_STUB_FILE="$stub" \
           POLICY_STUB_MARKER="$TEST_DIR/marker-D" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/cost-overrun.json" \
           PEL_POLICY_PATH="$TEST_POLICY" \
           PEL_FLAVOR=general \
           bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" "hint" 2>/dev/null)

  echo "$result" | jq -e '.mutations[0].key == "arbitrate_threshold"' >/dev/null \
    || { echo "D: .mutations[0].key mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.mutations[0].new == 0.6' >/dev/null \
    || { echo "D: .mutations[0].new mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.flavor == "general"' >/dev/null \
    || { echo "D: .flavor mismatch; got: $result" >&2; exit 1; }

  new_value=$(yq ".arbitrate_threshold" "$TEST_POLICY")
  test "$new_value" = "0.7" \
    || { echo "D: proposer mutated test policy (D-11 violation); expected 0.7, got $new_value" >&2; exit 1; }

  yq -i ".arbitrate_threshold = 0.6" "$TEST_POLICY"
  applied=$(yq ".arbitrate_threshold" "$TEST_POLICY")
  test "$applied" = "0.6" \
    || { echo "D: yq-apply failed; expected 0.6, got $applied" >&2; exit 1; }
) && pass "Scenario D (flavor=general delta applies via yq)" \
  || fail "Scenario D (general)"

# ---------------------------------------------------------------------------
# Scenario E: Out-of-bounds delta → bounds.jq halt_error(4) → exit 4
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub="$TEST_DIR/stub-E.json"
  # retry_cap=999 violates [0, 10] bound → bounds.jq halt_error(4)
  write_stub "$stub" "retry_cap" "3" "999" \
    "adversarial oob test" "bug-catcher" "$TEST_POLICY"

  cp "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml" "$TEST_POLICY"

  rc=0
  POLICY_STUB_FILE="$stub" \
  POLICY_STUB_MARKER="$TEST_DIR/marker-E" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/retry-failure.json" \
  PEL_POLICY_PATH="$TEST_POLICY" \
  PEL_FLAVOR=bug-catcher \
  bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" >/dev/null 2>"$TEST_DIR/stderr-E" || rc=$?

  test "$rc" = "4" \
    || { echo "E: expected exit 4 (bounds violation); got $rc, stderr: $(cat "$TEST_DIR/stderr-E")" >&2; exit 1; }
  grep -qE "bounds" "$TEST_DIR/stderr-E" \
    || { echo "E: stderr missing 'bounds' diagnostic; got: $(cat "$TEST_DIR/stderr-E")" >&2; exit 1; }
) && pass "Scenario E (out-of-bounds delta → exit 4 via bounds.jq)" \
  || fail "Scenario E (bounds)"

# ---------------------------------------------------------------------------
# Scenario F: Non-enumerated knob → bounds.jq halt_error(5) → exit 5
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub="$TEST_DIR/stub-F.json"
  # key=secret_flag is not in D-03 allowlist → bounds.jq halt_error(5)
  write_stub "$stub" "secret_flag" "null" "\"evil\"" \
    "adversarial non-enumerated test" "general" "$TEST_POLICY"

  cp "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml" "$TEST_POLICY"

  rc=0
  POLICY_STUB_FILE="$stub" \
  POLICY_STUB_MARKER="$TEST_DIR/marker-F" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/retry-failure.json" \
  PEL_POLICY_PATH="$TEST_POLICY" \
  PEL_FLAVOR=general \
  bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" >/dev/null 2>"$TEST_DIR/stderr-F" || rc=$?

  test "$rc" = "5" \
    || { echo "F: expected exit 5 (non-enumerated knob); got $rc, stderr: $(cat "$TEST_DIR/stderr-F")" >&2; exit 1; }
  grep -qE "non-enumerated" "$TEST_DIR/stderr-F" \
    || { echo "F: stderr missing 'non-enumerated' diagnostic; got: $(cat "$TEST_DIR/stderr-F")" >&2; exit 1; }
) && pass "Scenario F (non-enumerated knob → exit 5 via bounds.jq)" \
  || fail "Scenario F (non-enumerated)"

# ---------------------------------------------------------------------------
# Scenario G: Malformed JSON delta → validate_delta_response exit 3
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub="$TEST_DIR/stub-G.json"
  # Response missing the required "mutations" field → exit 3
  echo '{"rationale": "missing mutations field", "flavor": "general"}' > "$stub"

  cp "$REPO_ROOT/lab/pel/proposer/policy/policy.yaml" "$TEST_POLICY"

  rc=0
  POLICY_STUB_FILE="$stub" \
  POLICY_STUB_MARKER="$TEST_DIR/marker-G" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/retry-failure.json" \
  PEL_POLICY_PATH="$TEST_POLICY" \
  PEL_FLAVOR=general \
  bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" >/dev/null 2>"$TEST_DIR/stderr-G" || rc=$?

  test "$rc" = "3" \
    || { echo "G: expected exit 3 (malformed response); got $rc, stderr: $(cat "$TEST_DIR/stderr-G")" >&2; exit 1; }
) && pass "Scenario G (malformed JSON delta → exit 3 via validate_delta_response)" \
  || fail "Scenario G (malformed)"

# ---------------------------------------------------------------------------
# Scenario H: Missing/invalid env validation → exit 1 (composite, 4 sub-tests)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  # H1: missing PEL_FEEDBACK entirely.
  rc=0
  env -u PEL_FEEDBACK -u PEL_POLICY_PATH -u PEL_FLAVOR PATH="$TEST_DIR/bin:$PATH" \
  PEL_POLICY_PATH="$TEST_POLICY" \
  PEL_FLAVOR=general \
  bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" >/dev/null 2>"$TEST_DIR/stderr-H1" || rc=$?
  test "$rc" = "1" \
    || { echo "H1: missing PEL_FEEDBACK expected exit 1; got $rc" >&2; exit 1; }
  grep -qE "PEL_FEEDBACK is required" "$TEST_DIR/stderr-H1" \
    || { echo "H1: missing PEL_FEEDBACK error message; got: $(cat "$TEST_DIR/stderr-H1")" >&2; exit 1; }

  # H2: missing PEL_FLAVOR.
  rc=0
  env -u PEL_FEEDBACK -u PEL_POLICY_PATH -u PEL_FLAVOR PATH="$TEST_DIR/bin:$PATH" \
  PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/retry-failure.json" \
  PEL_POLICY_PATH="$TEST_POLICY" \
  bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" >/dev/null 2>"$TEST_DIR/stderr-H2" || rc=$?
  test "$rc" = "1" \
    || { echo "H2: missing PEL_FLAVOR expected exit 1; got $rc" >&2; exit 1; }
  grep -qE "PEL_FLAVOR is required" "$TEST_DIR/stderr-H2" \
    || { echo "H2: missing PEL_FLAVOR error message; got: $(cat "$TEST_DIR/stderr-H2")" >&2; exit 1; }

  # H3: shell-meta POLICY_PROPOSER_MODEL (T-06-03 defense).
  stub="$TEST_DIR/stub-H3.json"
  write_stub "$stub" "retry_cap" "3" "5" "unused" "general" "$TEST_POLICY"
  rc=0
  POLICY_STUB_FILE="$stub" \
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_FEEDBACK="$REPO_ROOT/tests/fixtures/policy-feedback/retry-failure.json" \
  PEL_POLICY_PATH="$TEST_POLICY" \
  PEL_FLAVOR=general \
  POLICY_PROPOSER_MODEL="haiku; rm -rf /" \
  bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" >/dev/null 2>"$TEST_DIR/stderr-H3" || rc=$?
  test "$rc" = "1" \
    || { echo "H3: bad POLICY_PROPOSER_MODEL expected exit 1; got $rc" >&2; exit 1; }
  grep -qE "invalid POLICY_PROPOSER_MODEL" "$TEST_DIR/stderr-H3" \
    || { echo "H3: missing POLICY_PROPOSER_MODEL error; got: $(cat "$TEST_DIR/stderr-H3")" >&2; exit 1; }

  # H4: path traversal on PEL_FEEDBACK (T-06-07 defense).
  rc=0
  PATH="$TEST_DIR/bin:$PATH" \
  PEL_FEEDBACK="/etc/passwd" \
  PEL_POLICY_PATH="$TEST_POLICY" \
  PEL_FLAVOR=general \
  bash "$REPO_ROOT/lab/pel/proposer/policy/proposer.sh" >/dev/null 2>"$TEST_DIR/stderr-H4" || rc=$?
  test "$rc" = "1" \
    || { echo "H4: path-traversal PEL_FEEDBACK expected exit 1; got $rc" >&2; exit 1; }
  # On Windows Git Bash, /etc/passwd may not exist at all; either "not readable"
  # OR "outside repo root" is a valid rejection literal.
  grep -qE "(not readable|outside repo root)" "$TEST_DIR/stderr-H4" \
    || { echo "H4: expected readable/traversal error; got: $(cat "$TEST_DIR/stderr-H4")" >&2; exit 1; }
) && pass "Scenario H (env/model/path validation — 4 sub-cases all exit 1)" \
  || fail "Scenario H (validation)"

# ---------------------------------------------------------------------------
# Summary footer (single counter — all 8 scenarios are SC-mandated per D-19;
# no bonus split needed).
# ---------------------------------------------------------------------------

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
