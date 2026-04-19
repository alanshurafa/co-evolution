#!/usr/bin/env bash
# evals/compare-reports.sh
# Port of runners/codex-ps/evals/compare-reports.ps1 (BASH-EVAL-01 Plan 02-03 Task 2b).
#
# Compare two eval report directories. Reads raw-scores.json from each and emits
# a per-case dimension-diff markdown table. Exits 0 iff no case regressed on
# Robustness; exits 1 otherwise (matches compare-reports.ps1:105-110).
#
# Usage:
#   bash evals/compare-reports.sh --before DIR --after DIR [--output PATH]
#
# Dependencies: bash, jq. No yq (YAML not parsed here). No pwsh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/co-evolution.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/co-evolution-evals.sh"

usage() {
  cat <<'EOF'
Usage: evals/compare-reports.sh --before DIR --after DIR [--output PATH]

Compare two eval report directories and print a per-case dimension-diff table.

Required:
  --before DIR          Older report dir (e.g. evals/reports/20260417-080000)
  --after DIR           Newer report dir
Optional:
  --output PATH         Write markdown to PATH (default: stdout)
  --help, -h            Show this help and exit 0

Exit 0 iff no case regressed on Robustness; 1 otherwise.
EOF
}

BEFORE=""
AFTER=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before) [[ $# -gt 1 ]] || die "--before requires a value"; BEFORE="$2"; shift 2 ;;
    --after)  [[ $# -gt 1 ]] || die "--after requires a value";  AFTER="$2";  shift 2 ;;
    --output) [[ $# -gt 1 ]] || die "--output requires a value"; OUTPUT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    -*) die "Unknown flag: $1" ;;
    *)  die "Unexpected positional arg: $1" ;;
  esac
done

[[ -n "$BEFORE" ]] || { usage; die "--before is required"; }
[[ -n "$AFTER" ]]  || { usage; die "--after is required"; }
[[ -f "$BEFORE/raw-scores.json" ]] || die "raw-scores.json missing in $BEFORE"
[[ -f "$AFTER/raw-scores.json" ]]  || die "raw-scores.json missing in $AFTER"

ensure_jq

# ---------------------------------------------------------------------------
# Two-file diff via jq --slurpfile (mirrors lib/co-evolution.sh::compute_execute_delta:787-798).
# Score ordering map matches compare-reports.ps1:47.
# ---------------------------------------------------------------------------

diff_json=$(jq -n \
  --slurpfile b "$BEFORE/raw-scores.json" \
  --slurpfile a "$AFTER/raw-scores.json" \
  '
  ($b[0] // []) as $B | ($a[0] // []) as $A |
  ($B | map({key: .case_id, value: .}) | from_entries) as $BM |
  ($A | map({key: .case_id, value: .}) | from_entries) as $AM |
  ["robustness","convergence","plan_quality","execution_fidelity","verify_accuracy","cost","cross_ai_diversity"] as $dims |
  {PASS: 3, PARTIAL: 2, FAIL: 1, "N/A": null, "?": 0} as $VAL |
  (($BM | keys) + ($AM | keys) | unique | sort) as $case_ids |
  {
    rows: [
      $case_ids[] as $id |
      {
        case_id: $id,
        cells: [
          $dims[] as $d |
          (($BM[$id].scores[$d]) // "?") as $bv |
          (($AM[$id].scores[$d]) // "?") as $av |
          {
            dim: $d,
            before: $bv,
            after:  $av,
            indicator: (
              ($VAL[$bv]) as $bn | ($VAL[$av]) as $an |
              if ($bn != null and $an != null) then
                if $an < $bn then "↓"
                elif $an > $bn then "↑"
                else "" end
              else "" end
            )
          }
        ]
      }
    ]
  } |
  . + {
    regressions: ([.rows[]?.cells[]? | select(.indicator == "↓")] | length),
    robustness_regressions: ([.rows[]?.cells[]? | select(.dim == "robustness" and .indicator == "↓")] | length)
  }
  ')

# Per-row markdown line: "| <id> | <before>→<after> <arrow> | ... |"
rows_md=$(echo "$diff_json" | jq -r '
  .rows[] |
  "| \(.case_id) | " +
  (.cells | map("\(.before)→\(.after) \(.indicator)" | sub(" $"; "")) | join(" | ")) +
  " |"
')

regressions=$(echo "$diff_json" | jq -r '.regressions')
rob_regressions=$(echo "$diff_json" | jq -r '.robustness_regressions')

body=$(cat <<EOF
# Eval Comparison

**Before:** \`$BEFORE\`
**After:**  \`$AFTER\`

**Regressions:** $regressions total, $rob_regressions on Robustness

## Per-Case Dimension Diff

| Case | robustness | convergence | plan_quality | execution_fidelity | verify_accuracy | cost | cross_ai_diversity |
|------|------------|-------------|--------------|--------------------|-----------------|------|--------------------|
$rows_md

## Legend

- \`↓\` regression (score dropped)
- \`↑\` improvement
- No arrow: unchanged
EOF
)

if [[ -n "$OUTPUT" ]]; then
  printf '%s\n' "$body" > "$OUTPUT"
  log "wrote: $OUTPUT"
else
  printf '%s\n' "$body"
fi

if (( rob_regressions > 0 )); then
  log "FAIL: $rob_regressions case(s) regressed on Robustness"
  exit 1
fi
exit 0
