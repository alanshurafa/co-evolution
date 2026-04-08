#!/usr/bin/env bash
set -euo pipefail

# Grade the role ablation experiment results using Claude CLI
# Produces a CSV of scores per the RUBRIC.md dimensions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
INPUTS_DIR="$SCRIPT_DIR/inputs"
RUBRIC_FILE="$SCRIPT_DIR/RUBRIC.md"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
GRADES_FILE="$RESULTS_DIR/grades-claude-${TIMESTAMP}.csv"

if [[ ! -f "$RUBRIC_FILE" ]]; then
  echo "ERROR: RUBRIC.md not found at $RUBRIC_FILE"
  exit 1
fi

RUBRIC_CONTENT=$(cat "$RUBRIC_FILE")

configs=("no-roles" "light-roles" "heavy-roles")
inputs=($(ls "$INPUTS_DIR"/*.md 2>/dev/null | sort))

if [[ ${#inputs[@]} -eq 0 ]]; then
  echo "ERROR: no inputs found"
  exit 1
fi

echo "config,input,disagreement,convergence,improvement,appropriateness,conciseness,total,notes" > "$GRADES_FILE"

TOTAL=$((${#inputs[@]} * ${#configs[@]}))
CURRENT=0

echo "============================================"
echo " GRADING EXPERIMENT RESULTS"
echo "============================================"
echo " Grading $TOTAL outputs with Claude"
echo " Output: $GRADES_FILE"
echo "============================================"
echo ""

for config in "${configs[@]}"; do
  for input_file in "${inputs[@]}"; do
    CURRENT=$((CURRENT + 1))
    input_name=$(basename "$input_file" .md)
    run_label="${config}__${input_name}"
    run_dir="$RESULTS_DIR/$run_label"

    echo "[$CURRENT/$TOTAL] Grading $run_label..."

    if [[ ! -d "$run_dir" ]]; then
      echo "  SKIP: run directory not found"
      echo "$config,$input_name,0,0,0,0,0,0,\"MISSING RUN\"" >> "$GRADES_FILE"
      continue
    fi

    # Find the final clean output (not original, not pass-N, not raw)
    final_file=$(ls "$run_dir"/*.md 2>/dev/null | grep -v "original\|pass-\|raw" | head -1)

    if [[ -z "$final_file" || ! -s "$final_file" ]]; then
      echo "  SKIP: no final output found"
      echo "$config,$input_name,0,0,0,0,0,0,\"NO FINAL OUTPUT\"" >> "$GRADES_FILE"
      continue
    fi

    original_content=$(cat "$input_file")
    final_content=$(cat "$final_file")

    # Build grading prompt
    grade_prompt="You are grading the output of a co-evolution bounce experiment. You must be a strict, honest grader.

RUBRIC:
${RUBRIC_CONTENT}

ORIGINAL INPUT:
---
${original_content}
---

FINAL OUTPUT (after bouncing between two AIs with config: ${config}):
---
${final_content}
---

Grade this output on the 5 dimensions from the rubric. Be strict — a 3 is average, 5 is exceptional.

Respond with EXACTLY one line in this CSV format, no other text:
disagreement,convergence,improvement,appropriateness,conciseness,\"brief note in quotes\"

Example: 4,3,3,5,4,\"Strong pushback but convergence rushed\""

    # Write prompt to temp file and invoke Claude
    tmp_prompt=$(mktemp --suffix=.md)
    tmp_output=$(mktemp --suffix=.md)
    tmp_stderr=$(mktemp)
    printf '%s' "$grade_prompt" > "$tmp_prompt"

    claude -p --output-format text --model claude-opus-4-6 --tools "" < "$tmp_prompt" > "$tmp_output" 2>"$tmp_stderr" || true

    if [[ -s "$tmp_output" ]]; then
      # Extract the CSV line (first line that looks like scores)
      scores_line=$(grep -E '^[0-9],[0-9],[0-9],[0-9],[0-9],' "$tmp_output" | head -1)
      if [[ -n "$scores_line" ]]; then
        # Calculate total
        IFS=',' read -r d c i a cn rest <<< "$scores_line"
        total=$((d + c + i + a + cn))
        echo "$config,$input_name,$d,$c,$i,$a,$cn,$total,$rest" >> "$GRADES_FILE"
        echo "  Scores: D=$d C=$c I=$i A=$a Cn=$cn Total=$total"
      else
        # Couldn't parse, save raw output
        raw=$(head -1 "$tmp_output" | tr '\n' ' ' | cut -c1-80)
        echo "$config,$input_name,0,0,0,0,0,0,\"PARSE ERROR: $raw\"" >> "$GRADES_FILE"
        echo "  WARNING: couldn't parse grading output"
      fi
    else
      echo "$config,$input_name,0,0,0,0,0,0,\"EMPTY RESPONSE\"" >> "$GRADES_FILE"
      echo "  WARNING: Claude returned empty output"
    fi

    rm -f "$tmp_prompt" "$tmp_output" "$tmp_stderr"
  done
done

echo ""
echo "============================================"
echo " GRADING COMPLETE"
echo "============================================"
echo " Grades: $GRADES_FILE"
echo "============================================"
echo ""
echo "Next: copy final outputs + rubric to Gemini and Grok for independent grading."
echo "Compile all grader CSVs and compare with: experiments/role-ablation/analyze-grades.sh"
