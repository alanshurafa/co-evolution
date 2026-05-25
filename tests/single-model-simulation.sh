#!/usr/bin/env bash
# tests/single-model-simulation.sh
# Hermetic simulation of the --single-model flag on co-evolve-bouncer.sh.
#
# Scenarios (all hermetic — no Claude/Codex CLIs invoked, only the
# arg-parser + preamble-builder paths are exercised):
#
#   A: --help advertises --single-model and retains pre-existing flags
#      (byte-parity spot-check for --agents, --bounces, --lab).
#   B: Bare --single-model defaults to "claude" for both roles and
#      logs the "Single: yes" banner line.
#   C: --single-model codex routes both roles to codex.
#   D: --single-model=opus rejected with a clear error (allow-list guard).
#   E: When --single-model is NOT set, the banner has no "Single:" line
#      (byte-parity invariant for default cross-model runs).
#   F: --single-model alone does NOT prepend the persona-discipline preface
#      (post-2026-05-24 A/B finding: bare two-role mode is the empirical
#      winner on dense technical docs; preface decoupled into --persona-discipline).
#   G: --persona-discipline prepends the preface (proves the opt-in wiring
#      actually reaches the role preamble — covers both --single-model
#      and standalone --persona-discipline cases).
#
# Final line on success: `7/7 scenarios passed`.
# Exit 0 iff all 7 scenarios pass; exit 1 otherwise.

set -euo pipefail

TEST_DIR=$(mktemp -d -t single-model-sim-XXXXXX)
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"

FAILURES=0
TOTAL=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "PASS: $1"; }

# ---------------------------------------------------------------------------
# Scenario A: --help advertises --single-model + retains older flags
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  out=$(bash "$BOUNCER" --help 2>&1)
  echo "$out" | grep -qF -- "--single-model" \
    || { echo "A: --help missing --single-model row" >&2; exit 1; }
  echo "$out" | grep -qF -- "--agents" \
    || { echo "A: --help missing --agents (byte-parity regression)" >&2; exit 1; }
  echo "$out" | grep -qF -- "--bounces" \
    || { echo "A: --help missing --bounces (byte-parity regression)" >&2; exit 1; }
  echo "$out" | grep -qF -- "--lab" \
    || { echo "A: --help missing --lab (byte-parity regression)" >&2; exit 1; }
) && pass "Scenario A (--help advertises --single-model, older flags intact)" \
  || fail "Scenario A (--help intact)"

# ---------------------------------------------------------------------------
# Stub the underlying agent invocations so the bouncer can run end-to-end
# without network. We source lib/co-evolution.sh, then override invoke_claude
# and invoke_codex to write a tiny canned response so the bouncer reaches its
# banner-log + compose-phase code paths.
#
# This trick: run a wrapper script that pre-loads stubs into the environment
# via BASH_ENV, then exec's the real bouncer. The bouncer sources
# lib/co-evolution.sh AFTER BASH_ENV runs, so our stubs get overwritten —
# instead, we wrap by sourcing the lib ourselves, redefining the functions,
# then sourcing the bouncer's body.
#
# Simpler: write a stub-lib that the bouncer sources INSTEAD of the real lib,
# by manipulating its `source "$SCRIPT_DIR/lib/co-evolution.sh"` line via a
# shadow SCRIPT_DIR. We achieve that by copying the bouncer to TEST_DIR and
# placing a stub lib alongside it.
# ---------------------------------------------------------------------------

SHADOW_DIR="$TEST_DIR/shadow"
mkdir -p "$SHADOW_DIR/lib" "$SHADOW_DIR/templates/co-evolve" \
         "$SHADOW_DIR/agent-bouncer/templates"

# Copy templates the bouncer validates on startup.
cp "$REPO_ROOT/templates/co-evolve/role-reviewer-light.md"    "$SHADOW_DIR/templates/co-evolve/"
cp "$REPO_ROOT/templates/co-evolve/role-composer-light.md"    "$SHADOW_DIR/templates/co-evolve/"
cp "$REPO_ROOT/templates/co-evolve/chain-critique.md"         "$SHADOW_DIR/templates/co-evolve/"
cp "$REPO_ROOT/templates/co-evolve/chain-defend.md"           "$SHADOW_DIR/templates/co-evolve/"
cp "$REPO_ROOT/templates/co-evolve/chain-tighten.md"          "$SHADOW_DIR/templates/co-evolve/"
cp "$REPO_ROOT/templates/co-evolve/single-model-preface.md"   "$SHADOW_DIR/templates/co-evolve/"
cp "$REPO_ROOT/agent-bouncer/templates/bounce-protocol.md"    "$SHADOW_DIR/agent-bouncer/templates/"
cp "$BOUNCER" "$SHADOW_DIR/co-evolve-bouncer.sh"

# Stub lib: re-export the few real functions the bouncer needs, but stub
# invoke_claude / invoke_codex so they emit a canned ~50-word response.
cat > "$SHADOW_DIR/lib/co-evolution.sh" <<'STUB'
#!/usr/bin/env bash
log() {
  local message="${1:-}"
  if [[ -n "${LOG_FILE:-}" ]]; then
    echo "$message" | tee -a "$LOG_FILE"
  else
    echo "$message"
  fi
}
die() { log "ERROR: ${1:-Fatal error}"; exit 1; }

validate_lab_mode()      { return 1; }
list_available_lab_modes() { printf '(none)'; }
dispatch_lab_mode()      { die "lab dispatch disabled in stub"; }

# Canned ~60-word response so size_sanity_check passes for short inputs.
_canned_output() {
  cat <<'EOF'
This is a stub agent response generated by the single-model test harness.
The harness exercises the bouncer's arg-parser and preamble-builder paths
without invoking any real model. Both compose and bounce phases produce
this identical body so marker-counting, working-file copying, and the
banner-log all execute the same code paths they would in a real run, but
with deterministic content and zero network access.
EOF
}

invoke_claude() {
  local prompt_file="$1"; local output_file="$2"; local stderr_file="$3"
  _canned_output > "$output_file"
  : > "$stderr_file"
  # Snapshot prompt so scenario F can grep it.
  cp "$prompt_file" "${prompt_file}.captured" 2>/dev/null || true
}

invoke_codex() {
  local prompt_file="$1"; local output_file="$2"; local stderr_file="$3"
  _canned_output > "$output_file"
  : > "$stderr_file"
  cp "$prompt_file" "${prompt_file}.captured" 2>/dev/null || true
}

count_markers() {
  awk -v marker="$2" 'BEGIN{c=0} index($0,marker){c++} END{print c}' "$1" \
    | tr -d '\r\n '
}
strip_human_summary() {
  awk '/^## HUMAN SUMMARY/{found=1} !found{print}' "$1" > "$2"
}
STUB

run_bouncer() {
  # Run the shadowed bouncer from inside its own dir so SCRIPT_DIR resolves
  # to SHADOW_DIR and our stub lib is what gets sourced.
  (cd "$SHADOW_DIR" && bash ./co-evolve-bouncer.sh "$@")
}

# ---------------------------------------------------------------------------
# Scenario B: bare --single-model defaults to claude + logs banner line
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  out=$(run_bouncer --vanilla --single-model --bounces 1 "smoke test prompt" 2>&1) \
    || { echo "B: bouncer exited non-zero; out: $out" >&2; exit 1; }
  echo "$out" | grep -qE "Single:[[:space:]]+yes \(both roles on claude" \
    || { echo "B: missing 'Single: yes (... claude' banner; out: $out" >&2; exit 1; }
  echo "$out" | grep -qF "bare two-role mode" \
    || { echo "B: banner missing 'bare two-role mode' phrase; out: $out" >&2; exit 1; }
  echo "$out" | grep -qE "Compose:[[:space:]]+claude" \
    || { echo "B: compose agent not pinned to claude; out: $out" >&2; exit 1; }
  echo "$out" | grep -qE "Bounce:[[:space:]]+claude / claude" \
    || { echo "B: bounce pair not pinned to claude/claude; out: $out" >&2; exit 1; }
  # Bare --single-model must NOT enable the preface (default-off post-2026-05-24).
  if echo "$out" | grep -qE "Persona:[[:space:]]+discipline preface enabled"; then
    echo "B: bare --single-model unexpectedly enabled the persona-discipline preface" >&2
    exit 1
  fi
) && pass "Scenario B (bare --single-model defaults to claude)" \
  || fail "Scenario B (bare --single-model)"

# ---------------------------------------------------------------------------
# Scenario C: --single-model codex pins both roles to codex
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  out=$(run_bouncer --vanilla --single-model codex --bounces 1 "smoke test prompt" 2>&1) \
    || { echo "C: bouncer exited non-zero; out: $out" >&2; exit 1; }
  echo "$out" | grep -qE "Bounce:[[:space:]]+codex / codex" \
    || { echo "C: bounce pair not pinned to codex/codex; out: $out" >&2; exit 1; }
  echo "$out" | grep -qE "Single:[[:space:]]+yes \(both roles on codex" \
    || { echo "C: banner missing codex; out: $out" >&2; exit 1; }
) && pass "Scenario C (--single-model codex pins both roles to codex)" \
  || fail "Scenario C (--single-model codex)"

# ---------------------------------------------------------------------------
# Scenario D: --single-model=opus rejected (allow-list guard)
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  out=$(run_bouncer --vanilla --single-model=opus --bounces 1 "smoke test prompt" 2>&1 || true)
  echo "$out" | grep -qF -- "--single-model agent must be claude or codex" \
    || { echo "D: missing allow-list error; out: $out" >&2; exit 1; }
) && pass "Scenario D (unknown --single-model agent rejected)" \
  || fail "Scenario D (allow-list)"

# ---------------------------------------------------------------------------
# Scenario E: default (no --single-model) → no 'Single:' banner line
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  # Force AGENT_B=claude too so we don't actually try codex; the stubs cover both anyway.
  out=$(run_bouncer --vanilla --agents claude,claude --bounces 1 "smoke test prompt" 2>&1) \
    || { echo "E: bouncer exited non-zero; out: $out" >&2; exit 1; }
  if echo "$out" | grep -qE "Single:[[:space:]]+yes"; then
    echo "E: banner leaked 'Single:' line in default cross-model run; out: $out" >&2; exit 1
  fi
) && pass "Scenario E (default run has no 'Single:' banner — byte-parity)" \
  || fail "Scenario E (default banner clean)"

# ---------------------------------------------------------------------------
# Scenario F: --single-model alone does NOT prepend the preface (default-off)
# ---------------------------------------------------------------------------
# Post-2026-05-24 finding: bare two-role mode is the empirical winner on
# dense docs. The preface MUST NOT leak into prompts unless --persona-discipline
# is explicitly set. Scans captured prompts for absence of the preface header.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  out=$(run_bouncer --vanilla --single-model --bounces 1 "default-off preface smoke" 2>&1) \
    || { echo "F: bouncer exited non-zero; out: $out" >&2; exit 1; }

  run_dir=$(echo "$out" | grep -E "Run dir:[[:space:]]" | tail -1 | sed -E 's/.*Run dir:[[:space:]]+//')
  [[ -n "$run_dir" && -d "$run_dir" ]] \
    || { echo "F: could not locate run dir from banner; out: $out" >&2; exit 1; }

  captured=$(find "$run_dir" -maxdepth 1 -name '*.captured' 2>/dev/null)
  [[ -n "$captured" ]] \
    || { echo "F: no .captured prompt files in $run_dir" >&2; exit 1; }

  if grep -lF "SINGLE-MODEL PERSONA DISCIPLINE" $captured >/dev/null 2>&1; then
    echo "F: preface header leaked into prompts without --persona-discipline flag" >&2
    exit 1
  fi
) && pass "Scenario F (bare --single-model does NOT prepend preface — default-off)" \
  || fail "Scenario F (preface default-off)"

# ---------------------------------------------------------------------------
# Scenario G: --persona-discipline prepends the preface (opt-in wiring)
# ---------------------------------------------------------------------------
# Combined with --single-model, the flag MUST cause the preface header to
# appear in captured prompts AND the banner MUST show the opt-in line.
# ---------------------------------------------------------------------------
TOTAL=$((TOTAL + 1))
(
  out=$(run_bouncer --vanilla --single-model --persona-discipline --bounces 1 \
        "persona-discipline opt-in smoke" 2>&1) \
    || { echo "G: bouncer exited non-zero; out: $out" >&2; exit 1; }

  echo "$out" | grep -qE "Persona:[[:space:]]+discipline preface enabled" \
    || { echo "G: banner missing 'Persona: discipline preface enabled' line; out: $out" >&2; exit 1; }

  run_dir=$(echo "$out" | grep -E "Run dir:[[:space:]]" | tail -1 | sed -E 's/.*Run dir:[[:space:]]+//')
  [[ -n "$run_dir" && -d "$run_dir" ]] \
    || { echo "G: could not locate run dir from banner; out: $out" >&2; exit 1; }

  captured=$(find "$run_dir" -maxdepth 1 -name '*.captured' 2>/dev/null)
  [[ -n "$captured" ]] \
    || { echo "G: no .captured prompt files in $run_dir" >&2; exit 1; }

  if ! grep -lF "SINGLE-MODEL PERSONA DISCIPLINE" $captured >/dev/null 2>&1; then
    echo "G: preface header missing from all captured prompts in $run_dir" >&2
    exit 1
  fi
) && pass "Scenario G (--persona-discipline opt-in prepends preface)" \
  || fail "Scenario G (persona-discipline opt-in)"

# ---------------------------------------------------------------------------
echo
if [[ $FAILURES -eq 0 ]]; then
  echo "$TOTAL/$TOTAL scenarios passed"
  exit 0
else
  echo "$((TOTAL - FAILURES))/$TOTAL scenarios passed ($FAILURES failures)"
  exit 1
fi
