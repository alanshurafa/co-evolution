#!/usr/bin/env bash
# lab/pel/proposer/policy/proposer.sh
# Co-Evolution PEL Policy-Tier Mutation Proposer — public entry point (Phase 6 PEL-03).
#
# Given eval feedback + a target policy YAML + a flavor pick, emits a proposed
# JSON delta to stdout (D-10). Does NOT mutate the live policy file (D-11 —
# dry-run by construction; Phase 8 applies the delta via yq after human PR review).
#
# Usage:
#   bash proposer.sh [optional-task-hint]
#
# Environment (caller-sets-before-invocation per D-05):
#   PEL_FEEDBACK            path to eval-failure JSON (required; D-06 die on missing)
#   PEL_POLICY_PATH         path to policy YAML to mutate (required; typically
#                           lab/pel/proposer/policy/policy.yaml but parameterized)
#   PEL_FLAVOR              one of bug-catcher|faster-converger|blind-spot-surfacer|general (required)
#   POLICY_PROPOSER_MODEL   Haiku model ID (default: claude-haiku-4-5-20251001)
#
# Output (stdout):
#   Single JSON delta object per D-10 schema. All diagnostics go to stderr.
#
# Exit codes (fail-fast):
#   0 success
#   1 input validation failure (missing env var, bad PEL_FLAVOR token, bad model, path traversal)
#   2 claude CLI missing / auth failure / yq or jq missing / Haiku call non-zero
#   3 malformed Haiku response (non-JSON, missing fields)
#   4 bounds violation in proposed delta (bounds.jq halt_error(4))
#   5 non-enumerated knob in proposed delta (bounds.jq halt_error(5))
#
# Self-contained per D-08: no lib/co-evolution.sh or runner internals imported.

set -euo pipefail

# --- Argv + self-locating -----------------------------------------------------
TASK_HINT="${1:-}"   # Optional — empty is legal

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# --- Required tool checks (T-06-05, T-06-06) ----------------------------------
require_tools() {
  command -v jq >/dev/null 2>&1 \
    || { echo "ERROR: jq is required. Install: scoop install jq (Windows), brew install jq (macOS), apt install jq (Linux)." >&2; exit 2; }
  # F-1: reject the python yq (apt) -- require mikefarah/Go yq v4 by its --version.
  if ! command -v yq >/dev/null 2>&1 || ! yq --version 2>&1 | grep -qi mikefarah; then
    echo "ERROR: mikefarah/yq (Go yq v4+) is required; the python 'yq' is not compatible. Install: scoop install yq (Windows), brew install yq (macOS), or see https://github.com/mikefarah/yq." >&2
    exit 2
  fi
}
require_tools

# --- Env validation (D-06 — die on missing required) -------------------------
[[ -n "${PEL_FEEDBACK:-}" ]]     || { echo "ERROR: PEL_FEEDBACK is required (path to eval-feedback JSON)" >&2; exit 1; }
[[ -n "${PEL_POLICY_PATH:-}" ]]  || { echo "ERROR: PEL_POLICY_PATH is required (path to policy YAML)" >&2; exit 1; }
[[ -n "${PEL_FLAVOR:-}" ]]       || { echo "ERROR: PEL_FLAVOR is required (one of bug-catcher, faster-converger, blind-spot-surfacer, general)" >&2; exit 1; }

case "$PEL_FLAVOR" in
  bug-catcher|faster-converger|blind-spot-surfacer|general) ;;
  *)
    echo "ERROR: invalid PEL_FLAVOR: $PEL_FLAVOR (must be one of bug-catcher, faster-converger, blind-spot-surfacer, general)" >&2
    exit 1
    ;;
esac

: "${POLICY_PROPOSER_MODEL:=claude-haiku-4-5-20251001}"
export POLICY_PROPOSER_MODEL

# --- Path validation + realpath containment check (T-06-07) -------------------
validate_path_in_repo() {
  # $1 = env var name (for error), $2 = raw path
  local name="$1" raw="$2"
  [[ -r "$raw" ]] || { echo "ERROR: $name not readable: $raw" >&2; exit 1; }
  local dirpart resolved
  dirpart=$(cd "$(dirname "$raw")" 2>/dev/null && pwd -P) \
    || { echo "ERROR: $name directory cannot be resolved: $raw" >&2; exit 1; }
  resolved="${dirpart}/$(basename "$raw")"
  # Prefix check — resolved path must start with REPO_ROOT
  case "$resolved" in
    "$REPO_ROOT"/*) ;;
    *)
      echo "ERROR: $name path resolves outside repo root: $resolved (repo: $REPO_ROOT)" >&2
      exit 1
      ;;
  esac
}
validate_path_in_repo "PEL_FEEDBACK"    "$PEL_FEEDBACK"
validate_path_in_repo "PEL_POLICY_PATH" "$PEL_POLICY_PATH"

# --- Parse-only verification of the two inputs (T-06-06) ---------------------
# D-11: yq is invoked read-only; no -i (in-place) flag anywhere in this file.
yq -e "type" "$PEL_POLICY_PATH" >/dev/null 2>&1 \
  || { echo "ERROR: PEL_POLICY_PATH is not valid YAML: $PEL_POLICY_PATH" >&2; exit 1; }
jq -e "type" "$PEL_FEEDBACK" >/dev/null 2>&1 \
  || { echo "ERROR: PEL_FEEDBACK is not valid JSON: $PEL_FEEDBACK" >&2; exit 1; }

# --- Export for adapter consumption + sibling-only adapter load ---------------
export TASK_HINT PEL_FEEDBACK PEL_POLICY_PATH PEL_FLAVOR

# shellcheck source=adapter.sh
# Sibling-only import — resolves inside lab/pel/proposer/policy/** frozen boundary.
source "$SCRIPT_DIR/adapter.sh"

# --- Model string validation (T-06-03, before any claude call) ----------------
validate_proposer_model "$POLICY_PROPOSER_MODEL"

# --- Invoke adapter, capture delta, run bounds.jq (D-12 runtime enforcement) --
# Run run_adapter and capture its stdout (the delta JSON). The adapter dies
# itself on CLI/auth/response-shape failures (exit codes 2/3).
delta=$(run_adapter)

# Validate against bounds.jq — the single source of truth.
# jq -f bounds.jq exits 0 on success, 4 on bounds violation, 5 on unknown knob.
# Preserve jq's exit code so the proposer exits with the right category.
#
# Capture jq's rc directly: `if ! cmd; then rc=$?` would capture `!`'s exit
# (which is always 0 when the inner fails), masking jq's real code. Run jq
# and assign rc immediately after.
rc=0
echo "$delta" | jq -f "$SCRIPT_DIR/bounds.jq" >/dev/null 2>/dev/null || rc=$?
if (( rc != 0 )); then
  # Re-run to surface the violation record (halt_error prints it to stderr
  # at exit). The first run was quieted to capture the pure exit code.
  echo "$delta" | jq -f "$SCRIPT_DIR/bounds.jq" >/dev/null || true
  echo "ERROR: delta failed bounds.jq validation (jq exit $rc)" >&2
  exit "$rc"
fi

# Emit the validated delta to stdout — this IS the D-10 output.
echo "$delta"
