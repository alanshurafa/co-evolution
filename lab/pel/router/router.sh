#!/usr/bin/env bash
# lab/pel/router/router.sh
# Co-Evolution PEL Router entry — picks model based on complexity classification.
#
# Reads env vars (TARGET, PEL_TIER, PEL_FLAVOR, PEL_FEEDBACK,
# PEL_COMPLEXITY_OVERRIDE). Emits routing JSON on stdout.
#
# Invoked from lab/pel/pr-emitter/pr-emitter.sh between flavor classification
# and proposer dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=adapter.sh
source "$SCRIPT_DIR/adapter.sh"

# ---------------------------------------------------------------------------
# Bypass: PEL_NO_ADAPTIVE=1 → router is a no-op (Scenario D).
# ---------------------------------------------------------------------------
if [[ "${PEL_NO_ADAPTIVE:-0}" == "1" ]]; then
  log_stderr "INFO: PEL_NO_ADAPTIVE=1 — router skipped"
  exit 0
fi

# ---------------------------------------------------------------------------
# Required inputs.
# ---------------------------------------------------------------------------
: "${TARGET:?TARGET env var required}"
: "${PEL_TIER:?PEL_TIER env var required}"
: "${PEL_FLAVOR:?PEL_FLAVOR env var required}"
: "${PEL_FEEDBACK:?PEL_FEEDBACK env var required}"

# Resolve target size (best-effort; falls back to 0 if file missing).
TARGET_SIZE_BYTES=0
if [[ -f "$TARGET" ]]; then
  TARGET_SIZE_BYTES=$(wc -c < "$TARGET" | tr -d ' ')
fi
export TARGET_SIZE_BYTES

# ---------------------------------------------------------------------------
# Tier-to-model mapping helper. Single source of truth — every code path
# that emits routing JSON goes through this.
# ---------------------------------------------------------------------------
emit_routing_json() {
  local complexity="$1" rationale="$2" user_override="${3:-null}"
  local model thinking_budget

  case "$complexity" in
    NORMAL)
      model="sonnet"
      thinking_budget="null"
      ;;
    COMPLEX)
      model="opus"
      thinking_budget='"harder"'
      ;;
    *)
      die "invalid complexity value: $complexity (expected NORMAL|COMPLEX)" 1
      ;;
  esac

  # Quote user_override correctly (null vs "STRING").
  local override_json
  if [[ "$user_override" == "null" ]]; then
    override_json="null"
  else
    override_json="\"$user_override\""
  fi

  # Emit canonical JSON via jq for safety (no manual string concatenation).
  jq -n \
    --arg complexity "$complexity" \
    --arg model "$model" \
    --arg fallback_model "sonnet" \
    --argjson thinking_budget "$thinking_budget" \
    --arg rationale "$rationale" \
    --arg pel_tier "$PEL_TIER" \
    --arg target "$TARGET" \
    --argjson target_size_bytes "$TARGET_SIZE_BYTES" \
    --arg flavor "$PEL_FLAVOR" \
    --argjson user_override "$override_json" \
    '{
      complexity: $complexity,
      model: $model,
      fallback_model: $fallback_model,
      thinking_budget: $thinking_budget,
      rationale: $rationale,
      inputs: {
        pel_tier: $pel_tier,
        target: $target,
        target_size_bytes: $target_size_bytes,
        flavor: $flavor,
        user_override: $user_override
      }
    }'
}

# ---------------------------------------------------------------------------
# Override path (Scenario C) — Task 4 fills this in. Skeleton here so the
# control flow shape exists.
# ---------------------------------------------------------------------------
if [[ -n "${PEL_COMPLEXITY_OVERRIDE:-}" ]]; then
  die "Override path not yet implemented (Task 4)" 99
fi

# ---------------------------------------------------------------------------
# Standard path: invoke Haiku, parse complexity, emit canonical JSON.
# Failure path (Scenario E) — Task 5 will replace die with safe-side fallback.
# ---------------------------------------------------------------------------
haiku_response=""
if ! haiku_response=$(run_adapter); then
  die "Haiku call failed (Task 5 will add safe-side fallback here)" 99
fi

# Validate Haiku response shape.
echo "$haiku_response" | jq -e 'type == "object" and has("complexity") and has("rationale")' >/dev/null 2>&1 \
  || die "Haiku response was not a valid JSON object: $haiku_response" 3

complexity=$(echo "$haiku_response" | jq -r '.complexity')
rationale=$(echo "$haiku_response" | jq -r '.rationale')

case "$complexity" in
  NORMAL|COMPLEX) ;;
  *)
    die "Haiku returned invalid complexity: $complexity (expected NORMAL|COMPLEX)" 3
    ;;
esac

emit_routing_json "$complexity" "$rationale"
