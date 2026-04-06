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
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
RUNS_DIR="${REPO_ROOT}/runs"
WORKDIR="$(pwd)"

source "${REPO_ROOT}/lib/co-evolution.sh"

# Validate that requested agents have adapters
for agent in "$ODD_AGENT" "$EVEN_AGENT"; do
  if ! type "invoke_${agent}" &>/dev/null; then
    echo "ERROR: No adapter for agent '${agent}'. Available: claude, codex" >&2
    exit 1
  fi
done

# Generate a run name from the document content.
RUN_NAME=""
NAME_PROMPT="Read this document title and first paragraph. Output ONLY a 2-4 word kebab-case name describing what this document is about. No explanation, no quotes, just the name. Example: error-handling-plan

$(head -20 "$PLAN_FILE")"

CANDIDATE=$(printf '%s' "$NAME_PROMPT" | codex exec --full-auto --skip-git-repo-check -C "$WORKDIR" 2>/dev/null | tr -d '\r\n ' | head -c 60 || true)

if [[ "$CANDIDATE" =~ ^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$ ]]; then
  RUN_LABEL="$CANDIDATE"
  RUN_NAME="bouncer-${RUN_LABEL}-${TIMESTAMP}"
else
  RUN_LABEL="run"
  RUN_NAME="bouncer-run-${TIMESTAMP}"
fi

RUN_DIR="${RUNS_DIR}/${RUN_NAME}"
mkdir -p "$RUN_DIR"

PROMPT_FILE="${RUN_DIR}/.prompt-tmp.md"
OUTPUT_FILE="${RUN_DIR}/.output-tmp.md"

cleanup() {
  rm -f "$PROMPT_FILE" "$OUTPUT_FILE" "${OUTPUT_FILE}.clean"
}
trap cleanup EXIT

cp "$PLAN_FILE" "${RUN_DIR}/original.md"

LOG_FILE="${RUN_DIR}/run.log"

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
  validate_output "$PLAN_FILE" "$OUTPUT_FILE" "$AGENT_NAME" "invoke_${AGENT_NAME}" "$PROMPT_FILE" "$RETRY_STDERR_FILE" || exit 1

  cp "$OUTPUT_FILE" "${RUN_DIR}/pass-${PASS}-${ROLE}-${AGENT_NAME}-raw.md"

  strip_human_summary "$OUTPUT_FILE" "${OUTPUT_FILE}.clean"
  mv "${OUTPUT_FILE}.clean" "$OUTPUT_FILE"

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
