#!/usr/bin/env bash

CODE_BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODE_BENCH_REPO_ROOT="$(cd "$CODE_BENCH_DIR/../.." && pwd)"
CODE_BENCH_RESULTS_ROOT="${CODE_BENCH_RESULTS_ROOT:-$CODE_BENCH_REPO_ROOT/benchmarks/results/code}"

code_die() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

code_require() {
  command -v "$1" >/dev/null 2>&1 || code_die "$1 is required"
}

code_suite_json() {
  local suite="$1"
  jq -ce --arg id "$suite" '.suites[] | select(.id == $id)' "$CODE_BENCH_DIR/suites.json"
}

code_subset_path() {
  local suite_json="$1" rel
  rel=$(printf '%s' "$suite_json" | jq -r '.subset_file' | tr -d '\r')
  printf '%s/%s' "$CODE_BENCH_DIR" "$rel"
}

code_check_manifests() {
  local failures=0 suite_json subset count declared
  code_require jq || return 1

  jq -e '.schema == "code-bench-conditions/1.0" and
         (.conditions | length > 0) and
         ([.conditions[].id] | length == (unique | length)) and
         (all(.conditions[]; (.dispatches | keys) == ["claude","codex","glm","kimi"])) and
         ([.conditions[].dispatches[] | type == "number" and . >= 0 and floor == .] | all)' \
    "$CODE_BENCH_DIR/conditions.json" >/dev/null || {
      printf 'CHECK FAIL: conditions.json\n' >&2; failures=$((failures + 1));
    }
  jq -e '.schema == "code-bench-suites/1.0" and
         (.suites | length > 0) and
         ([.suites[].id] | length == (unique | length))' \
    "$CODE_BENCH_DIR/suites.json" >/dev/null || {
      printf 'CHECK FAIL: suites.json\n' >&2; failures=$((failures + 1));
    }
  jq -e '.schema == "code-bench-external-lock/1.0" and
         (.swebench.commit | test("^[0-9a-f]{40}$")) and
         (.dataset.revision | test("^[0-9a-f]{40}$")) and
         (.compatibility_patches | type == "array" and length > 0) and
         (all(.compatibility_patches[]; test("^patches/[A-Za-z0-9._-]+[.]patch$")))' \
    "$CODE_BENCH_DIR/external-sources.lock.json" >/dev/null || {
      printf 'CHECK FAIL: external-sources.lock.json\n' >&2; failures=$((failures + 1));
    }
  while IFS= read -r patch_rel; do
    [[ -f "$CODE_BENCH_DIR/$patch_rel" ]] || {
      printf 'CHECK FAIL: compatibility patch missing: %s\n' "$patch_rel" >&2
      failures=$((failures + 1))
    }
  done < <(jq -r '.compatibility_patches[]' "$CODE_BENCH_DIR/external-sources.lock.json" | tr -d '\r')

  while IFS= read -r suite_json; do
    subset=$(code_subset_path "$suite_json")
    declared=$(printf '%s' "$suite_json" | jq -r '.task_count' | tr -d '\r')
    if [[ ! -f "$subset" ]]; then
      printf 'CHECK FAIL: subset missing: %s\n' "$subset" >&2
      failures=$((failures + 1)); continue
    fi
    if ! jq -e '.schema == "code-bench-subset/1.0" and
                (.instances | length > 0) and
                ([.instances[].instance_id] | length == (unique | length)) and
                ([.instances[].repo] | length == (unique | length))' "$subset" >/dev/null; then
      printf 'CHECK FAIL: malformed or duplicate subset entries: %s\n' "$subset" >&2
      failures=$((failures + 1)); continue
    fi
    count=$(jq '.instances | length' "$subset" | tr -d '\r')
    if [[ "$count" != "$declared" ]]; then
      printf 'CHECK FAIL: suite declares %s tasks but subset contains %s: %s\n' "$declared" "$count" "$subset" >&2
      failures=$((failures + 1))
    fi
    while IFS= read -r condition; do
      jq -e --arg id "$condition" 'any(.conditions[]; .id == $id)' \
        "$CODE_BENCH_DIR/conditions.json" >/dev/null || {
          printf 'CHECK FAIL: suite references unknown condition %s\n' "$condition" >&2
          failures=$((failures + 1))
        }
    done < <(printf '%s' "$suite_json" | jq -r '.default_conditions[]' | tr -d '\r')
  done < <(jq -c '.suites[]' "$CODE_BENCH_DIR/suites.json")

  (( failures == 0 )) || return 1
  printf 'CHECK: code benchmark manifests PASS\n'
}
