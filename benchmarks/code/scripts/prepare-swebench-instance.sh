#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

INSTANCE="${1:-}"
RUN_ID="${2:-}"
CONDITION="${3:-}"
[[ -n "$INSTANCE" && -n "$RUN_ID" && -n "$CONDITION" ]] || {
  code_die "usage: prepare-swebench-instance.sh INSTANCE RUN_ID CONDITION"; exit 2;
}
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || { code_die "unsafe run id: $RUN_ID"; exit 2; }
[[ "$CONDITION" =~ ^[A-Za-z0-9_-]+$ ]] || { code_die "unsafe condition id: $CONDITION"; exit 2; }
jq -e --arg id "$CONDITION" 'any(.conditions[]; .id == $id)' "$CODE_DIR/conditions.json" >/dev/null \
  || { code_die "unknown condition: $CONDITION"; exit 2; }

METADATA="$CODE_BENCH_RESULTS_ROOT/metadata/swebench-verified-canary.json"
[[ -f "$METADATA" ]] || { code_die "public metadata is absent; run code-bench.sh fetch-metadata"; exit 1; }
row=$(jq -ce --arg id "$INSTANCE" '.instances[] | select(.instance_id == $id)' "$METADATA") \
  || { code_die "instance is outside the frozen canary: $INSTANCE"; exit 1; }
repo=$(printf '%s' "$row" | jq -r '.repo' | tr -d '\r')
base_commit=$(printf '%s' "$row" | jq -r '.base_commit' | tr -d '\r')
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { code_die "unsafe repository id: $repo"; exit 1; }
[[ "$base_commit" =~ ^[0-9a-f]{40}$ ]] || { code_die "unsafe base commit for $INSTANCE"; exit 1; }

CELL="$CODE_BENCH_RESULTS_ROOT/runs/$RUN_ID/$INSTANCE/$CONDITION"
WORKSPACE="$CELL/workspace"
TASK_FILE="$CELL/task.md"
if [[ -e "$CELL" ]]; then
  code_die "cell already exists; choose a new run id: $CELL"; exit 1
fi
mkdir -p "$CELL"

git clone --filter=blob:none --no-checkout "https://github.com/$repo.git" "$WORKSPACE"
git -C "$WORKSPACE" checkout --detach "$base_commit"
git -C "$WORKSPACE" status --porcelain | grep -q . && {
  code_die "prepared workspace is unexpectedly dirty: $WORKSPACE"; exit 1;
}
printf '%s\n' "$row" | jq -r '.problem_statement' > "$TASK_FILE"
jq -n \
  --arg instance_id "$INSTANCE" --arg condition "$CONDITION" \
  --arg repo "$repo" --arg base_commit "$base_commit" \
  --arg workspace "$WORKSPACE" --arg task_file "$TASK_FILE" \
  '{schema:"code-bench-cell-input/1.0", instance_id:$instance_id,
    condition:$condition, repo:$repo, base_commit:$base_commit,
    workspace:$workspace, task_file:$task_file}' > "$CELL/input.json"
printf '%s\n' "$CELL/input.json"
