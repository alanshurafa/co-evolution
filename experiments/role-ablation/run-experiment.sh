#!/usr/bin/env bash
set -euo pipefail

# Role Ablation Experiment
# Tests 10 diverse inputs x 3 role configurations = 30 bouncer runs
# Measures: marker counts, convergence, word counts, output quality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOUNCER="$REPO_ROOT/agent-bouncer/agent-bouncer.sh"
BOUNCER_TEMPLATES="$REPO_ROOT/agent-bouncer/templates"
INPUTS_DIR="$SCRIPT_DIR/inputs"
CONFIGS_DIR="$SCRIPT_DIR/configs"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SUMMARY_FILE="$RESULTS_DIR/summary-${TIMESTAMP}.csv"
MAX_BOUNCES=2
ODD_AGENT="${1:-claude}"
EVEN_AGENT="${2:-codex}"

# Ensure dependencies
source "$REPO_ROOT/lib/co-evolution.sh"
command -v "$ODD_AGENT" >/dev/null 2>&1 || command -v claude >/dev/null 2>&1 || {
  echo "ERROR: claude CLI not found"
  exit 1
}
command -v "$EVEN_AGENT" >/dev/null 2>&1 || command -v codex >/dev/null 2>&1 || {
  echo "ERROR: codex CLI not found"
  exit 1
}

configs=("no-roles" "light-roles" "heavy-roles")
inputs=($(ls "$INPUTS_DIR"/*.md | sort))

if [[ ${#inputs[@]} -eq 0 ]]; then
  echo "ERROR: no input files found in $INPUTS_DIR"
  exit 1
fi

echo "============================================"
echo " ROLE ABLATION EXPERIMENT"
echo "============================================"
echo " Inputs:    ${#inputs[@]}"
echo " Configs:   ${#configs[@]} (${configs[*]})"
echo " Bounces:   $MAX_BOUNCES per run"
echo " Agents:    $ODD_AGENT (odd), $EVEN_AGENT (even)"
echo " Results:   $RESULTS_DIR"
echo " Total:     $((${#inputs[@]} * ${#configs[@]})) runs"
echo "============================================"
echo ""

# CSV header
mkdir -p "$RESULTS_DIR"
echo "config,input,input_words,compose_words,pass1_contested,pass1_clarify,pass1_words,final_contested,final_clarify,final_words,converged,passes_used,run_dir" > "$SUMMARY_FILE"

# Backup original templates
BACKUP_DIR=$(mktemp -d)
cp "$BOUNCER_TEMPLATES/role-reviewer.md" "$BACKUP_DIR/role-reviewer.md"
cp "$BOUNCER_TEMPLATES/role-composer.md" "$BACKUP_DIR/role-composer.md"

restore_templates() {
  cp "$BACKUP_DIR/role-reviewer.md" "$BOUNCER_TEMPLATES/role-reviewer.md"
  cp "$BACKUP_DIR/role-composer.md" "$BOUNCER_TEMPLATES/role-composer.md"
  rm -rf "$BACKUP_DIR"
}
trap restore_templates EXIT

TOTAL_RUNS=$((${#inputs[@]} * ${#configs[@]}))
CURRENT_RUN=0

for config in "${configs[@]}"; do
  echo "============================================"
  echo " CONFIG: $config"
  echo "============================================"

  # Swap role templates
  cp "$CONFIGS_DIR/$config/role-reviewer.md" "$BOUNCER_TEMPLATES/role-reviewer.md"
  cp "$CONFIGS_DIR/$config/role-composer.md" "$BOUNCER_TEMPLATES/role-composer.md"

  for input_file in "${inputs[@]}"; do
    CURRENT_RUN=$((CURRENT_RUN + 1))
    input_name=$(basename "$input_file" .md)
    run_label="${config}__${input_name}"

    echo ""
    echo "--------------------------------------------"
    echo " [$CURRENT_RUN/$TOTAL_RUNS] $config / $input_name"
    echo "--------------------------------------------"

    # Copy input to a temp file (bouncer modifies in place)
    tmp_input=$(mktemp --suffix=.md)
    cp "$input_file" "$tmp_input"

    input_words=$(wc -w < "$input_file" | tr -d '\r\n ')

    # Run the bouncer
    bash "$BOUNCER" "$tmp_input" "$MAX_BOUNCES" "$ODD_AGENT" "$EVEN_AGENT" || true

    # Find the run directory (most recent bouncer-* dir)
    latest_run=$(ls -dt "$REPO_ROOT/runs/bouncer-"*/ 2>/dev/null | head -1)

    if [[ -z "$latest_run" ]]; then
      echo "  WARNING: no run directory found, skipping"
      echo "$config,$input_name,$input_words,0,0,0,0,0,0,0,false,0,MISSING" >> "$SUMMARY_FILE"
      rm -f "$tmp_input"
      continue
    fi

    # Extract metrics from the run
    compose_words=0
    pass1_contested=0
    pass1_clarify=0
    pass1_words=0
    final_contested=0
    final_clarify=0
    final_words=0
    converged="false"
    passes_used=0

    # Check if compose output exists (pass 1 raw)
    if [[ -f "$latest_run/pass-1-reviewer-${ODD_AGENT}-raw.md" ]]; then
      pass1_words=$(wc -w < "$latest_run/pass-1-reviewer-${ODD_AGENT}-raw.md" | tr -d '\r\n ')
      pass1_contested=$(count_markers "$latest_run/pass-1-reviewer-${ODD_AGENT}-raw.md" "[CONTESTED]")
      pass1_clarify=$(count_markers "$latest_run/pass-1-reviewer-${ODD_AGENT}-raw.md" "[CLARIFY]")
      passes_used=1
    fi

    # Check pass 2
    if [[ -f "$latest_run/pass-2-composer-${EVEN_AGENT}-raw.md" ]]; then
      passes_used=2
    fi

    # Find the clean final output
    final_file=$(ls "$latest_run"/*.md 2>/dev/null | grep -v "original\|pass-\|raw" | head -1)
    if [[ -n "$final_file" && -f "$final_file" ]]; then
      final_words=$(wc -w < "$final_file" | tr -d '\r\n ')
      final_contested=$(count_markers "$final_file" "[CONTESTED]")
      final_clarify=$(count_markers "$final_file" "[CLARIFY]")
    fi

    # Did it converge?
    if grep -q "converged" "$latest_run/run.log" 2>/dev/null; then
      converged="true"
    fi

    # Move run dir to results
    result_run_dir="$RESULTS_DIR/${run_label}"
    mv "$latest_run" "$result_run_dir"

    echo "  Pass 1: ${pass1_contested} contested, ${pass1_clarify} clarify, ${pass1_words} words"
    echo "  Final:  ${final_contested} contested, ${final_clarify} clarify, ${final_words} words"
    echo "  Converged: $converged in $passes_used passes"

    echo "$config,$input_name,$input_words,$compose_words,$pass1_contested,$pass1_clarify,$pass1_words,$final_contested,$final_clarify,$final_words,$converged,$passes_used,$result_run_dir" >> "$SUMMARY_FILE"

    rm -f "$tmp_input"
  done
done

echo ""
echo "============================================"
echo " EXPERIMENT COMPLETE"
echo "============================================"
echo " Results:   $RESULTS_DIR"
echo " Summary:   $SUMMARY_FILE"
echo " Total runs: $CURRENT_RUN"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Review results in $RESULTS_DIR"
echo "  2. Run grading: bash experiments/role-ablation/grade-results.sh"
echo "  3. Copy outputs to Gemini and Grok for independent grading"
