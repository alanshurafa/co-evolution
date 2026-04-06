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
# - claude: uses `claude -p --bare` (Claude Code CLI, already authenticated)
# - codex: uses `codex exec --full-auto` (Codex CLI)
# Add new adapters by adding an invoke_<name> function below.
#
# Each run creates a named directory under runs/ containing:
#   original.md               — snapshot of input before any passes
#   pass-N-role-agent-raw.md  — full agent output per pass (with HUMAN SUMMARY)
#   <run-label>.md            — clean output (HUMAN SUMMARY stripped), named after the run
#   run.log                   — console output (pass counts, markers, convergence)

set -euo pipefail

PLAN_FILE="${1:?Usage: ./agent-bouncer.sh <plan-file> [max-bounces] [odd-agent] [even-agent]}"
MAX_BOUNCES="${2:-2}"
ODD_AGENT="${3:-claude}"   # Agent for odd passes (reviewer by default)
EVEN_AGENT="${4:-codex}"   # Agent for even passes (composer by default)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# --- Agent adapters ---
# Each adapter: invoke_<name> <prompt-file> <output-file> <stderr-file>
# Must write the agent's response to the output file.

invoke_claude() {
  local prompt_file="$1" output_file="$2" stderr_file="$3"
  # Pure text task — disable tools so Claude outputs the document directly
  # instead of burning turns on tool calls and hitting the max-turns limit.
  claude -p --output-format text --model claude-opus-4-6 --tools "" \
    < "$prompt_file" > "$output_file" 2>"$stderr_file" || true
}

invoke_codex() {
  local prompt_file="$1" output_file="$2" stderr_file="$3"
  # --skip-git-repo-check: documents may live outside git repos (e.g., Google Drive)
  codex exec --full-auto --skip-git-repo-check -C "$WORKDIR" -o "$output_file" \
    < "$prompt_file" 2>"$stderr_file" || true
}

# Validate that requested agents have adapters
for agent in "$ODD_AGENT" "$EVEN_AGENT"; do
  if ! type "invoke_${agent}" &>/dev/null; then
    echo "ERROR: No adapter for agent '${agent}'. Available: claude, codex" >&2
    exit 1
  fi
done
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
RUNS_DIR="${REPO_ROOT}/runs"
WORKDIR="$(pwd)"

# --- Generate a run name from the document content ---
# Ask the agent for a short descriptive name, fall back to timestamp
RUN_NAME=""
NAME_PROMPT="Read this document title and first paragraph. Output ONLY a 2-4 word kebab-case name describing what this document is about. No explanation, no quotes, just the name. Example: error-handling-plan

$(head -20 "$PLAN_FILE")"

CANDIDATE=$(printf '%s' "$NAME_PROMPT" | codex exec --full-auto --skip-git-repo-check -C "$WORKDIR" 2>/dev/null | tr -d '\r\n ' | head -c 60 || true)

# Validate: must be kebab-case (lowercase letters, digits, hyphens), 2-60 chars
if [[ "$CANDIDATE" =~ ^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$ ]]; then
  RUN_LABEL="$CANDIDATE"
  RUN_NAME="bouncer-${RUN_LABEL}-${TIMESTAMP}"
else
  RUN_LABEL="run"
  RUN_NAME="bouncer-run-${TIMESTAMP}"
fi

# --- Create run directory ---
RUN_DIR="${RUNS_DIR}/${RUN_NAME}"
mkdir -p "$RUN_DIR"

# Temp files scoped to this session (cleaned up on exit)
PROMPT_FILE="${RUN_DIR}/.prompt-tmp.md"
OUTPUT_FILE="${RUN_DIR}/.output-tmp.md"

cleanup() {
  rm -f "$PROMPT_FILE" "$OUTPUT_FILE" "${OUTPUT_FILE}.clean"
}
trap cleanup EXIT

# --- Snapshot original ---
cp "$PLAN_FILE" "${RUN_DIR}/original.md"

# --- Start logging (tee to run.log and stdout) ---
LOG_FILE="${RUN_DIR}/run.log"

log() {
  echo "$1" | tee -a "$LOG_FILE"
}

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

  # Determine role and agent: odd=reviewer, even=composer
  if (( PASS % 2 == 1 )); then
    ROLE="reviewer"
    AGENT_NAME="$ODD_AGENT"
  else
    ROLE="composer"
    AGENT_NAME="$EVEN_AGENT"
  fi

  # Read current plan content
  PLAN_CONTENT=$(cat "$PLAN_FILE")

  # Read role-specific preamble — gives each agent a distinct optimization lens
  ROLE_PREAMBLE=$(cat "$TEMPLATE_DIR/role-${ROLE}.md")

  # Read bounce protocol template and prepend role preamble
  PROTOCOL="${ROLE_PREAMBLE}
$(cat "$TEMPLATE_DIR/bounce-protocol.md")"

  # Build the filled prompt using bash parameter substitution
  # Replace scalar placeholders first
  FILLED="${PROTOCOL//\{TASK\}/Review and refine this document}"
  FILLED="${FILLED//\{PASS_NUMBER\}/$PASS}"
  FILLED="${FILLED//\{TOTAL_PASSES\}/$MAX_BOUNCES}"
  FILLED="${FILLED//\{YOUR_ROLE\}/$ROLE}"
  FILLED="${FILLED//\{WORKING_DIR\}/$WORKDIR}"
  # Replace plan content last (may contain special chars)
  FILLED="${FILLED//\{PLAN_CONTENT\}/$PLAN_CONTENT}"

  # Write prompt to temp file
  printf '%s' "$FILLED" > "$PROMPT_FILE"

  log "--------------------------------------------"
  log " BOUNCE $PASS/$MAX_BOUNCES - ${ROLE} (${AGENT_NAME})"
  log "--------------------------------------------"

  # Invoke the agent — plan content is inline in the prompt, never as a file path
  rm -f "$OUTPUT_FILE"
  STDERR_FILE="${RUN_DIR}/pass-${PASS}-stderr.log"
  "invoke_${AGENT_NAME}" "$PROMPT_FILE" "$OUTPUT_FILE" "$STDERR_FILE"

  # Check if output was produced
  if [[ ! -s "$OUTPUT_FILE" ]]; then
    log " ERROR: ${AGENT_NAME} returned empty output. Retrying once..."
    "invoke_${AGENT_NAME}" "$PROMPT_FILE" "$OUTPUT_FILE" "${RUN_DIR}/pass-${PASS}-stderr-retry.log"
    if [[ ! -s "$OUTPUT_FILE" ]]; then
      log " ERROR: ${AGENT_NAME} returned empty output on retry. Aborting."
      exit 1
    fi
  fi

  # Size sanity check — if output is less than 30% of input, the agent likely
  # returned a summary instead of the full document. Reject and retry.
  INPUT_WORDS=$(wc -w < "$PLAN_FILE" | tr -d '\r\n ')
  OUTPUT_WORDS=$(wc -w < "$OUTPUT_FILE" | tr -d '\r\n ')
  if (( INPUT_WORDS > 50 && OUTPUT_WORDS * 100 / INPUT_WORDS < 30 )); then
    log " WARNING: ${AGENT_NAME} returned ${OUTPUT_WORDS} words (input was ${INPUT_WORDS}). Likely a summary, not the full document. Retrying..."
    "invoke_${AGENT_NAME}" "$PROMPT_FILE" "$OUTPUT_FILE" "${RUN_DIR}/pass-${PASS}-stderr-retry.log"
    OUTPUT_WORDS=$(wc -w < "$OUTPUT_FILE" | tr -d '\r\n ')
    if (( OUTPUT_WORDS * 100 / INPUT_WORDS < 30 )); then
      log " WARNING: Retry also returned ${OUTPUT_WORDS} words. Using it anyway — check the output."
    fi
  fi

  # Save raw output (with HUMAN SUMMARY) as a per-pass artifact
  # Name includes pass number, role, and agent for at-a-glance scanning
  cp "$OUTPUT_FILE" "${RUN_DIR}/pass-${PASS}-${ROLE}-${AGENT_NAME}-raw.md"

  # Strip HUMAN SUMMARY from output before writing to canonical plan
  awk '/^## HUMAN SUMMARY/{found=1} !found{print}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.clean"
  mv "${OUTPUT_FILE}.clean" "$OUTPUT_FILE"

  # Orchestrator overwrites canonical plan with agent output
  cp "$OUTPUT_FILE" "$PLAN_FILE"

  # Count markers outside fenced code blocks AND outside inline backtick code
  # gsub strips `...` inline code before checking, so `[CONTESTED]` in prose doesn't count
  CONTESTED=$(awk 'BEGIN{c=0;f=0} /^```/{f=!f;next} !f{gsub(/`[^`]*`/,""); if(/\[CONTESTED\]/)c++} END{print c}' "$PLAN_FILE" | tr -d '\r\n ')
  CLARIFY=$(awk 'BEGIN{c=0;f=0} /^```/{f=!f;next} !f{gsub(/`[^`]*`/,""); if(/\[CLARIFY\]/)c++} END{print c}' "$PLAN_FILE" | tr -d '\r\n ')
  TOTAL_MARKERS=$((CONTESTED + CLARIFY))
  WORD_COUNT=$(wc -w < "$PLAN_FILE" | tr -d '\r\n ')

  log " [CONTESTED] markers: $CONTESTED"
  log " [CLARIFY] markers:   $CLARIFY"
  log " Plan length:         $WORD_COUNT words"
  log "--------------------------------------------"
  log ""

  # Convergence check
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

# --- Save final output (named after the run) ---
FINAL_NAME="${RUN_LABEL}.md"
cp "$PLAN_FILE" "${RUN_DIR}/${FINAL_NAME}"

log "============================================"
log " BOUNCE COMPLETE"
log "============================================"
log " Final plan: $PLAN_FILE"
log " Run dir:    $RUN_DIR"
log " Passes:     $FINAL_PASS / $MAX_BOUNCES"
log " Artifacts:"
log "   original.md                — input before bouncing"
for (( i=1; i<=FINAL_PASS; i++ )); do
  if (( i % 2 == 1 )); then R="reviewer"; A="$ODD_AGENT"; else R="composer"; A="$EVEN_AGENT"; fi
  log "   pass-${i}-${R}-${A}-raw.md — pass $i (${R}, ${A})"
done
log "   ${FINAL_NAME} — clean output"
log "   run.log                    — this log"
log "============================================"
