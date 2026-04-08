#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/co-evolution.sh"

# --- Defaults ---
SKIP_INTERVIEW=false
AUTO=false
EXOCORTEX_QUERY=""
CONTEXT_FILE=""
AUDIENCE=""
LENS=""
CHAIN=false
MAX_BOUNCES=2
AGENT_A="claude"
AGENT_B="codex"
BOUNCE_ONLY=false
OUTPUT_FILE=""
TASK=""
INPUT_CONTENT=""
INPUT_TYPE=""  # "string", "file", or "pipe"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

TEMPLATE_DIR="$SCRIPT_DIR/templates/co-evolve"
PROTOCOL_TEMPLATE="$SCRIPT_DIR/agent-bouncer/templates/bounce-protocol.md"

# Validate templates exist
for _tmpl in "$TEMPLATE_DIR/role-reviewer-light.md" "$TEMPLATE_DIR/role-composer-light.md" \
             "$TEMPLATE_DIR/chain-critique.md" "$TEMPLATE_DIR/chain-defend.md" \
             "$TEMPLATE_DIR/chain-tighten.md" "$PROTOCOL_TEMPLATE"; do
  [[ -f "$_tmpl" ]] || die "Missing template: $_tmpl"
done

# --- Usage ---
usage() {
  cat <<'USAGE'
Usage:
  co-evolve [OPTIONS] <input>

  input can be a question ("quoted string"), a file path, or piped stdin.

Options:
  --skip-interview   Skip the opening interview questions
  --auto             Skip human checks between passes
  --vanilla          Shorthand for --skip-interview --auto
  --exocortex QUERY  Search ExoCortex for relevant context
  --context FILE     Include a file as background context (not bounced; one file, concatenate if needed)
  --audience WHO     Prime agents for a specific reader
  --lens NAME        Use a named adversarial lens (replaces auto-shaped roles)
  --chain            Use staged passes: critique -> defend -> tighten
  --bounces N        Max bounce passes (default: 2, ignored with --chain)
  --agents A,B       Agent pair (default: claude,codex)
  --dev-review       Add execute + verify phases after bounce
  --bounce-only      Skip compose, bounce a file directly
  --output FILE      Write final output to a file instead of stdout
  --help             Show this help text
USAGE
  exit 0
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) usage ;;
    --skip-interview) SKIP_INTERVIEW=true; shift ;;
    --auto) AUTO=true; shift ;;
    --vanilla) SKIP_INTERVIEW=true; AUTO=true; shift ;;
    --exocortex) EXOCORTEX_QUERY="$2"; shift 2 ;;
    --context) CONTEXT_FILE="$2"; shift 2 ;;
    --audience) AUDIENCE="$2"; shift 2 ;;
    --lens) LENS="$2"; shift 2 ;;
    --chain) CHAIN=true; shift ;;
    --bounces)
      MAX_BOUNCES="$2"
      [[ "$MAX_BOUNCES" =~ ^[0-9]+$ ]] || die "--bounces must be a positive integer, got: $MAX_BOUNCES"
      shift 2
      ;;
    --agents)
      AGENT_A="${2%%,*}"
      AGENT_B="${2#*,}"
      AGENT_B="${AGENT_B%%,*}"
      [[ "$2" == *","*","* ]] && die "--agents requires exactly two agents (e.g., claude,codex)"
      [[ -z "$AGENT_A" || -z "$AGENT_B" ]] && die "--agents requires exactly two agents separated by comma (e.g., claude,codex)"
      shift 2
      ;;
    --dev-review) die "--dev-review is not yet implemented. Use dev-review/codex/dev-review.sh directly." ;;
    --bounce-only) BOUNCE_ONLY=true; shift ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --)
      shift
      TASK="$*"
      break
      ;;
    -*)
      die "Unknown flag: $1. Use --help for usage."
      ;;
    *)
      if [[ -z "$TASK" ]]; then
        TASK="$1"
      else
        TASK="${TASK} $1"
      fi
      shift
      ;;
  esac
done

# --- Input Detection ---
if [[ -n "$TASK" && -f "$TASK" ]]; then
  INPUT_TYPE="file"
  INPUT_CONTENT=$(cat "$TASK")
elif [[ -n "$TASK" ]]; then
  INPUT_TYPE="string"
  INPUT_CONTENT="$TASK"
elif [[ ! -t 0 ]]; then
  INPUT_TYPE="pipe"
  INPUT_CONTENT=$(cat)
  TASK="(piped input)"
else
  echo "Error: no input provided. Pass a question, file, or pipe stdin." >&2
  echo "Use --help for usage." >&2
  exit 1
fi

# --- Run Directory ---
RUN_LABEL=$(echo "$TASK" | head -c 60 | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//;s/-$//')
RUN_LABEL="${RUN_LABEL:-co-evolve}"
RUN_DIR="$SCRIPT_DIR/runs/co-evolve-${RUN_LABEL}-${TIMESTAMP}"
mkdir -p "$RUN_DIR"
LOG_FILE="$RUN_DIR/run.log"
WORKING_FILE="$RUN_DIR/working.md"

printf '%s' "$INPUT_CONTENT" > "$RUN_DIR/original-input.md"

# --- Interview Phase ---
run_interview() {
  log ""
  log "--- INTERVIEW ---"

  if [[ -z "$AUDIENCE" ]]; then
    printf 'Who is the audience for this? (e.g., judge, co-parent, lawyer, general) [general]: ' > /dev/tty
    read -r AUDIENCE < /dev/tty
    AUDIENCE="${AUDIENCE:-general}"
  fi
  log " Audience: $AUDIENCE"

  if [[ -z "$EXOCORTEX_QUERY" ]]; then
    printf 'Search your ExoCortex for relevant context? [y/N]: ' > /dev/tty
    read -r exo_answer < /dev/tty
    if [[ "$exo_answer" =~ ^[Yy] ]]; then
      printf 'What should I search for? ' > /dev/tty
      read -r EXOCORTEX_QUERY < /dev/tty
    fi
  fi
  if [[ -n "$EXOCORTEX_QUERY" ]]; then
    log " ExoCortex query: $EXOCORTEX_QUERY"
  fi

  if [[ -z "$CONTEXT_FILE" ]]; then
    printf 'Any files to include as context? (path or Enter to skip): ' > /dev/tty
    read -r CONTEXT_FILE < /dev/tty
  fi
  if [[ -n "$CONTEXT_FILE" ]]; then
    log " Context file: $CONTEXT_FILE"
  fi

  printf 'What kind of output do you want? (e.g., argument, email draft, analysis, plan) [auto]: ' > /dev/tty
  read -r OUTPUT_TYPE < /dev/tty
  OUTPUT_TYPE="${OUTPUT_TYPE:-auto}"
  log " Output type: $OUTPUT_TYPE"

  log "--- END INTERVIEW ---"
  log ""
}

if [[ "$SKIP_INTERVIEW" == "false" ]]; then
  run_interview
fi

# --- Context Enrichment ---
CONTEXT_BLOCK=""

if [[ -n "$EXOCORTEX_QUERY" ]]; then
  log "NOTE: ExoCortex CLI search not yet available. Use --context with a file or run from Claude Code for ExoCortex integration."
fi

if [[ -n "$CONTEXT_FILE" && ! -f "$CONTEXT_FILE" ]]; then
  die "Context file not found: $CONTEXT_FILE"
fi

if [[ -n "$CONTEXT_FILE" && -f "$CONTEXT_FILE" ]]; then
  CONTEXT_BLOCK="## Background Context

$(cat "$CONTEXT_FILE")

---

"
  log " Loaded context from: $CONTEXT_FILE ($(wc -w < "$CONTEXT_FILE" | tr -d '\r\n ') words)"
fi

# --- Role Preamble Generation ---
build_reviewer_preamble() {
  if [[ -n "$LENS" ]]; then
    echo "You are the ${LENS} reviewing this work. Be adversarial from that perspective. Every critique must include a concrete alternative."
  elif [[ "$SKIP_INTERVIEW" == "true" ]]; then
    cat "$TEMPLATE_DIR/role-reviewer-light.md"
  else
    local preamble
    preamble=$(cat "$TEMPLATE_DIR/role-reviewer-light.md")
    if [[ -n "$AUDIENCE" && "$AUDIENCE" != "general" && "$AUDIENCE" != "auto" ]]; then
      preamble="${preamble}Evaluate this as if you are a ${AUDIENCE} reading it. What would they find unconvincing, unclear, or missing?"
    fi
    echo "$preamble"
  fi
}

build_composer_preamble() {
  if [[ -n "$LENS" ]]; then
    echo "Resolve all critiques from the ${LENS} perspective. Strengthen weak points. Make it bulletproof."
  elif [[ "$SKIP_INTERVIEW" == "true" ]]; then
    cat "$TEMPLATE_DIR/role-composer-light.md"
  else
    local preamble
    preamble=$(cat "$TEMPLATE_DIR/role-composer-light.md")
    if [[ -n "${OUTPUT_TYPE:-}" && "$OUTPUT_TYPE" != "auto" ]]; then
      preamble="${preamble}The output should be a ${OUTPUT_TYPE}. Shape it accordingly."
    fi
    echo "$preamble"
  fi
}

# --- Agent Invocation Helper ---
invoke_agent() {
  local agent="$1"
  local prompt_file="$2"
  local output_file="$3"
  local stderr_file="$4"

  case "$agent" in
    claude) invoke_claude "$prompt_file" "$output_file" "$stderr_file" ;;
    codex)  invoke_codex "$prompt_file" "$output_file" "$stderr_file" ;;
    *)      die "Unknown agent: $agent" ;;
  esac
}

# --- Compose Phase ---
run_compose_phase() {
  local compose_prompt_file="$RUN_DIR/.compose-prompt.md"
  local compose_output_file="$RUN_DIR/compose-output.md"
  local compose_stderr_file="$RUN_DIR/compose-stderr.log"
  local compose_retry_stderr_file="$RUN_DIR/compose-stderr-retry.log"
  local compose_prompt

  if [[ "$INPUT_TYPE" == "file" ]]; then
    compose_prompt="Review and improve the following document. Identify gaps, strengthen weak points, and tighten the language.

${CONTEXT_BLOCK}${INPUT_CONTENT}"
  else
    compose_prompt="Respond to the following thoroughly and substantively.

${CONTEXT_BLOCK}${INPUT_CONTENT}"
  fi

  printf '%s' "$compose_prompt" > "$compose_prompt_file"

  log "--- COMPOSE PHASE ---"
  log " Agent: $AGENT_A"
  log " Input: $INPUT_TYPE ($(echo "$INPUT_CONTENT" | wc -w | tr -d '\r\n ') words)"

  invoke_agent "$AGENT_A" "$compose_prompt_file" "$compose_output_file" "$compose_stderr_file"

  if [[ ! -s "$compose_output_file" ]] || (( $(wc -w < "$compose_output_file" | tr -d '\r\n ') < 10 )); then
    log " WARNING: compose returned empty or minimal output. Retrying once..."
    : > "$compose_output_file"
    invoke_agent "$AGENT_A" "$compose_prompt_file" "$compose_output_file" "$compose_retry_stderr_file"
  fi

  if [[ ! -s "$compose_output_file" ]]; then
    log " ERROR: compose returned empty output on retry."
    return 1
  fi

  local compose_words
  compose_words=$(wc -w < "$compose_output_file" | tr -d '\r\n ')
  log " Compose output: $compose_words words"
  log "--- END COMPOSE ---"
  log ""

  cp "$compose_output_file" "$WORKING_FILE"
}

# --- Bounce Phase ---
run_bounce_phase() {
  local pass
  local role
  local current_agent
  local role_preamble
  local protocol
  local filled
  local prompt_file
  local output_file
  local stderr_file
  local clean_file

  local total_passes="$MAX_BOUNCES"
  if [[ "$CHAIN" == "true" ]]; then
    total_passes=3
  fi

  for (( pass=1; pass<=total_passes; pass++ )); do
    prompt_file="$RUN_DIR/.bounce-pass-${pass}-prompt.md"
    output_file="$RUN_DIR/.bounce-pass-${pass}-output.md"
    stderr_file="$RUN_DIR/pass-${pass}-stderr.log"
    clean_file="$RUN_DIR/.bounce-pass-${pass}-clean.md"

    # Determine agent and role
    if (( pass % 2 == 1 )); then
      current_agent="$AGENT_A"
      if [[ "$CHAIN" == "true" ]]; then
        case "$pass" in
          1) role_preamble=$(cat "$TEMPLATE_DIR/chain-critique.md") ;;
          3) role_preamble=$(cat "$TEMPLATE_DIR/chain-tighten.md") ;;
        esac
        role="critique"
        [[ "$pass" == "3" ]] && role="tighten"
      else
        role_preamble=$(build_reviewer_preamble)
        role="reviewer"
      fi
    else
      current_agent="$AGENT_B"
      if [[ "$CHAIN" == "true" ]]; then
        role_preamble=$(cat "$TEMPLATE_DIR/chain-defend.md")
        role="defend"
      else
        role_preamble=$(build_composer_preamble)
        role="composer"
      fi
    fi

    # Build prompt — avoid bash string replacement for user-controlled values
    # to prevent corruption of & > \ and other special chars in TASK and paths.
    # Only substitute safe integer/keyword values inline; append everything else.
    protocol="${role_preamble}
$(cat "$PROTOCOL_TEMPLATE")"

    # Safe substitutions (integers and single keywords only)
    protocol="${protocol//\{PASS_NUMBER\}/$pass}"
    protocol="${protocol//\{TOTAL_PASSES\}/$total_passes}"
    protocol="${protocol//\{YOUR_ROLE\}/$role}"

    # Remove placeholders for values we'll append separately
    protocol="${protocol//\{TASK\}/see TASK section below}"
    protocol="${protocol//\{WORKING_DIR\}/see TASK section below}"
    protocol="${protocol//\{PLAN_CONTENT\}/see DOCUMENT section below}"

    {
      printf '%s\n\n' "$protocol"
      printf '## TASK\n\n%s\n\n' "$TASK"
      printf '## WORKING DIRECTORY\n\n%s\n\n' "$SCRIPT_DIR"
      printf '## DOCUMENT TO REVIEW\n\n'
      cat "$WORKING_FILE"
    } > "$prompt_file"

    log "--------------------------------------------"
    log " BOUNCE $pass/$total_passes - ${role} (${current_agent})"
    log "--------------------------------------------"

    invoke_agent "$current_agent" "$prompt_file" "$output_file" "$stderr_file"

    # Validate output
    if [[ ! -s "$output_file" ]]; then
      log " WARNING: ${current_agent} returned empty output. Retrying..."
      invoke_agent "$current_agent" "$prompt_file" "$output_file" "$stderr_file"
    fi

    if [[ ! -s "$output_file" ]]; then
      log " ERROR: ${current_agent} returned empty output on retry. Stopping."
      break
    fi

    cp "$output_file" "$RUN_DIR/pass-${pass}-${role}-${current_agent}-raw.md"

    strip_human_summary "$output_file" "$clean_file"
    cp "$clean_file" "$WORKING_FILE"

    # Marker counts
    local contested clarify total_markers word_count
    contested=$(count_markers "$WORKING_FILE" "[CONTESTED]")
    clarify=$(count_markers "$WORKING_FILE" "[CLARIFY]")
    total_markers=$((contested + clarify))
    word_count=$(wc -w < "$WORKING_FILE" | tr -d '\r\n ')

    log " [CONTESTED] markers: $contested"
    log " [CLARIFY] markers:   $clarify"
    log " Length:              $word_count words"
    log "--------------------------------------------"
    log ""

    # Human check
    if [[ "$AUTO" == "false" ]]; then
      printf '\nPass %d complete. %d [CONTESTED], %d [CLARIFY] markers.\n' "$pass" "$contested" "$clarify" > /dev/tty
      printf 'Press Enter to continue, "e" to edit, "s" to stop: ' > /dev/tty
      read -r human_input < /dev/tty
      case "$human_input" in
        e|E)
          "${EDITOR:-nano}" "$WORKING_FILE" < /dev/tty > /dev/tty
          log " Human edited the working file after pass $pass."
          ;;
        s|S)
          log " Human stopped after pass $pass."
          break
          ;;
      esac
    fi

    # Early convergence (standard mode only)
    if [[ "$CHAIN" == "false" && "$total_markers" -eq 0 ]]; then
      log "Converged after $pass passes (no open markers)."
      log ""
      break
    fi
  done
}

# --- Banner ---
log "============================================"
log " CO-EVOLVE SESSION"
log "============================================"
log " Input:     $INPUT_TYPE"
log " Task:      $(echo "$TASK" | head -c 80)"
log " Compose:   $AGENT_A"
log " Bounce:    $AGENT_A / $AGENT_B"
if [[ "$CHAIN" == "true" ]]; then
  log " Mode:      chain (critique -> defend -> tighten)"
else
  log " Mode:      standard ($MAX_BOUNCES passes)"
fi
log " Interview: $([[ "$SKIP_INTERVIEW" == "true" ]] && echo "skipped" || echo "completed")"
log " Auto:      $AUTO"
log " Run dir:   $RUN_DIR"
log "============================================"
log ""

# --- Execute Pipeline ---
if [[ "$BOUNCE_ONLY" == "true" ]]; then
  if [[ "$INPUT_TYPE" != "file" ]]; then
    die "--bounce-only requires a file input"
  fi
  cp "$RUN_DIR/original-input.md" "$WORKING_FILE"
  log "Skipping compose (--bounce-only). Bouncing file directly."
  log ""
else
  run_compose_phase || exit 1
fi

run_bounce_phase

# --- Output ---
FINAL_FILE="$RUN_DIR/${RUN_LABEL}.md"
cp "$WORKING_FILE" "$FINAL_FILE"

if [[ -n "$OUTPUT_FILE" ]]; then
  cp "$FINAL_FILE" "$OUTPUT_FILE"
  log "Output written to: $OUTPUT_FILE"
fi

log "============================================"
log " CO-EVOLVE COMPLETE"
log "============================================"
log " Task:      $(echo "$TASK" | head -c 80)"
log " Run dir:   $RUN_DIR"
log " Final:     $FINAL_FILE"
log "============================================"

# Print clean result to stdout unless output was redirected to file
if [[ -z "$OUTPUT_FILE" ]]; then
  cat "$FINAL_FILE"
fi
