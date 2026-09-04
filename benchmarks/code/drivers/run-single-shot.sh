#!/usr/bin/env bash
# Single-shot patch generation for models that have no coding-agent loop.
#
# GLM and Kimi are reachable here only as chat completions: no tools, no file
# reads, no test execution. Their cells therefore cannot be a like-for-like
# comparison against the agentic conditions, and the tier is labelled
# "single-shot" in the manifest, the prediction record, and every report so a
# reader never sees these rows unqualified beside an agentic row.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"
# shellcheck source=../../../lib/co-evolution.sh
source "$CODE_BENCH_REPO_ROOT/lib/co-evolution.sh"

INPUT_JSON=""
PREDICTIONS=""
AGENT=""
DRY_RUN=false
# Both providers bill reasoning against max_tokens. Measured on this prompt
# shape, GLM spends ~19k reasoning tokens before writing a patch, so an 8k
# budget returns finish_reason=length with empty content every time.
MAX_TOKENS="${CODE_BENCH_SINGLE_SHOT_MAX_TOKENS:-32000}"
ATTEMPTS="${CODE_BENCH_SINGLE_SHOT_ATTEMPTS:-3}"
RETRY_DELAY="${CODE_BENCH_SINGLE_SHOT_RETRY_DELAY:-15}"
CONTEXT_FILES="${CODE_BENCH_SINGLE_SHOT_CONTEXT_FILES:-6}"
CONTEXT_BYTES="${CODE_BENCH_SINGLE_SHOT_CONTEXT_BYTES:-24000}"
GLM_CRITIC_REASONING="${CODE_BENCH_GLM_REASONING_EFFORT:-low}"
KIMI_CRITIC_THINKING="${CODE_BENCH_KIMI_THINKING:-disabled}"

while (( $# > 0 )); do
  case "$1" in
    --input) INPUT_JSON="${2:?--input needs a value}"; shift 2 ;;
    --predictions) PREDICTIONS="${2:?--predictions needs a value}"; shift 2 ;;
    --agent) AGENT="${2:?--agent needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) code_die "unknown single-shot option: $1"; exit 2 ;;
  esac
done

[[ -f "$INPUT_JSON" ]] || { code_die "--input must name a prepared input.json"; exit 2; }
[[ -n "$PREDICTIONS" ]] || { code_die "--predictions is required"; exit 2; }
case "$AGENT" in glm|kimi) ;; *) code_die "--agent must be glm or kimi"; exit 2 ;; esac
for numeric in MAX_TOKENS ATTEMPTS CONTEXT_FILES CONTEXT_BYTES; do
  [[ "${!numeric}" =~ ^[1-9][0-9]*$ ]] || { code_die "$numeric must be a positive integer"; exit 2; }
done
[[ "$RETRY_DELAY" =~ ^[0-9]+$ ]] || { code_die "RETRY_DELAY must be a non-negative integer"; exit 2; }

instance=$(jq -r '.instance_id' "$INPUT_JSON" | tr -d '\r')
condition=$(jq -r '.condition' "$INPUT_JSON" | tr -d '\r')
workspace=$(jq -r '.workspace' "$INPUT_JSON" | tr -d '\r')
task_file=$(jq -r '.task_file' "$INPUT_JSON" | tr -d '\r')
[[ -d "$workspace/.git" && -f "$task_file" ]] || { code_die "prepared workspace or task file is missing"; exit 1; }

condition_json=$(jq -ce --arg id "$condition" '.conditions | map(select(.id == $id)) | if length == 1 then .[0] else empty end' "$CODE_DIR/conditions.json") \
  || { code_die "unknown condition: $condition"; exit 1; }
tier=$(printf '%s' "$condition_json" | jq -r '.tier' | tr -d '\r')
label=$(printf '%s' "$condition_json" | jq -r '.label' | tr -d '\r')
[[ "$tier" == "single-shot" ]] || { code_die "condition $condition is tier $tier; this driver only runs single-shot cells"; exit 1; }
declared=$(printf '%s' "$condition_json" | jq -r --arg a "$AGENT" '.dispatches[$a]' | tr -d '\r')
(( declared == 1 )) || { code_die "condition $condition does not declare a $AGENT dispatch"; exit 1; }

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

if [[ "$DRY_RUN" == true ]]; then
  jq -n --arg instance "$instance" --arg condition "$condition" --arg agent "$AGENT" \
    --arg tier "$tier" --arg label "$label" \
    '{instance:$instance,condition:$condition,agent:$agent,tier:$tier,label:$label,
      phases:["select-context","single-shot-diff","git-apply-gate"],executed:false}'
  exit 0
fi

code_load_env_key ZAI_API_KEY
code_load_env_key KIMI_API_KEY
case "$AGENT" in
  glm) [[ -n "${ZAI_API_KEY:-}" ]] || { code_die "condition $condition requires ZAI_API_KEY"; exit 1; } ;;
  kimi) [[ -n "${KIMI_API_KEY:-}" ]] || { code_die "condition $condition requires KIMI_API_KEY"; exit 1; } ;;
esac

cell="$input_dir"
logs="$cell/logs"
mkdir -p "$logs"
# Ask the adapter for the token-usage sidecar next to each response; the
# results page prices the seat from it, and a cell without one is unpriced.
export CO_EVOLVE_TOKEN_CAPTURE=1

git -C "$workspace" diff --quiet || { code_die "workspace is already dirty; prepare a fresh cell"; exit 1; }

context_list="$cell/context-files.txt"
python "$CODE_DIR/scripts/select-context.py" \
  --workspace "$workspace" --task "$task_file" --max-files "$CONTEXT_FILES" \
  2> "$logs/select-context.stderr.log" | tr -d '\r' > "$context_list" \
  || { code_die "context selection failed; see $logs/select-context.stderr.log"; exit 1; }
[[ -s "$context_list" ]] || { code_die "context selection returned no files"; exit 1; }

model_name=""
case "$AGENT" in
  glm) model_name="${GLM_MODEL:-glm-5.3-flash}" ;;
  kimi) model_name="${KIMI_MODEL:-kimi-k3}" ;;
esac
jq -n --arg instance "$instance" --arg condition "$condition" --arg agent "$AGENT" \
  --arg tier "$tier" --arg label "$label" --arg model "$model_name" \
  --arg model_tier "$(code_model_tier)" \
  --argjson max_tokens "$MAX_TOKENS" --argjson attempts "$ATTEMPTS" \
  --argjson context_files "$CONTEXT_FILES" --argjson context_bytes "$CONTEXT_BYTES" \
  --rawfile context "$context_list" \
  '{schema:"code-bench-single-shot/1.0",instance:$instance,condition:$condition,
    tier:$tier,label:$label,agent:$agent,model:$model,model_tier:$model_tier,
    output_max_tokens:$max_tokens,apply_attempts:$attempts,
    retrieval:{max_files:$context_files,max_bytes_per_file:$context_bytes,
               selected:($context|split("\n")|map(select(length>0)))}}' \
  > "$cell/run-manifest.json"

write_prompt() {
  local out="$1" feedback="$2"
  {
    printf '%s\n' "You are fixing a bug in a Python repository. You cannot run commands, open files, or execute tests: everything you may use is below."
    printf '%s\n' "Return exactly one unified diff and nothing else, inside a single fenced block that opens with three backticks followed by diff."
    printf '%s\n' "Rules for the diff: use git-style headers (diff --git a/PATH b/PATH), keep paths relative to the repository root, include @@ hunk headers with at least three lines of unchanged context, and change only what the issue requires."
    printf '%s\n' "Do not add or modify tests. Do not reformat unrelated code. Do not invent files that are not shown."
    printf '\n## ISSUE\n\n'
    cat "$task_file"
    printf '\n## REPOSITORY FILES\n\n'
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      printf '### %s\n\n' "$rel"
      printf '%s\n' '```python'
      head -c "$CONTEXT_BYTES" "$workspace/$rel"
      printf '\n%s\n\n' '```'
    done < <(tr -d '\r' < "$context_list")
    if [[ -n "$feedback" && -s "$feedback" ]]; then
      printf '\n## YOUR PREVIOUS ATTEMPT DID NOT APPLY\n\n'
      printf '%s\n' "git apply rejected the diff below. Produce a corrected diff whose context lines match the files above exactly."
      printf '\n### git apply error\n\n'
      head -c 4000 "$feedback"
      printf '\n'
    fi
  } > "$out"
}

invoke_single_shot() {
  local prompt="$1" out="$2" err="$3"
  case "$AGENT" in
    glm) GLM_MAX_TOKENS="$MAX_TOKENS" GLM_REASONING_EFFORT="$GLM_CRITIC_REASONING" \
           invoke_glm "$prompt" "$out" "$err" false ;;
    kimi) KIMI_MAX_TOKENS="$MAX_TOKENS" KIMI_THINKING="$KIMI_CRITIC_THINKING" \
           invoke_kimi "$prompt" "$out" "$err" ;;
  esac
}

feedback=""
attempt=1
applied=false
while (( attempt <= ATTEMPTS )); do
  response="$logs/$AGENT-response-$attempt.md"
  stderr_log="$logs/$AGENT-response-$attempt.stderr.log"
  candidate="$cell/candidate-$attempt.patch"
  apply_log="$logs/git-apply-$attempt.log"
  write_prompt "$cell/single-shot-prompt-$attempt.md" "$feedback"
  invoke_single_shot "$cell/single-shot-prompt-$attempt.md" "$response" "$stderr_log"

  if ! validate_agent_artifact "$response" "$stderr_log" "$AGENT" >/dev/null 2>&1; then
    printf 'RETRY: %s attempt %s returned no usable response\n' "$AGENT" "$attempt" >&2
    printf 'provider returned no usable response\n' > "$apply_log"
  elif ! bash "$CODE_DIR/scripts/extract-diff.sh" "$response" "$candidate" 2>/dev/null; then
    printf 'RETRY: %s attempt %s contained no unified diff\n' "$AGENT" "$attempt" >&2
    printf 'no unified diff found in the response\n' > "$apply_log"
  elif git -C "$workspace" apply --check --recount --whitespace=nowarn "$candidate" > "$apply_log" 2>&1; then
    git -C "$workspace" apply --recount --whitespace=nowarn "$candidate" >> "$apply_log" 2>&1 \
      || { code_die "git apply --check passed but apply failed; see $apply_log"; exit 1; }
    applied=true
    break
  else
    printf 'RETRY: %s attempt %s produced a diff git apply rejected\n' "$AGENT" "$attempt" >&2
  fi

  feedback="$apply_log"
  attempt=$((attempt + 1))
  if (( attempt <= ATTEMPTS )); then sleep "$RETRY_DELAY"; fi
done

if [[ "$applied" != true ]]; then
  jq -n --arg instance "$instance" --arg condition "$condition" --arg agent "$AGENT" \
    --arg tier "$tier" --argjson attempts "$ATTEMPTS" \
    '{schema:"code-bench-single-shot-outcome/1.0",instance:$instance,condition:$condition,
      agent:$agent,tier:$tier,outcome:"no-applicable-patch",attempts:$attempts}' \
    > "$cell/outcome.json"
  code_die "$AGENT produced no applicable patch for $instance after $ATTEMPTS attempts"
  exit 1
fi

patch="$cell/final.patch"
git -C "$workspace" diff --binary > "$patch"
[[ -s "$patch" ]] || { code_die "single-shot run produced an empty patch"; exit 1; }
record="$cell/prediction.json"
jq -n --arg instance_id "$instance" --arg model "co-evolution-condition-$condition" \
  --rawfile model_patch "$patch" \
  '{instance_id:$instance_id,model_name_or_path:$model,model_patch:$model_patch}' > "$record"
jq -c . "$record" >> "$PREDICTIONS"
jq -n --arg instance "$instance" --arg condition "$condition" --arg agent "$AGENT" \
  --arg tier "$tier" --argjson attempts "$attempt" \
  '{schema:"code-bench-single-shot-outcome/1.0",instance:$instance,condition:$condition,
    agent:$agent,tier:$tier,outcome:"patch-applied",attempts:$attempts}' \
  > "$cell/outcome.json"
printf 'WROTE: %s\n' "$record"
