#!/usr/bin/env bash
# Pick one of k candidate patches by running the repository's own tests.
#
# The equal-cost baseline for a review arm is not "one implementation" but
# "the same number of implementations, chosen without a reviewer": at equal
# token spend, repeated sampling with an execution-grounded selector is the
# comparison a bounce has to beat. This is that selector. No model is called
# here; the only judge is the test command.
#
#   select-best-of-k.sh --workspace WS --output selection.json \
#       [--test-cmd 'python -m pytest -q {files}'] [--timeout 600] CAND1.patch CAND2.patch ...
#
# For each candidate, in order: reset the tree, apply the patch, run the test
# command with {files} replaced by the test files the patch touches (or, when
# it touches none, the tests/ directories beside the source files it changes),
# record exit code and the pytest pass/fail counts, reset again. The winner is
# the candidate that applied, then exited zero, then passed the most, then
# failed the fewest; the earliest candidate wins a tie. When no test file can
# be located for any candidate the selector degrades to "first candidate that
# applies" and says so in selection.json, because a silent fallback would let
# an untested pick masquerade as a test-chosen one.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

WORKSPACE=""
OUTPUT=""
TEST_CMD="${CODE_BENCH_SELECTOR_TEST_CMD:-python -m pytest -q -x -p no:cacheprovider {files}}"
TIMEOUT="${CODE_BENCH_SELECTOR_TIMEOUT:-600}"
CANDIDATES=()
while (( $# > 0 )); do
  case "$1" in
    --workspace) WORKSPACE="${2:?--workspace needs a path}"; shift 2 ;;
    --output) OUTPUT="${2:?--output needs a path}"; shift 2 ;;
    --test-cmd) TEST_CMD="${2:?--test-cmd needs a command}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
    -*) code_die "unknown selector option: $1"; exit 2 ;;
    *) CANDIDATES+=("$1"); shift ;;
  esac
done
[[ -d "$WORKSPACE/.git" ]] || { code_die "--workspace must be a git checkout"; exit 2; }
[[ -n "$OUTPUT" ]] || { code_die "--output is required"; exit 2; }
(( ${#CANDIDATES[@]} >= 1 )) || { code_die "at least one candidate patch is required"; exit 2; }
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { code_die "--timeout must be positive"; exit 2; }

reset_tree() {
  git -C "$WORKSPACE" checkout -q -- . 2>/dev/null
  git -C "$WORKSPACE" clean -fdq 2>/dev/null
}

# Test files named in a patch, else the tests/ directories that sit beside the
# source files it changes. Paths come from the +++ headers only.
test_targets() {
  local patch="$1" path dir
  local -a direct=() derived=()
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      *test*/*|*/test_*|test_*|*_test.py|*tests.py|*/tests/*) direct+=("$path") ;;
      *)
        dir=$(dirname "$path")
        for cand in "$dir/tests" "$dir/test" "$(dirname "$dir")/tests"; do
          [[ -d "$WORKSPACE/$cand" ]] && derived+=("$cand")
        done ;;
    esac
  done < <(grep -E '^\+\+\+ b/' "$patch" | sed 's|^+++ b/||' | tr -d '\r')
  if (( ${#direct[@]} > 0 )); then printf '%s\n' "${direct[@]}" | sort -u
  elif (( ${#derived[@]} > 0 )); then printf '%s\n' "${derived[@]}" | sort -u
  fi
}

results='[]'
index=0
any_tests=false
for candidate in "${CANDIDATES[@]}"; do
  index=$((index + 1))
  reset_tree
  applied=false; rc=null; passed=0; failed=0; cmd=""; seconds=0; targets_json='[]'
  log="$(dirname "$OUTPUT")/selector-candidate-$index.log"
  if [[ -s "$candidate" ]] && git -C "$WORKSPACE" apply --binary --whitespace=nowarn "$candidate" >"$log" 2>&1; then
    applied=true
    targets=$(test_targets "$candidate")
    if [[ -n "$targets" ]]; then
      any_tests=true
      targets_json=$(printf '%s\n' "$targets" | jq -R . | jq -sc .)
      files=$(printf '%s\n' "$targets" | tr '\n' ' ')
      cmd="${TEST_CMD//\{files\}/$files}"
      start=$(date +%s)
      if command -v timeout >/dev/null 2>&1; then
        (cd "$WORKSPACE" && timeout --foreground "${TIMEOUT}s" bash -c "$cmd") >>"$log" 2>&1; rc=$?
      else
        (cd "$WORKSPACE" && bash -c "$cmd") >>"$log" 2>&1; rc=$?
      fi
      seconds=$(( $(date +%s) - start ))
      # pytest's summary line: "3 passed, 1 failed in 0.12s" (either count may be absent).
      passed=$(grep -oE '[0-9]+ passed' "$log" | tail -1 | grep -oE '[0-9]+' || echo 0)
      failed=$(grep -oE '[0-9]+ (failed|error)' "$log" | tail -1 | grep -oE '[0-9]+' || echo 0)
      [[ -n "$passed" ]] || passed=0
      [[ -n "$failed" ]] || failed=0
    fi
  fi
  results=$(jq -c --argjson idx "$index" --arg patch "$candidate" --argjson applied "$applied" \
    --argjson rc "$rc" --argjson passed "$passed" --argjson failed "$failed" \
    --arg cmd "$cmd" --argjson seconds "$seconds" --argjson targets "$targets_json" --arg log "$log" \
    '. + [{index:$idx,patch:$patch,applied:$applied,test_targets:$targets,test_cmd:$cmd,
           exit_code:$rc,passed:$passed,failed:$failed,seconds:$seconds,log:$log}]' <<<"$results")
done
reset_tree

# Ranking: applied, then exit 0, then most passed, then fewest failed, then
# earliest. A candidate with no test run ranks below one that ran and passed
# and above one that ran and failed only through the exit-code term.
chosen=$(jq -r '
  map(. + {key: [(if .applied then 1 else 0 end),
                 (if .exit_code == 0 then 1 else 0 end),
                 .passed, (0 - .failed), (0 - .index)]})
  | max_by(.key) | .index' <<<"$results")
rule="tests"
[[ "$any_tests" == true ]] || rule="apply-only"
chosen_applied=$(jq -r --argjson c "$chosen" '.[] | select(.index == $c) | .applied' <<<"$results")
if [[ "$chosen_applied" != true ]]; then
  jq -n --argjson results "$results" --arg rule "$rule" \
    '{schema:"code-bench-selection/1.0",selector:"best-of-k-repo-tests",rule:$rule,
      chosen:null,candidates:$results}' > "$OUTPUT"
  code_die "no candidate patch applied cleanly"; exit 3
fi
chosen_patch=$(jq -r --argjson c "$chosen" '.[] | select(.index == $c) | .patch' <<<"$results")
git -C "$WORKSPACE" apply --binary --whitespace=nowarn "$chosen_patch" \
  || { code_die "chosen candidate failed to re-apply"; exit 1; }
jq -n --argjson results "$results" --argjson chosen "$chosen" --arg rule "$rule" --arg cmd "$TEST_CMD" \
  '{schema:"code-bench-selection/1.0",selector:"best-of-k-repo-tests",rule:$rule,
    test_cmd_template:$cmd,chosen:$chosen,candidates:$results}' > "$OUTPUT"
printf 'SELECTED: candidate %s of %s by %s\n' "$chosen" "${#CANDIDATES[@]}" "$rule"
