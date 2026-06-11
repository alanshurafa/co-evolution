#!/usr/bin/env bash
# Co-Evolution Agent Bouncer
# Usage: ./agent-bouncer.sh <plan-file> [max-bounces] [odd-agent-name] [even-agent-name]
#
# Bounces a plan between two agents (reviewer on odd passes, composer on even)
# using the [CONTESTED]/[CLARIFY] marker protocol until convergence or max passes.
# Default: up to 2 passes with auto-convergence (stops early if markers hit zero).
# Most value comes in the first two passes.
# Use more passes (e.g., ./agent-bouncer.sh plan.md 6) for complex architectural decisions.
#
# Supported agents: claude, codex
# - claude: uses `claude -p` (Claude Code CLI, already authenticated)
# - codex: uses `codex exec --full-auto` (Codex CLI)
# Add new adapters by adding an invoke_<name> function in lib/co-evolution.sh.
#
# Each run creates a named directory under runs/ containing:
#   original.md               - snapshot of input before any passes
#   pass-N-role-agent-raw.md  - full agent output per pass (with HUMAN SUMMARY)
#   <run-label>.md            - clean output (HUMAN SUMMARY stripped), named after the run
#   run.log                   - console output (pass counts, markers, convergence)

set -euo pipefail

PLAN_FILE="${1:?Usage: ./agent-bouncer.sh <plan-file> [max-bounces] [odd-agent] [even-agent]}"
MAX_BOUNCES="${2:-2}"
ODD_AGENT="${3:-claude}"   # Agent for odd passes (reviewer by default)
EVEN_AGENT="${4:-codex}"   # Agent for even passes (composer by default)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
RUNS_DIR="${REPO_ROOT}/runs"
WORKDIR="$(pwd)"

source "${REPO_ROOT}/lib/co-evolution.sh"

# R-7: timestamp + entropy — two runs in the same second must not share a dir.
TIMESTAMP=$(generate_run_suffix)

# Validate that requested agents have adapters
for agent in "$ODD_AGENT" "$EVEN_AGENT"; do
  if ! type "invoke_${agent}" &>/dev/null; then
    echo "ERROR: No adapter for agent '${agent}'. Available: claude, codex" >&2
    exit 1
  fi
done

# Generate a run name from the document content.
# R-3: the LLM naming call is best-effort sugar — skip it entirely when the
# codex CLI is absent, and fall back to a filename-derived label either way.
RUN_NAME=""
CANDIDATE=""
if command -v codex >/dev/null 2>&1; then
  NAME_PROMPT="Read this document title and first paragraph. Output ONLY a 2-4 word kebab-case name describing what this document is about. No explanation, no quotes, just the name. Example: error-handling-plan

$(head -20 "$PLAN_FILE")"

  NAME_PROMPT_FILE=$(mktemp)
  NAME_OUTPUT_FILE=$(mktemp)
  NAME_STDERR_FILE=$(mktemp)
  printf '%s' "$NAME_PROMPT" > "$NAME_PROMPT_FILE"
  invoke_codex "$NAME_PROMPT_FILE" "$NAME_OUTPUT_FILE" "$NAME_STDERR_FILE"
  CANDIDATE=$(tr -d '\r\n ' < "$NAME_OUTPUT_FILE" | head -c 60 || true)
  rm -f "$NAME_PROMPT_FILE" "$NAME_OUTPUT_FILE" "$NAME_STDERR_FILE"
fi

if [[ "$CANDIDATE" =~ ^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$ ]]; then
  RUN_LABEL="$CANDIDATE"
else
  # Filename-derived fallback: "docs/launch plan.md" -> "launch-plan".
  RUN_LABEL=$(basename "$PLAN_FILE" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//')
  RUN_LABEL="${RUN_LABEL:-run}"
fi
RUN_NAME="bouncer-${RUN_LABEL}-${TIMESTAMP}"

RUN_DIR="${RUNS_DIR}/${RUN_NAME}"
mkdir -p "$RUN_DIR"

PROMPT_FILE="${RUN_DIR}/.prompt-tmp.md"
OUTPUT_FILE="${RUN_DIR}/.output-tmp.md"

cleanup() {
  rm -f "$PROMPT_FILE" "$OUTPUT_FILE" "${OUTPUT_FILE}.clean"
}
trap cleanup EXIT

cp "$PLAN_FILE" "${RUN_DIR}/original.md"
# Contract name (evals/BOUNCE-RUNNER-CONTRACT.md); original.md kept for
# back-compat with pre-v1.3 consumers.
cp "$PLAN_FILE" "${RUN_DIR}/original-input.md"

LOG_FILE="${RUN_DIR}/run.log"

# --- Bounce state (bounce-state/1.0; see evals/BOUNCE-RUNNER-CONTRACT.md) ---
STATE_FILE="${RUN_DIR}/state.json"
init_bounce_state "$STATE_FILE" "agent-bouncer.sh" "agent-bouncer" "$PLAN_FILE" "file" "original-input.md" "${RUN_LABEL}.md"
_finalize_bounce_state_on_exit() {
  local exit_code=$?
  if [[ -f "$STATE_FILE" ]] && command -v jq >/dev/null 2>&1; then
    if [[ "$(jq -r '.status' "$STATE_FILE" 2>/dev/null)" == "running" ]]; then
      if (( exit_code == 0 )); then
        finalize_bounce_state "$STATE_FILE" "complete"
      else
        finalize_bounce_state "$STATE_FILE" "aborted"
      fi
    fi
  fi
  cleanup
}
trap _finalize_bounce_state_on_exit EXIT

log "============================================"
log " CO-EVOLUTION AGENT BOUNCER"
log "============================================"
log " Source:     agent-bouncer"
log " Plan:      $PLAN_FILE"
log " Bounces:   up to $MAX_BOUNCES"
log " Reviewer:  $ODD_AGENT (odd passes)"
log " Composer:  $EVEN_AGENT (even passes)"
log " Run:       $RUN_NAME"
log " Dir:       $RUN_DIR"
log "============================================"
log ""

FINAL_PASS=0

for (( PASS=1; PASS<=MAX_BOUNCES; PASS++ )); do
  FINAL_PASS=$PASS

  if (( PASS % 2 == 1 )); then
    ROLE="reviewer"
    AGENT_NAME="$ODD_AGENT"
  else
    ROLE="composer"
    AGENT_NAME="$EVEN_AGENT"
  fi

  PLAN_CONTENT=$(cat "$PLAN_FILE")
  ROLE_PREAMBLE=$(cat "$TEMPLATE_DIR/role-${ROLE}.md")
  PROTOCOL="${ROLE_PREAMBLE}
$(cat "$TEMPLATE_DIR/bounce-protocol.md")"

  FILLED="${PROTOCOL//\{TASK\}/Review and refine this document}"
  FILLED="${FILLED//\{PASS_NUMBER\}/$PASS}"
  FILLED="${FILLED//\{TOTAL_PASSES\}/$MAX_BOUNCES}"
  FILLED="${FILLED//\{YOUR_ROLE\}/$ROLE}"
  FILLED="${FILLED//\{WORKING_DIR\}/$WORKDIR}"
  FILLED="${FILLED//\{PLAN_CONTENT\}/$PLAN_CONTENT}"

  printf '%s' "$FILLED" > "$PROMPT_FILE"

  log "--------------------------------------------"
  log " BOUNCE $PASS/$MAX_BOUNCES - ${ROLE} (${AGENT_NAME})"
  log "--------------------------------------------"

  rm -f "$OUTPUT_FILE"
  STDERR_FILE="${RUN_DIR}/pass-${PASS}-stderr.log"
  RETRY_STDERR_FILE="${RUN_DIR}/pass-${PASS}-stderr-retry.log"
  "invoke_${AGENT_NAME}" "$PROMPT_FILE" "$OUTPUT_FILE" "$STDERR_FILE"
  # 8th arg (first-pass stderr) lets validate_output fail fast on
  # CLI-missing / auth-failure instead of accepting error text (R-1/R-2).
  validate_output "$PLAN_FILE" "$OUTPUT_FILE" "$AGENT_NAME" "invoke_${AGENT_NAME}" "$PROMPT_FILE" "$RETRY_STDERR_FILE" 30 "$STDERR_FILE" || exit 1

  cp "$OUTPUT_FILE" "${RUN_DIR}/pass-${PASS}-${ROLE}-${AGENT_NAME}-raw.md"

  strip_human_summary "$OUTPUT_FILE" "${OUTPUT_FILE}.clean"
  mv "${OUTPUT_FILE}.clean" "$OUTPUT_FILE"

  # Plain per-pass clean artifact (contract name, matches co-evolve-bouncer).
  cp "$OUTPUT_FILE" "${RUN_DIR}/pass-${PASS}-clean.md"

  cp "$OUTPUT_FILE" "$PLAN_FILE"

  CONTESTED=$(count_markers "$PLAN_FILE" "[CONTESTED]")
  CLARIFY=$(count_markers "$PLAN_FILE" "[CLARIFY]")
  TOTAL_MARKERS=$((CONTESTED + CLARIFY))
  WORD_COUNT=$(wc -w < "$PLAN_FILE" | tr -d '\r\n ')

  log " [CONTESTED] markers: $CONTESTED"
  log " [CLARIFY] markers:   $CLARIFY"
  log " Plan length:         $WORD_COUNT words"
  log "--------------------------------------------"
  log ""

  append_bounce_pass "$STATE_FILE" "$PASS" "$ROLE" "$AGENT_NAME" \
    "pass-${PASS}-${ROLE}-${AGENT_NAME}-raw.md" "pass-${PASS}-clean.md" \
    "$CONTESTED" "$CLARIFY" "$WORD_COUNT"

  if (( TOTAL_MARKERS == 0 )); then
    log "Plan converged after $PASS passes (no open markers)."
    log ""
    break
  fi

  if (( PASS == MAX_BOUNCES && TOTAL_MARKERS > 0 )); then
    log "WARNING: $TOTAL_MARKERS unresolved markers after $MAX_BOUNCES passes."
    log ""
  fi
done

FINAL_NAME="${RUN_LABEL}.md"
cp "$PLAN_FILE" "${RUN_DIR}/${FINAL_NAME}"

finalize_bounce_state "$STATE_FILE" "complete"

log "============================================"
log " BOUNCE COMPLETE"
log "============================================"
log " Final plan: $PLAN_FILE"
log " Run dir:    $RUN_DIR"
log " Passes:     $FINAL_PASS / $MAX_BOUNCES"
log " Artifacts:"
log "   original.md                - input before bouncing"
for (( i=1; i<=FINAL_PASS; i++ )); do
  if (( i % 2 == 1 )); then
    R="reviewer"
    A="$ODD_AGENT"
  else
    R="composer"
    A="$EVEN_AGENT"
  fi
  log "   pass-${i}-${R}-${A}-raw.md - pass $i (${R}, ${A})"
done
log "   ${FINAL_NAME} - clean output"
log "   run.log                    - this log"
log "============================================"
