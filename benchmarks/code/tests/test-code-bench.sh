#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$CODE_DIR/code-bench.sh"
TMP=$(mktemp -d -t code-bench-test-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

TOTAL=0
FAILED=0
pass() { TOTAL=$((TOTAL + 1)); printf 'PASS: %s\n' "$1"; }
fail() { TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1"; }
expect_ok() { if "$@" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }

if bash "$RUNNER" check >/dev/null 2>&1; then pass "manifests validate"; else fail "manifests validate"; fi

estimate=$(bash "$RUNNER" estimate --suite swebench-verified-canary --conditions A,B,C --json 2>/dev/null)
if [[ "$(printf '%s' "$estimate" | jq -r '.cells')" == 15 \
   && "$(printf '%s' "$estimate" | jq -r '.declared_dispatches.claude')" == 20 \
   && "$(printf '%s' "$estimate" | jq -r '.declared_dispatches.codex')" == 10 \
   && "$(printf '%s' "$estimate" | jq -r '.declared_dispatches.glm')" == 5 \
   && "$(printf '%s' "$estimate" | jq -r '.declared_dispatches.kimi')" == 5 ]]; then
  pass "A/B/C estimate is exact"
else
  fail "A/B/C estimate is exact"
fi

rc=0
bash "$RUNNER" estimate --conditions A,B,C --max-claude-dispatches 4 >/dev/null 2>&1 || rc=$?
if [[ "$rc" == 75 ]]; then pass "Claude cap fails closed"; else fail "Claude cap fails closed (rc=$rc)"; fi

cat > "$TMP/good.jsonl" <<'JSON'
{"instance_id":"sympy__sympy-20916","model_name_or_path":"condition-A","model_patch":"diff --git a/a.py b/a.py\n"}
JSON
if bash "$RUNNER" validate-predictions "$TMP/good.jsonl" >/dev/null 2>&1; then pass "valid prediction accepted"; else fail "valid prediction accepted"; fi

cat > "$TMP/unknown.jsonl" <<'JSON'
{"instance_id":"unknown__repo-1","model_name_or_path":"condition-A","model_patch":"diff --git a/a b/a\n"}
JSON
if bash "$RUNNER" validate-predictions "$TMP/unknown.jsonl" >/dev/null 2>&1; then fail "unknown instance rejected"; else pass "unknown instance rejected"; fi

cat > "$TMP/duplicate.jsonl" <<'JSON'
{"instance_id":"sympy__sympy-20916","model_name_or_path":"condition-A","model_patch":"diff one"}
{"instance_id":"sympy__sympy-20916","model_name_or_path":"condition-A","model_patch":"diff two"}
JSON
if bash "$RUNNER" validate-predictions "$TMP/duplicate.jsonl" >/dev/null 2>&1; then fail "duplicate prediction rejected"; else pass "duplicate prediction rejected"; fi

cat > "$TMP/empty.jsonl" <<'JSON'
{"instance_id":"sympy__sympy-20916","model_name_or_path":"condition-A","model_patch":""}
JSON
if bash "$RUNNER" validate-predictions "$TMP/empty.jsonl" >/dev/null 2>&1; then fail "empty patch rejected"; else pass "empty patch rejected"; fi

if grep -R -nE '"(patch|test_patch|FAIL_TO_PASS|PASS_TO_PASS)"[[:space:]]*:' \
     "$CODE_DIR/subsets" "$CODE_DIR/conditions.json" "$CODE_DIR/suites.json" >/dev/null 2>&1; then
  fail "checked-in manifests contain no gold fields"
else
  pass "checked-in manifests contain no gold fields"
fi

if find "$CODE_DIR" -type f -name '*.sh' -exec grep -nE \
     '^[[:space:]]*(mapfile|readarray)([[:space:]]|$)' {} + >/dev/null 2>&1; then
  fail "shell scripts are Bash 3 portable"
else
  pass "shell scripts are Bash 3 portable"
fi

TEST_RESULTS="$TMP/results"
for condition in A B C D E F H I; do
  cell="$TEST_RESULTS/runs/test/sympy__sympy-20916/$condition"
  mkdir -p "$cell/workspace/.git" "$TEST_RESULTS/predictions/test"
  printf 'task\n' > "$cell/task.md"
  jq -n --arg c "$condition" --arg w "$cell/workspace" \
    --arg t "$cell/task.md" \
    '{instance_id:"sympy__sympy-20916",condition:$c,workspace:$w,task_file:$t}' \
    > "$cell/input.json"
done

dry_c=$(CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-workflow \
  --input "$TEST_RESULTS/runs/test/sympy__sympy-20916/C/input.json" \
  --predictions "$TEST_RESULTS/predictions/test/C.jsonl" \
  --max-claude-dispatches 2 --dry-run 2>/dev/null)
if [[ "$(printf '%s' "$dry_c" | jq -r '.executed')" == false \
   && "$(printf '%s' "$dry_c" | jq -r '.phases | length')" == 5 \
   && "$(printf '%s' "$dry_c" | jq -r '.critics | join(",")')" == "codex,glm,kimi" \
   && "$(printf '%s' "$dry_c" | jq -r '.declared_claude_dispatches')" == 2 ]]; then
  pass "condition C dry-run exposes five phases and executes nothing"
else
  fail "condition C dry-run exposes five phases and executes nothing"
fi

# A has no critics at all. An empty roster still has to serialize, or every solo
# arm dies before it reaches the dry-run branch.
dry_a=$(CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-workflow \
  --input "$TEST_RESULTS/runs/test/sympy__sympy-20916/A/input.json" \
  --predictions "$TEST_RESULTS/predictions/test/A.jsonl" \
  --max-claude-dispatches 1 --dry-run 2>/dev/null)
if [[ "$(printf '%s' "$dry_a" | jq -r '.phases | join(",")')" == "fable-implement" \
   && "$(printf '%s' "$dry_a" | jq -r '.critics | length')" == 0 ]]; then
  pass "a condition with no critics reports an empty roster"
else
  fail "a condition with no critics reports an empty roster"
fi

# H and I are C with the panel cut to one critic. The roster the driver reports
# is the same string that drives the critique loop and the manifest, so an arm
# that claimed one critic and ran another would fail here.
for arm in H:glm I:kimi; do
  arm_condition="${arm%%:*}"
  arm_critic="${arm##*:}"
  dry_arm=$(CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-workflow \
    --input "$TEST_RESULTS/runs/test/sympy__sympy-20916/$arm_condition/input.json" \
    --predictions "$TEST_RESULTS/predictions/test/$arm_condition.jsonl" \
    --max-claude-dispatches 2 --dry-run 2>/dev/null)
  if [[ "$(printf '%s' "$dry_arm" | jq -r '.phases | join(",")')" == "fable-implement,$arm_critic-critique,fable-repair" \
     && "$(printf '%s' "$dry_arm" | jq -r '.critics | join(",")')" == "$arm_critic" \
     && "$(printf '%s' "$dry_arm" | jq -r '.declared_claude_dispatches')" == 2 ]]; then
    pass "condition $arm_condition bounces through a single $arm_critic critic"
  else
    fail "condition $arm_condition bounces through a single $arm_critic critic"
  fi
done

if grep -q 'critics:\$critics' "$CODE_DIR/drivers/run-workflow.sh"; then
  pass "the run manifest records the critic roster"
else
  fail "the run manifest records the critic roster"
fi

REPAIR="$TMP/repair"
mkdir -p "$REPAIR"
printf 'the issue\n' > "$REPAIR/task.md"
printf 'finding one\n' > "$REPAIR/r1.md"
printf 'finding two\n' > "$REPAIR/r2.md"
printf 'finding three\n' > "$REPAIR/r3.md"
( source "$CODE_DIR/lib/code-bench-lib.sh"
  code_write_repair_prompt "$REPAIR/one.md" "$REPAIR/task.md" "$REPAIR/r1.md"
  code_write_repair_prompt "$REPAIR/three.md" "$REPAIR/task.md" \
    "$REPAIR/r1.md" "$REPAIR/r2.md" "$REPAIR/r3.md"
) >/dev/null 2>&1
one_kept=$(grep -c 'finding one' "$REPAIR/one.md" | tr -d '[:space:]')
two_leaked=$(grep -c 'finding two' "$REPAIR/one.md" | tr -d '[:space:]')
if [[ "$(grep -c '^## REVIEWER ' "$REPAIR/one.md" | tr -d '[:space:]')" == 1 \
   && "$(grep -c '^## REVIEWER ' "$REPAIR/three.md" | tr -d '[:space:]')" == 3 \
   && "$(grep -c '^## REVIEWER 3$' "$REPAIR/three.md" | tr -d '[:space:]')" == 1 \
   && "$one_kept" == 1 && "$two_leaked" == 0 ]]; then
  pass "repair prompt carries one reviewer section per review"
else
  fail "repair prompt carries one reviewer section per review"
fi

if ( source "$CODE_DIR/lib/code-bench-lib.sh"
     code_write_repair_prompt "$REPAIR/none.md" "$REPAIR/task.md"
   ) >/dev/null 2>&1; then
  fail "repair prompt refuses an empty review list"
else
  pass "repair prompt refuses an empty review list"
fi

rc=0
CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-workflow \
  --input "$TEST_RESULTS/runs/test/sympy__sympy-20916/D/input.json" \
  --predictions "$TEST_RESULTS/predictions/test/D.jsonl" \
  --max-claude-dispatches 1 --dry-run >/dev/null 2>&1 || rc=$?
if [[ "$rc" == 75 ]]; then pass "workflow cap refuses condition D"; else fail "workflow cap refuses condition D (rc=$rc)"; fi

mkdir -p "$TMP/outside/workspace/.git"
printf 'task\n' > "$TMP/outside/task.md"
jq -n --arg w "$TMP/outside/workspace" --arg t "$TMP/outside/task.md" \
  '{instance_id:"sympy__sympy-20916",condition:"A",workspace:$w,task_file:$t}' > "$TMP/outside/input.json"
if CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-workflow --input "$TMP/outside/input.json" \
     --predictions "$TEST_RESULTS/predictions/test/A.jsonl" --max-claude-dispatches 1 --dry-run >/dev/null 2>&1; then
  fail "driver rejects input outside sandbox"
else
  pass "driver rejects input outside sandbox"
fi

if bash "$RUNNER" run-canary --run-id dry-one --conditions A,B,C --task-limit 1 \
     --max-claude-dispatches 4 --dry-run >/dev/null 2>&1; then
  pass "one-task A/B/C canary fits aggregate cap four"
else
  fail "one-task A/B/C canary fits aggregate cap four"
fi

rc=0
bash "$RUNNER" run-canary --run-id dry-two --conditions A,B,C --task-limit 2 \
  --max-claude-dispatches 4 --dry-run >/dev/null 2>&1 || rc=$?
if [[ "$rc" == 75 ]]; then pass "two-task A/B/C canary exceeds aggregate cap four"; else fail "two-task A/B/C canary exceeds aggregate cap four (rc=$rc)"; fi

if bash "$RUNNER" run-canary --run-id dry-poc --task pallets__flask-5014 \
     --conditions A,B,C,D,E,F,G,H,I --max-claude-dispatches 10 --dry-run >/dev/null 2>&1; then
  pass "one named task across all nine arms fits ten Fable dispatches"
else
  fail "one named task across all nine arms fits ten Fable dispatches"
fi

if bash "$RUNNER" run-canary --run-id dry-unknown --task nosuch__repo-1 \
     --conditions A --max-claude-dispatches 1 --dry-run >/dev/null 2>&1; then
  fail "a task outside the suite is rejected"
else
  pass "a task outside the suite is rejected"
fi

if grep -q 'run-single-shot.sh' "$CODE_DIR/scripts/run-canary.sh"; then
  pass "the canary runner routes single-shot cells to their own driver"
else
  fail "the canary runner routes single-shot cells to their own driver"
fi

# A fifty-task batch is hours long. One arm that produces no patch is a zero for
# that arm, and an abort there discards every remaining cell in the run.
RESUME_ROOT="$TMP/resume"
mkdir -p "$RESUME_ROOT/runs/resume-test/pallets__flask-5014/A"
jq -n '{instance_id:"pallets__flask-5014",model_name_or_path:"co-evolution-condition-A",
        model_patch:"diff --git a/a.py b/a.py\n"}' \
  > "$RESUME_ROOT/runs/resume-test/pallets__flask-5014/A/prediction.json"
resume_out=$(CODE_BENCH_SUITE=swebench-verified-poc CODE_BENCH_RESULTS_ROOT="$RESUME_ROOT" \
  bash "$RUNNER" run-canary --run-id resume-test --task pallets__flask-5014 \
  --conditions A --max-claude-dispatches 1 2>&1)
if printf '%s' "$resume_out" | grep -q 'SKIP: pallets__flask-5014/A already has a prediction' \
   && printf '%s' "$resume_out" | grep -q '0 cell(s) generated, 1 reused, 0 scored zero (no patch), 0 failed'; then
  pass "a cell with a prediction is reused instead of rerun"
else
  fail "a cell with a prediction is reused instead of rerun"
fi

# Shards must partition the subset: every instance claimed by exactly one shard,
# or a parallel run silently double-spends on some tasks and skips others.
SHARD_ROOT="$TMP/shard"
while IFS= read -r inst; do
  mkdir -p "$SHARD_ROOT/runs/shard-test/$inst/A"
  jq -n --arg id "$inst" '{instance_id:$id,model_name_or_path:"x",model_patch:"diff\n"}' \
    > "$SHARD_ROOT/runs/shard-test/$inst/A/prediction.json"
done < <(jq -r '.instances[].instance_id' "$CODE_DIR/subsets/swebench-verified-canary.json" | tr -d '\r')
shard_total=0
shard_ok=true
for s in 0 1; do
  out=$(CODE_BENCH_RESULTS_ROOT="$SHARD_ROOT" bash "$RUNNER" run-canary \
    --run-id shard-test --shard "$s/2" --task-limit 5 --conditions A \
    --max-claude-dispatches 5 2>&1)
  n=$(printf '%s' "$out" | grep -c '^SKIP: ')
  shard_total=$((shard_total + n))
  # 5 instances over 2 shards is 3 and 2; neither may be empty or take them all.
  if (( n == 0 || n == 5 )); then shard_ok=false; fi
done
if [[ "$shard_ok" == true ]] && (( shard_total == 5 )); then
  pass "shards partition the subset exactly once each"
else
  fail "shards partition the subset exactly once each (total=$shard_total)"
fi

if bash "$RUNNER" run-canary --run-id bad-shard --shard 3/2 --conditions A \
     --max-claude-dispatches 1 --dry-run >/dev/null 2>&1; then
  fail "a shard index outside its count is rejected"
else
  pass "a shard index outside its count is rejected"
fi

# A tier is a named configuration of the primary seats. GLM and Kimi are held
# constant across all of them, so a tier comparison varies only the two seats
# that have a cheaper sibling.
tier_ok=true
for spec in "frontier fable gpt-5.6-sol medium" \
            "max fable gpt-5.6-sol xhigh" \
            "light sonnet gpt-5.6-terra medium"; do
  set -- $spec
  got=$( unset CODE_BENCH_CLAUDE_MODEL CODE_BENCH_CODEX_MODEL CODE_BENCH_CODEX_EFFORT
         source "$CODE_DIR/lib/code-bench-lib.sh"
         code_apply_model_tier "$1" >/dev/null
         printf '%s %s %s' "$CODE_BENCH_CLAUDE_MODEL" "$CODE_BENCH_CODEX_MODEL" \
           "$CODE_BENCH_CODEX_EFFORT" )
  [[ "$got" == "$2 $3 $4" ]] || { tier_ok=false; printf 'tier %s gave: %s\n' "$1" "$got" >&2; }
done
if [[ "$tier_ok" == true ]]; then
  pass "each model tier selects its own models"
else
  fail "each model tier selects its own models"
fi

# The light tier asks for Sonnet's own default effort. If that arrives as the
# driver's "medium" instead, the run is not the one the tier described and the
# manifest records an effort nobody chose.
light_effort=$( unset CODE_BENCH_CLAUDE_EFFORT
                source "$CODE_DIR/lib/code-bench-lib.sh"
                code_apply_model_tier light >/dev/null
                printf '[%s]' "${CODE_BENCH_CLAUDE_EFFORT?unset}" )
if [[ "$light_effort" == "[]" ]]; then
  pass "the light tier leaves Claude effort to the model"
else
  fail "the light tier leaves Claude effort to the model (got $light_effort)"
fi

# A ceiling that clips a model's tail measures the ceiling, not the model. The
# cheaper tier needs the longer one because it iterates more per task.
timeout_ok=true
for spec in "frontier 900" "max 1800" "light 2400"; do
  set -- $spec
  got=$( unset CODE_BENCH_PHASE_TIMEOUT
         source "$CODE_DIR/lib/code-bench-lib.sh"
         code_apply_model_tier "$1" >/dev/null
         printf '%s' "$CODE_BENCH_PHASE_TIMEOUT" )
  [[ "$got" == "$2" ]] || { timeout_ok=false; printf 'tier %s timeout %s\n' "$1" "$got" >&2; }
done
if [[ "$timeout_ok" == true ]]; then
  pass "each tier carries a phase timeout sized to its models"
else
  fail "each tier carries a phase timeout sized to its models"
fi

# An explicit override is a deliberate act and must outrank the tier default.
# Exported before the call, the way a caller actually sets it. A "VAR=x func"
# prefix does not reliably outlive a shell function, so testing it that way
# measured the shell rather than the tier logic.
override=$( unset CODE_BENCH_CODEX_MODEL
            source "$CODE_DIR/lib/code-bench-lib.sh"
            export CODE_BENCH_CLAUDE_MODEL=opus
            code_apply_model_tier light >/dev/null
            printf '%s' "$CODE_BENCH_CLAUDE_MODEL" )
if [[ "$override" == "opus" ]]; then
  pass "an explicit model override survives tier selection"
else
  fail "an explicit model override survives tier selection (got $override)"
fi

if ( source "$CODE_DIR/lib/code-bench-lib.sh"; code_tier_is_valid turbo ); then
  fail "an unknown tier is rejected"
else
  pass "an unknown tier is rejected"
fi

# Resuming a run at a different tier would put two experiments in one prediction
# file with nothing downstream able to separate them.
TIER_ROOT="$TMP/tiermix"
mkdir -p "$TIER_ROOT/runs/tier-test/pallets__flask-5014/A"
jq -n '{schema:"code-bench-run/1.0",model_tier:"light"}' \
  > "$TIER_ROOT/runs/tier-test/pallets__flask-5014/A/run-manifest.json"
if CODE_BENCH_SUITE=swebench-verified-poc CODE_BENCH_RESULTS_ROOT="$TIER_ROOT" \
     bash "$RUNNER" run-canary --run-id tier-test --task pallets__flask-5014 \
     --conditions A --models frontier --max-claude-dispatches 1 >/dev/null 2>&1; then
  fail "a cell from another tier is refused instead of reused"
else
  pass "a cell from another tier is refused instead of reused"
fi

if jq -e 'all(.conditions[]; (.tier == "agentic") or (.tier == "single-shot"))' \
     "$CODE_DIR/conditions.json" >/dev/null 2>&1; then
  pass "every condition declares a tier"
else
  fail "every condition declares a tier"
fi

if jq -e '[.conditions[] | select(.tier == "single-shot")]
          | length > 0 and all(.[]; .dispatches.claude == 0 and .dispatches.codex == 0)' \
     "$CODE_DIR/conditions.json" >/dev/null 2>&1; then
  pass "single-shot conditions spend no agentic dispatch"
else
  fail "single-shot conditions spend no agentic dispatch"
fi

refusal=$(CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-workflow \
  --input "$TEST_RESULTS/runs/test/sympy__sympy-20916/F/input.json" \
  --predictions "$TEST_RESULTS/predictions/test/F.jsonl" \
  --max-claude-dispatches 0 --dry-run 2>&1 >/dev/null)
rc=$?
if (( rc != 0 )) && printf '%s' "$refusal" | grep -q 'run-single-shot.sh'; then
  pass "agentic driver refuses a single-shot condition"
else
  fail "agentic driver refuses a single-shot condition (rc=$rc)"
fi

dry_f=$(CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-single-shot \
  --input "$TEST_RESULTS/runs/test/sympy__sympy-20916/F/input.json" \
  --predictions "$TEST_RESULTS/predictions/test/F.jsonl" \
  --agent glm --dry-run 2>/dev/null)
if [[ "$(printf '%s' "$dry_f" | jq -r '.tier')" == "single-shot" \
   && "$(printf '%s' "$dry_f" | jq -r '.executed')" == false ]]; then
  pass "single-shot dry-run reports its tier and executes nothing"
else
  fail "single-shot dry-run reports its tier and executes nothing"
fi

if CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-single-shot \
     --input "$TEST_RESULTS/runs/test/sympy__sympy-20916/F/input.json" \
     --predictions "$TEST_RESULTS/predictions/test/F.jsonl" \
     --agent kimi --dry-run >/dev/null 2>&1; then
  fail "single-shot driver rejects an undeclared agent"
else
  pass "single-shot driver rejects an undeclared agent"
fi

if CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-single-shot \
     --input "$TEST_RESULTS/runs/test/sympy__sympy-20916/A/input.json" \
     --predictions "$TEST_RESULTS/predictions/test/A.jsonl" \
     --agent glm --dry-run >/dev/null 2>&1; then
  fail "single-shot driver rejects an agentic condition"
else
  pass "single-shot driver rejects an agentic condition"
fi

EXTRACT="$CODE_DIR/scripts/extract-diff.sh"
FIX="$TMP/fixture"
mkdir -p "$FIX"
git -C "$FIX" init -q
printf 'alpha\nbeta\ngamma\n' > "$FIX/sample.txt"
git -C "$FIX" add sample.txt >/dev/null 2>&1
git -C "$FIX" -c user.email=t@e -c user.name=t commit -qm seed >/dev/null 2>&1
printf 'alpha\nBETA\ngamma\n' > "$FIX/sample.txt"
git -C "$FIX" diff > "$TMP/real.patch"
git -C "$FIX" checkout -- sample.txt

{
  printf 'Here is the fix you asked for.\n\n'
  printf '%s\n' '```diff'
  cat "$TMP/real.patch"
  printf '%s\n' '```'
  printf '\nLet me know if you want tests as well.\n'
} > "$TMP/fenced-response.md"
if bash "$EXTRACT" "$TMP/fenced-response.md" "$TMP/fenced.patch" >/dev/null 2>&1 \
   && git -C "$FIX" apply --check "$TMP/fenced.patch" >/dev/null 2>&1; then
  pass "fenced diff extracts and applies"
else
  fail "fenced diff extracts and applies"
fi

{
  cat "$TMP/real.patch"
  printf 'That should resolve the reported behaviour.\n'
} > "$TMP/bare-response.md"
if bash "$EXTRACT" "$TMP/bare-response.md" "$TMP/bare.patch" >/dev/null 2>&1 \
   && git -C "$FIX" apply --check "$TMP/bare.patch" >/dev/null 2>&1 \
   && ! grep -q 'reported behaviour' "$TMP/bare.patch"; then
  pass "unfenced diff extracts without trailing prose"
else
  fail "unfenced diff extracts without trailing prose"
fi

printf 'I could not reproduce the issue.\n' > "$TMP/no-diff.md"
if bash "$EXTRACT" "$TMP/no-diff.md" "$TMP/none.patch" >/dev/null 2>&1; then
  fail "response without a diff is rejected"
else
  pass "response without a diff is rejected"
fi

# The single-shot gate applies with --recount because chat models routinely get
# the @@ line counts wrong while proposing a correct edit. Strict apply rejects
# such a patch; --recount accepts it without altering a single edited line.
miscounted="$TMP/miscounted.patch"
sed 's/^@@ -1,3 +1,3 @@/@@ -1,9 +1,9 @@/' "$TMP/real.patch" > "$miscounted"
strict_rc=0
git -C "$FIX" apply --check "$miscounted" >/dev/null 2>&1 || strict_rc=$?
recount_rc=0
git -C "$FIX" apply --check --recount "$miscounted" >/dev/null 2>&1 || recount_rc=$?
if (( strict_rc != 0 )) && (( recount_rc == 0 )); then
  pass "--recount rescues a miscounted hunk header"
else
  fail "--recount rescues a miscounted hunk header (strict=$strict_rc recount=$recount_rc)"
fi

if grep -q 'apply --check --recount' "$CODE_DIR/drivers/run-single-shot.sh"; then
  pass "single-shot driver gates with --recount"
else
  fail "single-shot driver gates with --recount"
fi

STATUS_TEST="$TMP/status/battery.txt"
if ( set -e
     source "$CODE_DIR/lib/code-bench-lib.sh"
     code_status_init "$STATUS_TEST" alpha
     code_status_append "$STATUS_TEST" alpha "cells=1/5"
   ) >/dev/null 2>&1 && grep -q '^writer=alpha .*cells=1/5' "$STATUS_TEST"; then
  pass "status lines carry their writer"
else
  fail "status lines carry their writer"
fi

if ( source "$CODE_DIR/lib/code-bench-lib.sh"
     code_status_append "$STATUS_TEST" beta "cells=2/5"
   ) >/dev/null 2>&1; then
  fail "a second writer cannot append to another writer's status file"
else
  pass "a second writer cannot append to another writer's status file"
fi

sandbox_default=$( source "$CODE_DIR/lib/code-bench-lib.sh"; code_codex_sandbox )
if [[ "$sandbox_default" == "workspace-write" ]]; then
  pass "codex sandbox defaults to workspace-write"
else
  fail "codex sandbox defaults to workspace-write"
fi

if ( source "$CODE_DIR/lib/code-bench-lib.sh"
     CODE_BENCH_CODEX_SANDBOX=wide-open code_codex_sandbox
   ) >/dev/null 2>&1; then
  fail "codex sandbox rejects an unknown mode"
else
  pass "codex sandbox rejects an unknown mode"
fi


# --- T0.2: seeds -------------------------------------------------------------
# A seed is a repeat index. Seed 1 keeps the bare condition name so every
# existing run stays addressable; a repeat gets a .rN suffix on the cell, the
# prediction file and model_name_or_path alike.
seed_names=$( source "$CODE_DIR/lib/code-bench-lib.sh"
              printf '%s %s %s' "$(code_cell_name A 1)" "$(code_cell_name A 2)" "$(code_cell_name B 10)" )
if [[ "$seed_names" == "A A.r2 B.r10" ]]; then
  pass "cell names carry the seed only past the first run"
else
  fail "cell names carry the seed only past the first run (got $seed_names)"
fi

estimate3=$(bash "$RUNNER" estimate --suite swebench-verified-canary --conditions A,B --repeat 3 --json 2>/dev/null)
if [[ "$(printf '%s' "$estimate3" | jq -r '.cells')" == 30 \
   && "$(printf '%s' "$estimate3" | jq -r '.seeds')" == 3 \
   && "$(printf '%s' "$estimate3" | jq -r '.declared_dispatches.claude')" == 30 \
   && "$(printf '%s' "$estimate3" | jq -r '.declared_dispatches.codex')" == 15 ]]; then
  pass "--repeat multiplies cells and dispatches by the seed count"
else
  fail "--repeat multiplies cells and dispatches by the seed count"
fi

rc=0
bash "$RUNNER" run-canary --run-id dry-seeds --conditions A --task-limit 5 --repeat 3 \
  --max-claude-dispatches 14 --dry-run >/dev/null 2>&1 || rc=$?
if [[ "$rc" == 75 ]]; then pass "the aggregate cap counts every seed"; else fail "the aggregate cap counts every seed (rc=$rc)"; fi

if bash "$RUNNER" run-canary --run-id dry-seeds --conditions A --task-limit 5 --repeat 3 \
     --max-claude-dispatches 15 --dry-run >/dev/null 2>&1; then
  pass "three seeds of a five-task solo arm fit fifteen dispatches"
else
  fail "three seeds of a five-task solo arm fit fifteen dispatches"
fi

if bash "$RUNNER" run-canary --run-id dry-seeds --conditions A --repeat 0 \
     --max-claude-dispatches 1 --dry-run >/dev/null 2>&1; then
  fail "--repeat rejects zero"
else
  pass "--repeat rejects zero"
fi

# Resume across seeds: seed 1 and seed 2 cells both hold predictions, so a
# --repeat 2 rerun reuses both and generates nothing.
SEED_ROOT="$TMP/seeds"
for cellname in A A.r2; do
  mkdir -p "$SEED_ROOT/runs/seed-test/pallets__flask-5014/$cellname"
  jq -n --arg m "co-evolution-condition-$cellname" \
    '{instance_id:"pallets__flask-5014",model_name_or_path:$m,model_patch:"diff --git a/a.py b/a.py\n"}' \
    > "$SEED_ROOT/runs/seed-test/pallets__flask-5014/$cellname/prediction.json"
done
seed_out=$(CODE_BENCH_SUITE=swebench-verified-poc CODE_BENCH_RESULTS_ROOT="$SEED_ROOT" \
  bash "$RUNNER" run-canary --run-id seed-test --task pallets__flask-5014 \
  --conditions A --repeat 2 --max-claude-dispatches 2 2>&1)
if printf '%s' "$seed_out" | grep -q 'SKIP: pallets__flask-5014/A.r2 already has a prediction' \
   && printf '%s' "$seed_out" | grep -q '0 cell(s) generated, 2 reused, 0 scored zero (no patch), 0 failed' \
   && [[ -f "$SEED_ROOT/predictions/seed-test/A.r2.jsonl" ]] \
   && jq -e '.model_name_or_path == "co-evolution-condition-A.r2"' "$SEED_ROOT/predictions/seed-test/A.r2.jsonl" >/dev/null; then
  pass "each seed resumes into its own prediction file"
else
  fail "each seed resumes into its own prediction file"
fi

seed_cell="$TEST_RESULTS/runs/test/sympy__sympy-20916/A.r2"
mkdir -p "$seed_cell/workspace/.git"
printf 'task\n' > "$seed_cell/task.md"
jq -n --arg w "$seed_cell/workspace" --arg t "$seed_cell/task.md" \
  '{instance_id:"sympy__sympy-20916",condition:"A",seed:2,workspace:$w,task_file:$t}' \
  > "$seed_cell/input.json"
dry_seed=$(CODE_BENCH_RESULTS_ROOT="$TEST_RESULTS" bash "$RUNNER" run-workflow \
  --input "$seed_cell/input.json" --predictions "$TEST_RESULTS/predictions/test/A.r2.jsonl" \
  --max-claude-dispatches 1 --dry-run 2>/dev/null)
if [[ "$(printf '%s' "$dry_seed" | jq -r '.seed')" == 2 \
   && "$(printf '%s' "$dry_seed" | jq -r '.model_name_or_path')" == "co-evolution-condition-A.r2" ]]; then
  pass "the driver names a repeat's prediction after its seed"
else
  fail "the driver names a repeat's prediction after its seed"
fi

if bash "$CODE_DIR/scripts/prepare-swebench-instance.sh" sympy__sympy-20916 x A 0 >/dev/null 2>&1; then
  fail "prepare rejects seed zero"
else
  pass "prepare rejects seed zero"
fi


# --- T0.3: difficulty labels --------------------------------------------------
if jq -e '.annotations.difficulty.source and (.instances | all(.difficulty | type == "string"))' \
     "$CODE_DIR/subsets/swebench-verified-random50.json" >/dev/null 2>&1; then
  pass "the random50 subset carries a Verified difficulty label per task"
else
  fail "the random50 subset carries a Verified difficulty label per task"
fi

# A label outside the four buckets must fail the manifest check rather than
# silently vanish from every by-difficulty bucket on the page.
BAD_SUBSET="$TMP/bad-subset"
mkdir -p "$BAD_SUBSET/subsets" "$BAD_SUBSET/lib" "$BAD_SUBSET/patches"
cp "$CODE_DIR/conditions.json" "$CODE_DIR/suites.json" "$CODE_DIR/external-sources.lock.json" "$BAD_SUBSET/"
cp "$CODE_DIR/patches/"* "$BAD_SUBSET/patches/"
cp "$CODE_DIR/subsets/"* "$BAD_SUBSET/subsets/"
cp "$CODE_DIR/lib/code-bench-lib.sh" "$BAD_SUBSET/lib/"
jq '.instances[0].difficulty = "trivial"' "$CODE_DIR/subsets/swebench-verified-canary.json" \
  > "$BAD_SUBSET/subsets/swebench-verified-canary.json"
if ( source "$BAD_SUBSET/lib/code-bench-lib.sh"; code_check_manifests ) >/dev/null 2>&1; then
  fail "a difficulty label outside the four buckets fails the check"
else
  pass "a difficulty label outside the four buckets fails the check"
fi

# The annotator reads a public field only and refuses to leave a task unlabeled.
ANN="$TMP/annotate"
mkdir -p "$ANN"
jq '{schema, suite_id, instances: [.instances[0], .instances[1]]}' \
  "$CODE_DIR/subsets/swebench-verified-canary.json" > "$ANN/subset.json"
jq -n '{"sympy__sympy-20916": "<15 min fix", "django__django-16819": "1-4 hours"}' > "$ANN/labels.json"
if python "$CODE_DIR/scripts/annotate-difficulty.py" --lock "$CODE_DIR/external-sources.lock.json" \
     --subset "$ANN/subset.json" --labels-json "$ANN/labels.json" >/dev/null 2>&1 \
   && jq -e '.instances[1].difficulty == "1-4 hours" and .annotations.difficulty.counts["1-4 hours"] == 1' \
        "$ANN/subset.json" >/dev/null; then
  pass "the annotator writes labels and bucket counts into the subset"
else
  fail "the annotator writes labels and bucket counts into the subset"
fi
jq -n '{"sympy__sympy-20916": "<15 min fix"}' > "$ANN/partial.json"
if python "$CODE_DIR/scripts/annotate-difficulty.py" --lock "$CODE_DIR/external-sources.lock.json" \
     --subset "$ANN/subset.json" --labels-json "$ANN/partial.json" >/dev/null 2>&1; then
  fail "the annotator refuses to leave a task unlabeled"
else
  pass "the annotator refuses to leave a task unlabeled"
fi


# --- T0.5: an arm that produces no patch scores zero and the batch goes on ---
# Stub CLIs on PATH: claude returns a successful envelope and, unless told
# otherwise, touches nothing; codex drains its prompt and prints the banner.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/claude" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
if [[ -n "${STUB_CLAUDE_EDIT:-}" ]]; then printf 'edited by stub\n' >> "$STUB_CLAUDE_EDIT"; fi
printf '{"type":"result","is_error":false,"result":"done","duration_ms":1000,"total_cost_usd":0.5,"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}\n'
STUB
cat > "$STUB_BIN/codex" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
printf 'OpenAI Codex v0.0.0-stub\n--------\n' >&2
if [[ -n "${STUB_CODEX_EDIT:-}" ]]; then printf 'edited by codex stub\n' >> "$STUB_CODEX_EDIT"; fi
printf '{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":100}}\n'
printf 'tokens used\n1,100\n' >&2
STUB
chmod +x "$STUB_BIN/claude" "$STUB_BIN/codex"

make_live_cell() { # make_live_cell RUN COND [SEED] -> input.json path
  local run="$1" cond="$2" seed="${3:-1}" name
  name=$( source "$CODE_DIR/lib/code-bench-lib.sh"; code_cell_name "$cond" "$seed" )
  local cell="$LIVE_ROOT/runs/$run/pallets__flask-5014/$name"
  mkdir -p "$cell/workspace" "$LIVE_ROOT/predictions/$run"
  git -C "$cell/workspace" init -q
  printf 'original\n' > "$cell/workspace/app.py"
  git -C "$cell/workspace" add app.py >/dev/null 2>&1
  git -C "$cell/workspace" -c user.email=t@e -c user.name=t commit -qm seed >/dev/null 2>&1
  printf 'task\n' > "$cell/task.md"
  jq -n --arg c "$cond" --argjson s "$seed" --arg w "$cell/workspace" --arg t "$cell/task.md" \
    '{instance_id:"pallets__flask-5014",condition:$c,seed:$s,workspace:$w,task_file:$t}' \
    > "$cell/input.json"
  printf '%s' "$cell/input.json"
}

LIVE_ROOT="$TMP/live"
input_a=$(make_live_cell nopatch A)
rc=0
( unset ANTHROPIC_API_KEY
  PATH="$STUB_BIN:$PATH" CODE_BENCH_RESULTS_ROOT="$LIVE_ROOT" \
  bash "$RUNNER" run-workflow --input "$input_a" \
    --predictions "$LIVE_ROOT/predictions/nopatch/A.jsonl" --max-claude-dispatches 1 ) >/dev/null 2>&1 || rc=$?
cell_a=$(dirname "$input_a")
if [[ "$rc" == 3 ]] && jq -e '.outcome == "empty-patch" and .condition == "A" and .seed == 1' \
     "$cell_a/outcome.json" >/dev/null 2>&1 && [[ ! -f "$cell_a/prediction.json" ]]; then
  pass "an arm that changes nothing records an empty-patch outcome and exits 3"
else
  fail "an arm that changes nothing records an empty-patch outcome and exits 3 (rc=$rc)"
fi

# The batch runner treats that cell as a scored zero: it is not retried on
# resume, and the summary line counts it apart from failures.
nopatch_out=$(CODE_BENCH_SUITE=swebench-verified-poc CODE_BENCH_RESULTS_ROOT="$LIVE_ROOT" \
  bash "$RUNNER" run-canary --run-id nopatch --task pallets__flask-5014 \
  --conditions A --max-claude-dispatches 1 2>&1)
if printf '%s' "$nopatch_out" | grep -q 'SKIP: pallets__flask-5014/A already ran and produced no patch' \
   && printf '%s' "$nopatch_out" | grep -q '0 cell(s) generated, 1 reused, 0 scored zero (no patch), 0 failed'; then
  pass "a no-patch cell is kept as a zero on resume rather than rerun"
else
  fail "a no-patch cell is kept as a zero on resume rather than rerun"
fi

# The happy path still writes a prediction named for its seed.
input_a2=$(make_live_cell happy A 2)
cell_a2=$(dirname "$input_a2")
rc=0
( unset ANTHROPIC_API_KEY
  PATH="$STUB_BIN:$PATH" STUB_CLAUDE_EDIT="$cell_a2/workspace/app.py" CODE_BENCH_RESULTS_ROOT="$LIVE_ROOT" \
  bash "$RUNNER" run-workflow --input "$input_a2" \
    --predictions "$LIVE_ROOT/predictions/happy/A.r2.jsonl" --max-claude-dispatches 1 ) >/dev/null 2>&1 || rc=$?
if [[ "$rc" == 0 ]] && jq -e '.model_name_or_path == "co-evolution-condition-A.r2"' "$cell_a2/prediction.json" >/dev/null 2>&1 \
   && jq -e '.seed == 2 and .models.glm == "glm-5.3-flash"' "$cell_a2/run-manifest.json" >/dev/null 2>&1; then
  pass "a stubbed live cell writes its prediction under the seeded model name"
else
  fail "a stubbed live cell writes its prediction under the seeded model name (rc=$rc)"
fi

printf '%d/%d assertions passed' "$((TOTAL - FAILED))" "$TOTAL"
if (( FAILED > 0 )); then printf ' (%d failed)\n' "$FAILED"; exit 1; fi
printf '\n'
