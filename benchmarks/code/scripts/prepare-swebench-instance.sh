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

METADATA=$(code_metadata_path)
[[ -f "$METADATA" ]] || { code_die "public metadata is absent; run code-bench.sh fetch-metadata"; exit 1; }
row=$(jq -ce --arg id "$INSTANCE" '.instances[] | select(.instance_id == $id)' "$METADATA") \
  || { code_die "instance is outside suite $(code_suite_id): $INSTANCE"; exit 1; }
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

# A clone carries every commit AFTER the base, including the upstream fix for
# this very issue. An agent that runs `git log origin/main` can read the answer
# instead of deriving it, and observed runs did exactly that -- citing the
# upstream PR and commit hash back in their reports. Replace the history with a
# single synthetic commit holding the base tree, so the working tree is
# identical but nothing about the future is recoverable. `git diff` still yields
# the agent's changes, which is all the driver needs.
rm -rf "$WORKSPACE/.git"
git -C "$WORKSPACE" init -q
git -C "$WORKSPACE" -c core.autocrlf=false add -A
git -C "$WORKSPACE" -c user.email=bench@local -c user.name=bench \
  commit -q -m "base $base_commit" --no-gpg-sign
if git -C "$WORKSPACE" log --oneline --all | wc -l | grep -qv '^ *1$'; then
  code_die "workspace history was not reduced to a single commit"; exit 1
fi
if git -C "$WORKSPACE" remote -v | grep -q .; then
  code_die "workspace still has a remote configured"; exit 1
fi
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
