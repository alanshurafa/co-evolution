#!/usr/bin/env bash
set -euo pipefail

# Analyze grading results from multiple graders
# Reads all grades-*.csv files in results/ and produces a summary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ANALYSIS_FILE="$RESULTS_DIR/analysis-${TIMESTAMP}.md"

grade_files=($(ls "$RESULTS_DIR"/grades-*.csv 2>/dev/null))

if [[ ${#grade_files[@]} -eq 0 ]]; then
  echo "ERROR: no grade files found in $RESULTS_DIR"
  echo "Run grade-results.sh first, then add Gemini/Grok grades as grades-gemini-*.csv and grades-grok-*.csv"
  exit 1
fi

echo "# Role Ablation Analysis — ${TIMESTAMP}" > "$ANALYSIS_FILE"
echo "" >> "$ANALYSIS_FILE"
echo "## Graders: ${#grade_files[@]}" >> "$ANALYSIS_FILE"
for f in "${grade_files[@]}"; do
  echo "- $(basename "$f")" >> "$ANALYSIS_FILE"
done
echo "" >> "$ANALYSIS_FILE"

# Use awk to compute averages per config across all grade files
echo "## Average Scores by Config (across all graders and inputs)" >> "$ANALYSIS_FILE"
echo "" >> "$ANALYSIS_FILE"
echo "| Config | Disagreement | Convergence | Improvement | Appropriateness | Conciseness | Total |" >> "$ANALYSIS_FILE"
echo "|--------|-------------|-------------|-------------|-----------------|-------------|-------|" >> "$ANALYSIS_FILE"

for config in "no-roles" "light-roles" "heavy-roles"; do
  # Aggregate across all grade files
  awk -F',' -v cfg="$config" '
    NR > 1 && $1 == cfg && $3 > 0 {
      d += $3; c += $4; i += $5; a += $6; cn += $7; t += $8; n++
    }
    END {
      if (n > 0)
        printf "| %s | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |\n", cfg, d/n, c/n, i/n, a/n, cn/n, t/n
      else
        printf "| %s | - | - | - | - | - | - |\n", cfg
    }
  ' "${grade_files[@]}" >> "$ANALYSIS_FILE"
done

echo "" >> "$ANALYSIS_FILE"

# Per-input breakdown
echo "## Average Scores by Input (across all configs and graders)" >> "$ANALYSIS_FILE"
echo "" >> "$ANALYSIS_FILE"
echo "| Input | Disagreement | Convergence | Improvement | Appropriateness | Conciseness | Total |" >> "$ANALYSIS_FILE"
echo "|-------|-------------|-------------|-------------|-----------------|-------------|-------|" >> "$ANALYSIS_FILE"

for input_file in "$SCRIPT_DIR"/inputs/*.md; do
  input_name=$(basename "$input_file" .md)
  awk -F',' -v inp="$input_name" '
    NR > 1 && $2 == inp && $3 > 0 {
      d += $3; c += $4; i += $5; a += $6; cn += $7; t += $8; n++
    }
    END {
      if (n > 0)
        printf "| %s | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |\n", inp, d/n, c/n, i/n, a/n, cn/n, t/n
      else
        printf "| %s | - | - | - | - | - | - |\n", inp
    }
  ' "${grade_files[@]}" >> "$ANALYSIS_FILE"
done

echo "" >> "$ANALYSIS_FILE"

# Winner
echo "## Recommendation" >> "$ANALYSIS_FILE"
echo "" >> "$ANALYSIS_FILE"
echo "Config with highest average total score should be the default for co-evolve.sh." >> "$ANALYSIS_FILE"
echo "If scores are within 1 point, prefer the simpler config (no-roles > light-roles > heavy-roles)." >> "$ANALYSIS_FILE"
echo "" >> "$ANALYSIS_FILE"

# Raw data
echo "## Raw Grade Files" >> "$ANALYSIS_FILE"
echo "" >> "$ANALYSIS_FILE"
for f in "${grade_files[@]}"; do
  echo "### $(basename "$f")" >> "$ANALYSIS_FILE"
  echo '```' >> "$ANALYSIS_FILE"
  cat "$f" >> "$ANALYSIS_FILE"
  echo '```' >> "$ANALYSIS_FILE"
  echo "" >> "$ANALYSIS_FILE"
done

echo "Analysis written to: $ANALYSIS_FILE"
