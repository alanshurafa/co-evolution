#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/code-bench-lib.sh
source "$SCRIPT_DIR/lib/code-bench-lib.sh"

SUITE="swebench-verified-canary"
CONDITIONS=""
MAX_CLAUDE=""
TASK_LIMIT=""
JSON=false

while (( $# > 0 )); do
  case "$1" in
    --suite) SUITE="${2:?--suite needs a value}"; shift 2 ;;
    --conditions) CONDITIONS="${2:?--conditions needs a value}"; shift 2 ;;
    --max-claude-dispatches) MAX_CLAUDE="${2:?--max-claude-dispatches needs a value}"; shift 2 ;;
    --task-limit) TASK_LIMIT="${2:?--task-limit needs a value}"; shift 2 ;;
    --json) JSON=true; shift ;;
    *) code_die "unknown estimate option: $1"; exit 2 ;;
  esac
done

suite_json=$(code_suite_json "$SUITE") || { code_die "unknown suite: $SUITE"; exit 1; }
subset=$(code_subset_path "$suite_json")
tasks=$(jq '.instances | length' "$subset" | tr -d '\r')
if [[ -n "$TASK_LIMIT" ]]; then
  [[ "$TASK_LIMIT" =~ ^[1-9][0-9]*$ ]] || { code_die "--task-limit must be a positive integer"; exit 2; }
  (( TASK_LIMIT <= tasks )) || { code_die "--task-limit $TASK_LIMIT exceeds suite size $tasks"; exit 2; }
  tasks="$TASK_LIMIT"
fi

if [[ -z "$CONDITIONS" ]]; then
  CONDITIONS=$(printf '%s' "$suite_json" | jq -r '.default_conditions | join(",")' | tr -d '\r')
fi

selected='[]'
old_ifs=$IFS
IFS=','
for condition in $CONDITIONS; do
  row=$(jq -ce --arg id "$condition" '.conditions | map(select(.id == $id)) | if length == 1 then .[0] else empty end' "$SCRIPT_DIR/conditions.json") \
    || { IFS=$old_ifs; code_die "unknown condition: $condition"; exit 1; }
  selected=$(jq -c --argjson row "$row" '. + [$row]' <<<"$selected")
done
IFS=$old_ifs

summary=$(jq -cn --arg suite "$SUITE" --argjson tasks "$tasks" --argjson conditions "$selected" '
  def total($p): ([$conditions[].dispatches[$p]] | add // 0) * $tasks;
  {
    schema: "code-bench-compute-estimate/1.0",
    suite: $suite,
    tasks: $tasks,
    conditions: [$conditions[].id],
    cells: ($tasks * ($conditions | length)),
    declared_dispatches: {
      claude: total("claude"), codex: total("codex"),
      glm: total("glm"), kimi: total("kimi")
    },
    caveat: "Declared dispatches are a lower bound; a coding-agent dispatch may contain multiple model turns."
  }')

claude_calls=$(printf '%s' "$summary" | jq -r '.declared_dispatches.claude' | tr -d '\r')
if [[ -n "$MAX_CLAUDE" ]]; then
  [[ "$MAX_CLAUDE" =~ ^[0-9]+$ ]] || { code_die "--max-claude-dispatches must be a non-negative integer"; exit 2; }
  if (( claude_calls > MAX_CLAUDE )); then
    printf 'REFUSED: estimate requires %s declared Claude dispatches; cap is %s.\n' "$claude_calls" "$MAX_CLAUDE" >&2
    exit 75
  fi
fi

if [[ "$JSON" == true ]]; then
  printf '%s\n' "$summary" | jq .
else
  printf 'Compute estimate — %s\n' "$SUITE"
  printf '  tasks: %s | conditions: %s | cells: %s\n' \
    "$tasks" "$(printf '%s' "$summary" | jq -r '.conditions | join(",")')" "$(printf '%s' "$summary" | jq -r '.cells')"
  for provider in claude codex glm kimi; do
    printf '  %-6s declared dispatches: %s\n' "$provider" "$(printf '%s' "$summary" | jq -r --arg p "$provider" '.declared_dispatches[$p]')"
  done
  printf '  NOTE: one coding-agent dispatch may contain multiple internal model turns.\n'
  printf '  Weekly-Max percentage: not derivable without the account usage meter; calibrate with one capped task.\n'
fi
