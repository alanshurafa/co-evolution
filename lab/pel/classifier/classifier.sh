#!/usr/bin/env bash
# lab/pel/classifier/classifier.sh
# Co-Evolution PEL Mode Classifier — public entry point (Phase 4 PEL-01).
#
# Picks one of four fitness flavors (bug-catcher / faster-converger /
# blind-spot-surfacer / general) for a PEL mutation proposer invocation.
#
# Usage:
#   bash classifier.sh "<task string>"
#
# Environment (caller-sets-before-invocation per D-02):
#   PEL_BOUNCE_STEP         compose|bounce|execute|verify|unknown (default: unknown)
#   PEL_PHASE_TYPE          scoping|implementation|verification|unknown (default: unknown)
#   PEL_FLAVOR_OVERRIDE     (optional) force flavor pick; valid values same as output.
#                           When set, Haiku is NOT invoked (D-09 bypass).
#   CLASSIFIER_MODEL        Haiku model ID (default: claude-haiku-4-5-20251001)
#                           Override for debugging only — contract is frozen in v1.2.
#
# Output (stdout):
#   Single JSON object per D-08 schema. All diagnostics go to stderr.
#
# Exit codes (D-07 fail-fast):
#   0 success
#   1 input validation failure (bad override, bad task arg, bad CLASSIFIER_MODEL)
#   2 claude CLI missing / auth failure / Haiku call non-zero
#   3 malformed Haiku response / invalid flavor returned
#
# Self-contained per D-05: no lib/co-evolution.sh or runner internals are imported.
# Frozen per D-11: lab/pel/classifier/** is the Phase 7 allowlist-exclusion glob.

set -euo pipefail

# --- Argv contract (W-3 single-slot task string) ---
# $1 is the whole task string. Multi-token tasks arrive pre-joined by the runner
# (see lab/README.md:121). Missing $1 dies with a clear usage message.
TASK="${1:?Usage: classifier.sh <task-string>}"

# --- Self-locating: sibling-only source (D-05 no external sourcing) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Env-var defaults (D-02 + D-03 — mirrors lib/co-evolution.sh:19-34 pattern) ---
: "${PEL_BOUNCE_STEP:=unknown}"
: "${PEL_PHASE_TYPE:=unknown}"
: "${CLASSIFIER_MODEL:=claude-haiku-4-5-20251001}"
# PEL_FLAVOR_OVERRIDE intentionally NOT defaulted; unset = no override.
export PEL_BOUNCE_STEP PEL_PHASE_TYPE CLASSIFIER_MODEL TASK

# --- Env value validation (D-04 — warn, do NOT die) ---
# Domain violations are caller mistakes, not structural failures. Warn to
# stderr and degrade to unknown so a misspelled env var does not kill an
# entire PEL run. (Structural failures — bad override token, missing task,
# bad model string — still die. See below.)
case "$PEL_BOUNCE_STEP" in
  compose|bounce|execute|verify|unknown) ;;
  *)
    printf "WARNING: unexpected PEL_BOUNCE_STEP value %q, treating as unknown\n" "$PEL_BOUNCE_STEP" >&2
    PEL_BOUNCE_STEP=unknown
    export PEL_BOUNCE_STEP
    ;;
esac

case "$PEL_PHASE_TYPE" in
  scoping|implementation|verification|unknown) ;;
  *)
    printf "WARNING: unexpected PEL_PHASE_TYPE value %q, treating as unknown\n" "$PEL_PHASE_TYPE" >&2
    PEL_PHASE_TYPE=unknown
    export PEL_PHASE_TYPE
    ;;
esac

# --- Load the self-contained adapter (D-05 — sibling only) ---
# The adapter defines die(), log_stderr(), validate_classifier_model(),
# emit_classification(), run_adapter(), and friends. No external imports.
# shellcheck source=adapter.sh
source "$SCRIPT_DIR/adapter.sh"

# --- CLASSIFIER_MODEL validation (T-04-04) ---
# Validate BEFORE the override path so both paths reject shell metacharacters.
# validate_classifier_model is provided by adapter.sh (which was just sourced).
validate_classifier_model "$CLASSIFIER_MODEL"

# --- Override fast-path (D-09 + SC-3) ---
# When PEL_FLAVOR_OVERRIDE is set:
#   1. Validate against the 4 legal tokens (T-04-04 strict schema — no
#      shell metacharacters, no arbitrary strings).
#   2. Emit override JSON via emit_classification with override=true.
#   3. Skip Haiku entirely (D-09: override IS the trust signal; no
#      would-have-been comparison logging in v1.2).
if [[ -n "${PEL_FLAVOR_OVERRIDE:-}" ]]; then
  case "$PEL_FLAVOR_OVERRIDE" in
    bug-catcher|faster-converger|blind-spot-surfacer|general)
      printf "INFO: override active — flavor=%s, Haiku call bypassed\n" "$PEL_FLAVOR_OVERRIDE" >&2
      emit_classification "$PEL_FLAVOR_OVERRIDE" "user override via PEL_FLAVOR_OVERRIDE" "true"
      exit 0
      ;;
    *)
      die "invalid PEL_FLAVOR_OVERRIDE: $PEL_FLAVOR_OVERRIDE (must be one of bug-catcher, faster-converger, blind-spot-surfacer, general)" 1
      ;;
  esac
fi

# --- Non-override path: delegate to adapter.sh's run_adapter ---
# run_adapter handles the full Haiku flow:
#   - require_claude_cli (dies exit 2 if CLI missing)
#   - compose_prompt from prompt.md (placeholder substitution, no eval)
#   - invoke_haiku (fail-fast on non-zero; auth-failure detection → exit 2)
#   - validate_haiku_response (exit 3 on schema/value failure)
#   - emit_classification with override=false
run_adapter
