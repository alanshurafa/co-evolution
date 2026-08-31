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
for condition in A B C D; do
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
   && "$(printf '%s' "$dry_c" | jq -r '.declared_claude_dispatches')" == 2 ]]; then
  pass "condition C dry-run exposes five phases and executes nothing"
else
  fail "condition C dry-run exposes five phases and executes nothing"
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

printf '%d/%d assertions passed' "$((TOTAL - FAILED))" "$TOTAL"
if (( FAILED > 0 )); then printf ' (%d failed)\n' "$FAILED"; exit 1; fi
printf '\n'
