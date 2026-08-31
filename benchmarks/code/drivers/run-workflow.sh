#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"
# shellcheck source=../../../lib/co-evolution.sh
source "$CODE_BENCH_REPO_ROOT/lib/co-evolution.sh"

INPUT_JSON=""
PREDICTIONS=""
MAX_CLAUDE=""
DRY_RUN=false
RESUME=false
CLAUDE_MODEL="${CODE_BENCH_CLAUDE_MODEL:-fable}"
CODEX_MODEL_LOCAL="${CODE_BENCH_CODEX_MODEL:-gpt-5.6-sol}"
CLAUDE_EFFORT_LOCAL="${CODE_BENCH_CLAUDE_EFFORT:-medium}"
CODEX_EFFORT_LOCAL="${CODE_BENCH_CODEX_EFFORT:-medium}"
PHASE_TIMEOUT="${CODE_BENCH_PHASE_TIMEOUT:-900}"

while (( $# > 0 )); do
  case "$1" in
    --input) INPUT_JSON="${2:?--input needs a value}"; shift 2 ;;
    --predictions) PREDICTIONS="${2:?--predictions needs a value}"; shift 2 ;;
    --max-claude-dispatches) MAX_CLAUDE="${2:?--max-claude-dispatches needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --resume) RESUME=true; shift ;;
    *) code_die "unknown workflow option: $1"; exit 2 ;;
  esac
done

[[ -f "$INPUT_JSON" ]] || { code_die "--input must name a prepared input.json"; exit 2; }
[[ -n "$PREDICTIONS" ]] || { code_die "--predictions is required"; exit 2; }
[[ "$MAX_CLAUDE" =~ ^[0-9]+$ ]] || { code_die "--max-claude-dispatches is required and must be an integer"; exit 2; }
[[ "$PHASE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { code_die "CODE_BENCH_PHASE_TIMEOUT must be positive"; exit 2; }

instance=$(jq -r '.instance_id' "$INPUT_JSON" | tr -d '\r')
condition=$(jq -r '.condition' "$INPUT_JSON" | tr -d '\r')
workspace=$(jq -r '.workspace' "$INPUT_JSON" | tr -d '\r')
task_file=$(jq -r '.task_file' "$INPUT_JSON" | tr -d '\r')
[[ -d "$workspace/.git" && -f "$task_file" ]] || { code_die "prepared workspace or task file is missing"; exit 1; }

results_root=$(cd "$CODE_BENCH_RESULTS_ROOT" && pwd -P)
input_dir=$(cd "$(dirname "$INPUT_JSON")" && pwd -P)
input_abs="$input_dir/$(basename "$INPUT_JSON")"
workspace_abs=$(cd "$workspace" && pwd -P)
task_dir=$(cd "$(dirname "$task_file")" && pwd -P)
task_abs="$task_dir/$(basename "$task_file")"
case "$input_abs" in "$results_root"/runs/*/*/*/input.json) ;; *) code_die "input.json is outside the benchmark run sandbox"; exit 1 ;; esac
[[ "$workspace_abs" == "$input_dir/workspace" ]] || { code_die "workspace does not belong to the prepared cell"; exit 1; }
[[ "$task_abs" == "$input_dir/task.md" ]] || { code_die "task file does not belong to the prepared cell"; exit 1; }
mkdir -p "$(dirname "$PREDICTIONS")"
pred_dir=$(cd "$(dirname "$PREDICTIONS")" && pwd -P)
pred_abs="$pred_dir/$(basename "$PREDICTIONS")"
case "$pred_abs" in "$results_root"/predictions/*) ;; *) code_die "predictions path is outside the benchmark prediction sandbox"; exit 1 ;; esac

condition_json=$(jq -ce --arg id "$condition" '.conditions | map(select(.id == $id)) | if length == 1 then .[0] else empty end' "$CODE_DIR/conditions.json") \
  || { code_die "unknown condition: $condition"; exit 1; }
claude_needed=$(printf '%s' "$condition_json" | jq -r '.dispatches.claude' | tr -d '\r')
if (( claude_needed > MAX_CLAUDE )); then
  printf 'REFUSED: condition %s declares %s Claude dispatches; cap is %s.\n' "$condition" "$claude_needed" "$MAX_CLAUDE" >&2
  exit 75
fi

case "$condition" in
  A) phases="fable-implement" ;;
  B) phases="fable-implement,codex-repair" ;;
  C) phases="fable-implement,codex-critique,glm-critique,kimi-critique,fable-repair" ;;
  D) phases="fable-implement,fable-self-repair" ;;
esac
if [[ "$DRY_RUN" == true ]]; then
  jq -n --arg instance "$instance" --arg condition "$condition" --arg phases "$phases" \
    --argjson claude "$claude_needed" \
    '{instance:$instance,condition:$condition,phases:($phases|split(",")),declared_claude_dispatches:$claude,executed:false}'
  exit 0
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  code_die "ANTHROPIC_API_KEY is set; refusing because this would bill API credits instead of the Max plan"
  exit 1
fi
command -v claude >/dev/null 2>&1 || { code_die "claude CLI is required"; exit 1; }
command -v codex >/dev/null 2>&1 || { code_die "codex CLI is required"; exit 1; }

load_named_key() {
  local name="$1" env_file="$CODE_BENCH_REPO_ROOT/.env.local" line="" value=""
  [[ -z "${!name:-}" && -r "$env_file" ]] || return 0
  line=$(grep -m 1 -E "^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*=" "$env_file" 2>/dev/null || true)
  [[ -n "$line" ]] || return 0
  value=$(printf '%s' "$line" | sed -e 's/^[^=]*=//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  [[ -n "$value" ]] && printf -v "$name" '%s' "$value"
}
load_named_key ZAI_API_KEY
load_named_key KIMI_API_KEY

cell="$input_dir"
logs="$cell/logs"
reviews="$cell/reviews"
mkdir -p "$logs" "$reviews"
jq -n --arg instance "$instance" --arg condition "$condition" \
  --arg claude_model "$CLAUDE_MODEL" --arg claude_effort "$CLAUDE_EFFORT_LOCAL" \
  --arg codex_model "$CODEX_MODEL_LOCAL" --arg codex_effort "$CODEX_EFFORT_LOCAL" \
  --argjson phase_timeout "$PHASE_TIMEOUT" --argjson declared_claude "$claude_needed" \
  '{schema:"code-bench-run/1.0",instance:$instance,condition:$condition,
    models:{claude:$claude_model,codex:$codex_model},
    effort:{claude:$claude_effort,codex:$codex_effort},
    phase_timeout_seconds:$phase_timeout,declared_claude_dispatches:$declared_claude}' \
  > "$cell/run-manifest.json"

write_implement_prompt() {
  local out="$1"
  {
    printf '%s\n\n' "You are solving a repository issue in the current working directory."
    printf '%s\n' "Inspect the code, implement the smallest correct fix, and run the most relevant tests available."
    printf '%s\n' "Do not read outside the repository. Do not commit. Do not modify tests merely to make a failure disappear."
    printf '\n## ISSUE\n\n'
    cat "$task_file"
  } > "$out"
}

run_fable() {
  local phase="$1" prompt="$2"
  local -a cmd=(claude -p --model "$CLAUDE_MODEL" --effort "$CLAUDE_EFFORT_LOCAL"
    --safe-mode --permission-mode auto --tools "Bash,Read,Edit,Write,Glob,Grep"
    --no-session-persistence --output-format json)
  command -v timeout >/dev/null 2>&1 && cmd=(timeout --foreground "${PHASE_TIMEOUT}s" "${cmd[@]}")
  (cd "$workspace" && "${cmd[@]}" < "$prompt") \
    > "$logs/$phase.json" 2> "$logs/$phase.stderr.log"
  jq -e '.type == "result" and .is_error == false and (.result | type == "string")' \
    "$logs/$phase.json" >/dev/null || { code_die "$phase did not produce a successful Claude result"; return 1; }
}

run_codex_repair() {
  local prompt="$1"
  local -a cmd=(codex exec -C "$workspace" -m "$CODEX_MODEL_LOCAL" --sandbox workspace-write
    --ephemeral --ignore-user-config -c approval_policy="never"
    -c model_reasoning_effort="$CODEX_EFFORT_LOCAL" -)
  command -v timeout >/dev/null 2>&1 && cmd=(timeout --foreground "${PHASE_TIMEOUT}s" "${cmd[@]}")
  "${cmd[@]}" \
    < "$prompt" > "$logs/codex-repair.log" 2> "$logs/codex-repair.stderr.log"
}

run_codex_critique() {
  local prompt="$1" out="$2"
  local -a cmd=(codex exec -C "$workspace" -m "$CODEX_MODEL_LOCAL" --sandbox read-only
    --ephemeral --ignore-user-config -c approval_policy="never"
    -c model_reasoning_effort="$CODEX_EFFORT_LOCAL" -o "$out" -)
  command -v timeout >/dev/null 2>&1 && cmd=(timeout --foreground "${PHASE_TIMEOUT}s" "${cmd[@]}")
  "${cmd[@]}" < "$prompt" > "$logs/codex-critique.log" 2> "$logs/codex-critique.stderr.log"
}

write_implement_prompt "$cell/implement-prompt.md"
if [[ "$RESUME" == true ]] \
   && jq -e '.type == "result" and .is_error == false' "$logs/fable-implement.json" >/dev/null 2>&1 \
   && [[ -n "$(git -C "$workspace" diff --name-only)" ]]; then
  printf 'REUSED: fable-implement\n'
else
  run_fable fable-implement "$cell/implement-prompt.md"
fi

case "$condition" in
  B)
    {
      printf '%s\n' "Review the current uncommitted implementation for the issue below. Inspect the diff and repository, correct defects, and run relevant tests. Do not commit."
      printf '\n## ISSUE\n\n'; cat "$task_file"
    } > "$cell/codex-repair-prompt.md"
    run_codex_repair "$cell/codex-repair-prompt.md"
    ;;
  C)
    git -C "$workspace" diff --binary > "$cell/candidate.patch"
    {
      printf '%s\n' "Critique the candidate patch for correctness, regressions, missing cases, and scope. Do not edit files. Return concrete findings only."
      printf '\n## ISSUE\n\n'; cat "$task_file"
      printf '\n## CANDIDATE PATCH\n\n'; head -c 120000 "$cell/candidate.patch"
    } > "$cell/critique-prompt.md"
    if [[ "$RESUME" == true && -s "$reviews/reviewer-1.md" ]] \
       && ! output_is_provider_failure "$reviews/reviewer-1.md"; then
      printf 'REUSED: codex-critique\n'
    else
      run_codex_critique "$cell/critique-prompt.md" "$reviews/reviewer-1.md"
    fi
    [[ -n "${ZAI_API_KEY:-}" ]] || { code_die "condition C requires ZAI_API_KEY"; exit 1; }
    [[ -n "${KIMI_API_KEY:-}" ]] || { code_die "condition C requires KIMI_API_KEY"; exit 1; }
    if [[ "$RESUME" != true ]] || ! validate_agent_artifact "$reviews/reviewer-2.md" "$logs/glm-critique.stderr.log" glm >/dev/null 2>&1; then
      rm -f "$reviews/reviewer-2.md"
      invoke_glm "$cell/critique-prompt.md" "$reviews/reviewer-2.md" "$logs/glm-critique.stderr.log" false
    else
      printf 'REUSED: glm-critique\n'
    fi
    validate_agent_artifact "$reviews/reviewer-2.md" "$logs/glm-critique.stderr.log" glm >/dev/null \
      || { code_die "GLM critique is not a valid artifact"; exit 1; }
    if [[ "$RESUME" != true ]] || ! validate_agent_artifact "$reviews/reviewer-3.md" "$logs/kimi-critique.stderr.log" kimi >/dev/null 2>&1; then
      rm -f "$reviews/reviewer-3.md"
      invoke_kimi "$cell/critique-prompt.md" "$reviews/reviewer-3.md" "$logs/kimi-critique.stderr.log"
    else
      printf 'REUSED: kimi-critique\n'
    fi
    validate_agent_artifact "$reviews/reviewer-3.md" "$logs/kimi-critique.stderr.log" kimi >/dev/null \
      || { code_die "Kimi critique is not a valid artifact"; exit 1; }
    {
      printf '%s\n' "Re-open the current implementation and evaluate the three anonymous reviews below. Decide every finding on its merits, repair accepted issues, and run relevant tests. Do not commit."
      printf '\n## ISSUE\n\n'; cat "$task_file"
      reviewer_number=0
      for review in "$reviews/reviewer-1.md" "$reviews/reviewer-2.md" "$reviews/reviewer-3.md"; do
        reviewer_number=$((reviewer_number + 1))
        printf '\n## REVIEWER %s\n\n' "$reviewer_number"
        head -c 40000 "$review"
        printf '\n'
      done
    } > "$cell/fable-repair-prompt.md"
    run_fable fable-repair "$cell/fable-repair-prompt.md"
    ;;
  D)
    {
      printf '%s\n' "Review your current uncommitted implementation for the issue below. Find and repair correctness or regression risks and run relevant tests. Do not commit."
      printf '\n## ISSUE\n\n'; cat "$task_file"
    } > "$cell/fable-self-repair-prompt.md"
    run_fable fable-self-repair "$cell/fable-self-repair-prompt.md"
    ;;
esac

patch="$cell/final.patch"
git -C "$workspace" diff --binary > "$patch"
[[ -s "$patch" ]] || { code_die "workflow produced an empty patch"; exit 1; }
record="$cell/prediction.json"
jq -n --arg instance_id "$instance" --arg model "co-evolution-condition-$condition" \
  --rawfile model_patch "$patch" \
  '{instance_id:$instance_id,model_name_or_path:$model,model_patch:$model_patch}' > "$record"
jq -c . "$record" >> "$PREDICTIONS"
printf 'WROTE: %s\n' "$record"
