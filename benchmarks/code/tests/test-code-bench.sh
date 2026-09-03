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
   && printf '%s' "$resume_out" | grep -q '0 cell(s) generated, 1 reused, 0 failed'; then
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

# An explicit override is a deliberate act and must outrank the tier default.
override=$( unset CODE_BENCH_CODEX_MODEL
            source "$CODE_DIR/lib/code-bench-lib.sh"
            CODE_BENCH_CLAUDE_MODEL=opus code_apply_model_tier light >/dev/null
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

printf '%d/%d assertions passed' "$((TOTAL - FAILED))" "$TOTAL"
if (( FAILED > 0 )); then printf ' (%d failed)\n' "$FAILED"; exit 1; fi
printf '\n'
