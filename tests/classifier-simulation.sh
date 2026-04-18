#!/usr/bin/env bash
# tests/classifier-simulation.sh
# Phase 4 PEL-01: Hermetic simulation of lab/pel/classifier/ behavior.
#
# Scenarios (6 primary + 2 bonus — all hermetic, no network, no real claude
# CLI — claude is stubbed via PATH injection):
#
#   A: Flavor=bug-catcher           — stub returns bug-catcher JSON; classifier
#                                     re-emits canonical D-08 schema.
#   B: Flavor=faster-converger      — stub returns faster-converger JSON.
#   C: Flavor=blind-spot-surfacer   — stub returns blind-spot-surfacer JSON.
#   D: Flavor=general               — stub returns general JSON.
#   E: PEL_FLAVOR_OVERRIDE bypass   — override skips Haiku entirely.
#                                     Proof-by-fingerprint: stub writes a
#                                     marker file on each invocation; scenario
#                                     asserts the marker DOES NOT exist.
#   F: Frozen-surface invariant     — no file under lab/pel/classifier/**
#                                     sources anything outside that boundary
#                                     (SC-4 / D-11 anchor for Phase 7).
#
# Bonus scenarios (regression coverage for Plan 01 mitigations):
#   G: Input validation (T-04-04)   — bogus PEL_FLAVOR_OVERRIDE and bogus
#                                     CLASSIFIER_MODEL both die exit 1.
#   H: Warn-don't-die (D-04)        — garbage PEL_BOUNCE_STEP + PEL_PHASE_TYPE
#                                     produce WARNING on stderr and still
#                                     emit valid D-08 JSON via stub.
#
# Final line on success: "6/6 scenarios passed" (matches Phase 2+3 style).
# Exit 0 iff all 6 primary scenarios pass; exit 1 otherwise.
#
# Dependencies: bash, jq. No claude CLI, no network.

set -euo pipefail

TEST_DIR=$(mktemp -d -t classifier-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# Bonus counters — scenarios G and H harden Plan 01's T-04-04 + D-04
# mitigations with end-to-end coverage but are NOT part of SC-5's 6-scenario
# gate. They count separately so the final footer stays "6/6 scenarios
# passed" per v1.2 phase-gate convention (matches Phase 2 "13/13" and
# Phase 3 "4/4"); the bonus summary prints on its own line.
BONUS_FAILURES=0
BONUS_TOTAL=0
bonus_fail() { echo "FAIL: $1" >&2; BONUS_FAILURES=$((BONUS_FAILURES + 1)); }
bonus_pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# Stub claude CLI (PATH-injected). Echoes whatever canned JSON the test
# placed in $CLASSIFIER_STUB_FILE. Writes a fingerprint marker per call so
# Scenario E can prove the override path skipped Haiku.
#
# Pattern adapted from 04-PATTERNS.md §tests/classifier-simulation.sh and
# Phase 2's evals/tests/fake-runner.sh PATH-injection precedent.
# ---------------------------------------------------------------------------

mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
# PATH-injected stub for hermetic classifier simulation.
#
# Fingerprint: record every invocation so tests can assert bypass invariants.
if [[ -n "${CLASSIFIER_STUB_MARKER:-}" ]]; then
  printf 'called\n' >> "$CLASSIFIER_STUB_MARKER"
fi

# --version handling so any future require_claude_cli probe path works.
# (On Git Bash Windows, the adapter uses `command -v claude` which doesn't
# invoke the binary; on WSL it shells `cmd.exe /c claude --version`.)
if [[ "$*" == *"--version"* ]]; then
  echo "claude 1.0.0 (stub)"
  exit 0
fi

# Consume stdin so the upstream prompt-file redirect doesn't leak.
cat > /dev/null

# Optional forced-exit path for negative scenarios.
if [[ -n "${CLASSIFIER_STUB_EXIT:-}" ]]; then
  exit "$CLASSIFIER_STUB_EXIT"
fi

# Emit the canned JSON response.
if [[ -z "${CLASSIFIER_STUB_FILE:-}" || ! -f "${CLASSIFIER_STUB_FILE:-}" ]]; then
  echo "STUB ERROR: CLASSIFIER_STUB_FILE not set or file missing" >&2
  exit 99
fi
cat "$CLASSIFIER_STUB_FILE"
STUB
chmod +x "$TEST_DIR/bin/claude"

# Helper: write a canned stub response JSON.
#   write_stub <dest-file> <flavor> <rationale>
write_stub() {
  local dest="$1" flavor="$2" rationale="$3"
  jq -n --arg flavor "$flavor" --arg rationale "$rationale" \
    '{flavor: $flavor, rationale: $rationale}' > "$dest"
}

# ---------------------------------------------------------------------------
# Scenario A: Flavor = bug-catcher (via Haiku path, stubbed)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-bug-catcher.json"
  write_stub "$stub_file" "bug-catcher" "eval-known defects dominate"

  result=$(CLASSIFIER_STUB_FILE="$stub_file" \
           CLASSIFIER_STUB_MARKER="$TEST_DIR/marker-A" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_BOUNCE_STEP=bounce \
           PEL_PHASE_TYPE=verification \
           bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" \
             "fix off-by-one in marker counting" 2>/dev/null)

  echo "$result" | jq -e '.flavor == "bug-catcher"' >/dev/null \
    || { echo "A: .flavor mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.override == false' >/dev/null \
    || { echo "A: .override must be false on Haiku path; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.task == "fix off-by-one in marker counting"' >/dev/null \
    || { echo "A: .inputs.task mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.bounce_step == "bounce"' >/dev/null \
    || { echo "A: .inputs.bounce_step mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.phase_type == "verification"' >/dev/null \
    || { echo "A: .inputs.phase_type mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.model == "claude-haiku-4-5-20251001"' >/dev/null \
    || { echo "A: .model mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.rationale == "eval-known defects dominate"' >/dev/null \
    || { echo "A: .rationale mismatch; got: $result" >&2; exit 1; }
) && pass "Scenario A (flavor=bug-catcher via Haiku path)" \
  || fail "Scenario A (bug-catcher)"

# ---------------------------------------------------------------------------
# Scenario B: Flavor = faster-converger
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-faster-converger.json"
  write_stub "$stub_file" "faster-converger" "latency and cost pressure"

  result=$(CLASSIFIER_STUB_FILE="$stub_file" \
           CLASSIFIER_STUB_MARKER="$TEST_DIR/marker-B" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_BOUNCE_STEP=execute \
           PEL_PHASE_TYPE=implementation \
           bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" \
             "reduce bounce latency on small tasks" 2>/dev/null)

  echo "$result" | jq -e '.flavor == "faster-converger"' >/dev/null \
    || { echo "B: .flavor mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.override == false' >/dev/null \
    || { echo "B: .override must be false on Haiku path; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.task == "reduce bounce latency on small tasks"' >/dev/null \
    || { echo "B: .inputs.task mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.bounce_step == "execute"' >/dev/null \
    || { echo "B: .inputs.bounce_step mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.phase_type == "implementation"' >/dev/null \
    || { echo "B: .inputs.phase_type mismatch; got: $result" >&2; exit 1; }
) && pass "Scenario B (flavor=faster-converger via Haiku path)" \
  || fail "Scenario B (faster-converger)"

# ---------------------------------------------------------------------------
# Scenario C: Flavor = blind-spot-surfacer
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-blind-spot-surfacer.json"
  write_stub "$stub_file" "blind-spot-surfacer" "untested edge cases dominate"

  result=$(CLASSIFIER_STUB_FILE="$stub_file" \
           CLASSIFIER_STUB_MARKER="$TEST_DIR/marker-C" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_BOUNCE_STEP=compose \
           PEL_PHASE_TYPE=scoping \
           bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" \
             "explore protocol edge cases evals don't know yet" 2>/dev/null)

  echo "$result" | jq -e '.flavor == "blind-spot-surfacer"' >/dev/null \
    || { echo "C: .flavor mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.override == false' >/dev/null \
    || { echo "C: .override must be false on Haiku path; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.task == "explore protocol edge cases evals don'"'"'t know yet"' >/dev/null \
    || { echo "C: .inputs.task mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.bounce_step == "compose"' >/dev/null \
    || { echo "C: .inputs.bounce_step mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.phase_type == "scoping"' >/dev/null \
    || { echo "C: .inputs.phase_type mismatch; got: $result" >&2; exit 1; }
) && pass "Scenario C (flavor=blind-spot-surfacer via Haiku path)" \
  || fail "Scenario C (blind-spot-surfacer)"

# ---------------------------------------------------------------------------
# Scenario D: Flavor = general
# ---------------------------------------------------------------------------
# Env vars here exercise the "unexpected → unknown" degradation path by
# setting values that ARE legal tokens, confirming the non-degradation
# baseline (D-04 warn path is exercised in Scenario H).
TOTAL=$((TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-general.json"
  write_stub "$stub_file" "general" "no single axis dominates"

  result=$(CLASSIFIER_STUB_FILE="$stub_file" \
           CLASSIFIER_STUB_MARKER="$TEST_DIR/marker-D" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_BOUNCE_STEP=unknown \
           PEL_PHASE_TYPE=unknown \
           bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" \
             "balanced mutation proposal" 2>/dev/null)

  echo "$result" | jq -e '.flavor == "general"' >/dev/null \
    || { echo "D: .flavor mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.override == false' >/dev/null \
    || { echo "D: .override must be false on Haiku path; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.task == "balanced mutation proposal"' >/dev/null \
    || { echo "D: .inputs.task mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.bounce_step == "unknown"' >/dev/null \
    || { echo "D: .inputs.bounce_step mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.phase_type == "unknown"' >/dev/null \
    || { echo "D: .inputs.phase_type mismatch; got: $result" >&2; exit 1; }
) && pass "Scenario D (flavor=general via Haiku path)" \
  || fail "Scenario D (general)"

# ---------------------------------------------------------------------------
# Scenario E: PEL_FLAVOR_OVERRIDE bypass (SC-3 — override precedence)
# ---------------------------------------------------------------------------
# Proof-by-fingerprint: the stub writes a marker file on every invocation.
# This scenario asserts the marker DOES NOT exist after the run, proving
# claude was never called. Stronger than output-only assertion — guards
# against a future bug where override emits correct JSON but still calls
# Haiku (T-04-09 spoofing risk).
TOTAL=$((TOTAL + 1))
(
  marker="$TEST_DIR/marker-E"
  rm -f "$marker"
  stub_file="$TEST_DIR/stub-unused-E.json"
  write_stub "$stub_file" "faster-converger" "should NEVER be emitted"

  result=$(CLASSIFIER_STUB_FILE="$stub_file" \
           CLASSIFIER_STUB_MARKER="$marker" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_BOUNCE_STEP=compose \
           PEL_PHASE_TYPE=scoping \
           PEL_FLAVOR_OVERRIDE=bug-catcher \
           bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" \
             "override test task" 2>"$TEST_DIR/stderr-E")

  # Stub fingerprint MUST NOT exist (Haiku was NOT called).
  if [[ -f "$marker" ]]; then
    echo "E: stub claude was invoked despite override (marker contents: $(cat "$marker")); got: $result" >&2
    exit 1
  fi

  # Output must reflect override flavor + override=true + correct rationale.
  echo "$result" | jq -e '.flavor == "bug-catcher"' >/dev/null \
    || { echo "E: override flavor mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.override == true' >/dev/null \
    || { echo "E: .override must be true on override path; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.rationale == "user override via PEL_FLAVOR_OVERRIDE"' >/dev/null \
    || { echo "E: override rationale mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.task == "override test task"' >/dev/null \
    || { echo "E: .inputs.task mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.bounce_step == "compose"' >/dev/null \
    || { echo "E: .inputs.bounce_step mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.phase_type == "scoping"' >/dev/null \
    || { echo "E: .inputs.phase_type mismatch; got: $result" >&2; exit 1; }

  # stderr must log the bypass for observability (SC-3 "is logged" clause).
  grep -qF "Haiku call bypassed" "$TEST_DIR/stderr-E" \
    || { echo "E: stderr missing Haiku-bypass log; got: $(cat "$TEST_DIR/stderr-E")" >&2; exit 1; }
) && pass "Scenario E (PEL_FLAVOR_OVERRIDE bypasses Haiku entirely)" \
  || fail "Scenario E (override precedence)"

# ---------------------------------------------------------------------------
# Scenario F: Frozen-surface invariant (SC-4 / D-11)
# ---------------------------------------------------------------------------
# Every file under lab/pel/classifier/** must be self-contained. Any source
# or dot-import that resolves outside that directory means Phase 7's
# allowlist-exclusion glob "lab/pel/classifier/**" would miss a real
# dependency. This test catches D-05 regressions structurally before they
# ship, so a future executor adding `source ../../../lib/co-evolution.sh`
# is caught here even if the semantic gates still pass.
TOTAL=$((TOTAL + 1))
(
  classifier_dir="$REPO_ROOT/lab/pel/classifier"
  offenders=""
  while IFS= read -r file; do
    # Capture source/dot statements at line-start (or after whitespace).
    # Filter out comments. Then exclude legitimate sibling-only references:
    #   - lines using $SCRIPT_DIR (sibling-resolution pattern)
    #   - lines using dirname (self-locating)
    #   - lines that literally mention lab/pel/classifier (sibling reference)
    external=$(grep -nE '^[[:space:]]*(source|\.)[[:space:]]' "$file" 2>/dev/null \
      | grep -vE '^[[:space:]]*#' \
      | grep -vE 'SCRIPT_DIR|dirname|lab/pel/classifier' \
      || true)
    if [[ -n "$external" ]]; then
      offenders+="$file:$external"$'\n'
    fi
  done < <(find "$classifier_dir" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.md" \))

  if [[ -n "$offenders" ]]; then
    echo "F: frozen-surface invariant breached — classifier sources files outside lab/pel/classifier/:" >&2
    echo "$offenders" >&2
    exit 1
  fi

  # Double-check: the directory contains the three expected files.
  test -f "$classifier_dir/classifier.sh" || { echo "F: classifier.sh missing" >&2; exit 1; }
  test -f "$classifier_dir/adapter.sh"    || { echo "F: adapter.sh missing"    >&2; exit 1; }
  test -f "$classifier_dir/prompt.md"     || { echo "F: prompt.md missing"     >&2; exit 1; }
) && pass "Scenario F (frozen-surface invariant — no sources outside lab/pel/classifier/**)" \
  || fail "Scenario F (frozen-surface)"

# ---------------------------------------------------------------------------
# Scenario G: Input validation (T-04-04) — BONUS
# ---------------------------------------------------------------------------
# Sub-G1: bogus PEL_FLAVOR_OVERRIDE with shell meta → exit 1 + clear error.
# Sub-G2: bogus CLASSIFIER_MODEL with shell meta → exit 1 + clear error.
#
# Note: classifier.sh validates CLASSIFIER_MODEL BEFORE the override check
# fires (line 80), so G2 does NOT need PEL_FLAVOR_OVERRIDE unset — the
# model validator rejects the metacharacter regardless of override path.
# We intentionally set no override for G2 so the failure path is purely
# driven by the bad model string.
BONUS_TOTAL=$((BONUS_TOTAL + 1))
(
  # G1: bogus PEL_FLAVOR_OVERRIDE (shell metacharacter injection attempt).
  out1=$(PATH="$TEST_DIR/bin:$PATH" \
         PEL_FLAVOR_OVERRIDE="evil; rm -rf /" \
         bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" "task" 2>&1 || true)
  echo "$out1" | grep -qE "invalid PEL_FLAVOR_OVERRIDE" \
    || { echo "G1: bogus override not rejected; got: $out1" >&2; exit 1; }

  # Second G1 variant: shell expansion attempt (command substitution).
  out1b=$(PATH="$TEST_DIR/bin:$PATH" \
          PEL_FLAVOR_OVERRIDE='evil$(whoami)' \
          bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" "task" 2>&1 || true)
  echo "$out1b" | grep -qE "invalid PEL_FLAVOR_OVERRIDE" \
    || { echo "G1b: shell-subst override not rejected; got: $out1b" >&2; exit 1; }

  # G2: bogus CLASSIFIER_MODEL (shell metacharacter injection attempt).
  # Stub is on PATH so require_claude_cli would pass — proves validator fires
  # BEFORE the CLI is ever consulted (T-04-04 defense-in-depth).
  stub_file="$TEST_DIR/stub-G2.json"
  write_stub "$stub_file" "general" "unused"
  out2=$(CLASSIFIER_STUB_FILE="$stub_file" \
         CLASSIFIER_MODEL="haiku; rm -rf /" \
         PATH="$TEST_DIR/bin:$PATH" \
         bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" "task" 2>&1 || true)
  echo "$out2" | grep -qE "invalid CLASSIFIER_MODEL" \
    || { echo "G2: bogus model not rejected; got: $out2" >&2; exit 1; }
) && bonus_pass "Scenario G (input validation — bogus override + bogus model both rejected, T-04-04)" \
  || bonus_fail "Scenario G (input validation)"

# ---------------------------------------------------------------------------
# Scenario H: Warn-don't-die (D-04) — BONUS
# ---------------------------------------------------------------------------
# Garbage PEL_BOUNCE_STEP + PEL_PHASE_TYPE produce WARNING on stderr but
# classifier still completes exit 0 and emits valid D-08 JSON via the stub.
# Proves graceful degradation path: caller mistakes do not kill a PEL run.
BONUS_TOTAL=$((BONUS_TOTAL + 1))
(
  stub_file="$TEST_DIR/stub-H.json"
  write_stub "$stub_file" "general" "degraded context"

  result=$(CLASSIFIER_STUB_FILE="$stub_file" \
           CLASSIFIER_STUB_MARKER="$TEST_DIR/marker-H" \
           PATH="$TEST_DIR/bin:$PATH" \
           PEL_BOUNCE_STEP=garbage-step \
           PEL_PHASE_TYPE=also-bogus \
           bash "$REPO_ROOT/lab/pel/classifier/classifier.sh" \
             "graceful degradation test" 2>"$TEST_DIR/stderr-H")

  # stderr must contain both warnings (classifier does NOT die).
  grep -qF "WARNING: unexpected PEL_BOUNCE_STEP" "$TEST_DIR/stderr-H" \
    || { echo "H: PEL_BOUNCE_STEP warning missing; got stderr: $(cat "$TEST_DIR/stderr-H")" >&2; exit 1; }
  grep -qF "WARNING: unexpected PEL_PHASE_TYPE" "$TEST_DIR/stderr-H" \
    || { echo "H: PEL_PHASE_TYPE warning missing; got stderr: $(cat "$TEST_DIR/stderr-H")" >&2; exit 1; }

  # stdout must be valid JSON with forced-to-unknown inputs.
  echo "$result" | jq -e '.flavor == "general"' >/dev/null \
    || { echo "H: .flavor mismatch; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.override == false' >/dev/null \
    || { echo "H: .override must be false on Haiku path; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.bounce_step == "unknown"' >/dev/null \
    || { echo "H: garbage PEL_BOUNCE_STEP did not degrade to unknown; got: $result" >&2; exit 1; }
  echo "$result" | jq -e '.inputs.phase_type == "unknown"' >/dev/null \
    || { echo "H: garbage PEL_PHASE_TYPE did not degrade to unknown; got: $result" >&2; exit 1; }
) && bonus_pass "Scenario H (warn-don't-die: garbage env values degrade to unknown, D-04)" \
  || bonus_fail "Scenario H (warn-don't-die)"

# ---------------------------------------------------------------------------
# Summary footer (matches Phase 2 scorer-verification.sh + Phase 3
# lab-routing-simulation.sh convention: "N/N scenarios passed")
#
# Bonus scenarios (G, H) are reported on their own line BEFORE the primary
# footer so `tail -1` of a successful run returns exactly the primary
# "6/6 scenarios passed" line per v1.2 phase-gate convention. Bonus
# failures surface to stderr but do NOT affect exit code — SC-5 mandates
# the 6 primary scenarios; G+H are defense-in-depth regression coverage.
# ---------------------------------------------------------------------------

bonus_passed=$((BONUS_TOTAL - BONUS_FAILURES))
if (( BONUS_TOTAL > 0 )); then
  if (( BONUS_FAILURES == 0 )); then
    echo "$bonus_passed/$BONUS_TOTAL bonus scenarios passed"
  else
    echo "$bonus_passed/$BONUS_TOTAL bonus scenarios passed ($BONUS_FAILURES bonus failed)" >&2
  fi
fi

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
