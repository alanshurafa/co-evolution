#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

RUN_ID=""
CONDITIONS="A,B,C"
TASK_LIMIT=1
MAX_CLAUDE=""
DRY_RUN=false

while (( $# > 0 )); do
  case "$1" in
    --run-id) RUN_ID="${2:?--run-id needs a value}"; shift 2 ;;
    --conditions) CONDITIONS="${2:?--conditions needs a value}"; shift 2 ;;
    --task-limit) TASK_LIMIT="${2:?--task-limit needs a value}"; shift 2 ;;
    --max-claude-dispatches) MAX_CLAUDE="${2:?--max-claude-dispatches needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) code_die "unknown canary option: $1"; exit 2 ;;
  esac
done

[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { code_die "--run-id is required and must be filesystem-safe"; exit 2; }
[[ "$TASK_LIMIT" =~ ^[1-9][0-9]*$ ]] || { code_die "--task-limit must be positive"; exit 2; }
[[ "$MAX_CLAUDE" =~ ^[0-9]+$ ]] || { code_die "--max-claude-dispatches is required"; exit 2; }

bash "$CODE_DIR/estimate-compute.sh" --suite swebench-verified-canary \
  --conditions "$CONDITIONS" --task-limit "$TASK_LIMIT" \
  --max-claude-dispatches "$MAX_CLAUDE"

if [[ "$DRY_RUN" == true ]]; then
  printf 'DRY RUN: no repositories cloned and no providers invoked.\n'
  exit 0
fi

suite_json=$(code_suite_json "swebench-verified-canary")
subset=$(code_subset_path "$suite_json")
pred_dir="$CODE_BENCH_RESULTS_ROOT/predictions/$RUN_ID"
mkdir -p "$pred_dir"

task_index=0
while IFS= read -r instance; do
  task_index=$((task_index + 1))
  (( task_index <= TASK_LIMIT )) || break
  old_ifs=$IFS
  IFS=','
  for condition in $CONDITIONS; do
    input=$(bash "$CODE_DIR/scripts/prepare-swebench-instance.sh" "$instance" "$RUN_ID" "$condition")
    per_condition=$(jq -r --arg id "$condition" '.conditions[] | select(.id == $id) | .dispatches.claude' \
      "$CODE_DIR/conditions.json" | tr -d '\r')
    bash "$CODE_DIR/drivers/run-workflow.sh" --input "$input" \
      --predictions "$pred_dir/$condition.jsonl" \
      --max-claude-dispatches "$per_condition"
  done
  IFS=$old_ifs
done < <(jq -r '.instances[].instance_id' "$subset" | tr -d '\r')

for predictions in "$pred_dir"/*.jsonl; do
  bash "$CODE_DIR/validate-predictions.sh" "$predictions" swebench-verified-canary
done
printf 'COMPLETE: canary predictions -> %s\n' "$pred_dir"
