#!/usr/bin/env bash
# tests/run-all.sh — aggregate test runner (v1.3 Phase 2; closes audit F-3).
#
# Runs every hermetic gate in the repo and reports one PASS/FAIL line per
# suite plus a final summary. Exits nonzero if any suite fails.
#
#   bash tests/run-all.sh            # everything, serially (CI default)
#   bash tests/run-all.sh --quick    # skip the slow suites (pr-emitter,
#                                    # code-proposer, scorer-verification)
#   bash tests/run-all.sh --jobs 4   # run suites in parallel (needs bash>=4.3)
#   bash tests/run-all.sh --resume   # checkpoint ledger: suites that already
#                                    # PASSed (this tree) are skipped, so an
#                                    # interrupted run continues instead of
#                                    # restarting; the gate is cumulative —
#                                    # every suite must have passed at least
#                                    # once, not all in a single run
#   --ledger DIR                     # ledger location (default tests/.run-ledger)
#
# Per-suite output always lands in the ledger dir as <suite>.log when a ledger
# is active, so a failure's full output survives the run.
#
# Hermetic against host git config: tests that create scratch repos must not
# depend on (or be broken by) the host's user identity, autocrlf, hooks, or
# default-branch settings, so a throwaway global config is injected for the
# whole run.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

QUICK=false
JOBS=1
RESUME=false
LEDGER_DIR="$SCRIPT_DIR/.run-ledger"
while (( $# > 0 )); do
  case "$1" in
    --quick) QUICK=true ;;
    --jobs) shift; JOBS="${1:?--jobs requires a count}" ;;
    --resume) RESUME=true ;;
    --ledger) shift; LEDGER_DIR="${1:?--ledger requires a directory}" ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
[[ "$JOBS" =~ ^[0-9]+$ ]] && (( JOBS >= 1 )) || { printf -- '--jobs must be a positive integer\n' >&2; exit 2; }

# Parallel mode needs `wait -n` (bash 4.3+). Fall back rather than half-run.
if (( JOBS > 1 )) && ! { wait -n 2>/dev/null || [[ $? -ne 2 ]]; }; then
  printf 'bash %s lacks wait -n; falling back to --jobs 1\n' "${BASH_VERSION%%(*}" >&2
  JOBS=1
fi

# Results always land as one file per suite in TALLY_DIR — parallel jobs
# cannot share a bash counter, and a crash mid-run leaves a readable trail.
# Without --resume/--ledger the tally is ephemeral (removed on exit) and the
# output format stays byte-compatible with the historical serial runner.
USE_LEDGER=false
if [[ "$RESUME" == true || "$LEDGER_DIR" != "$SCRIPT_DIR/.run-ledger" ]]; then
  USE_LEDGER=true
  mkdir -p "$LEDGER_DIR"
  TALLY_DIR="$LEDGER_DIR"
else
  TALLY_DIR=$(mktemp -d -t run-all-tally-XXXXXX)
fi

# --- hermetic git environment ------------------------------------------------
HERMETIC_HOME=$(mktemp -d -t run-all-git-XXXXXX)
cleanup() {
  rm -rf "$HERMETIC_HOME"
  [[ "${USE_LEDGER:-false}" == false && -n "${TALLY_DIR:-}" ]] && rm -rf "$TALLY_DIR"
}
trap cleanup EXIT
cat > "$HERMETIC_HOME/gitconfig" <<'GITCFG'
[user]
	name = co-evolution-tests
	email = tests@invalid.local
[init]
	defaultBranch = master
[core]
	autocrlf = false
[commit]
	gpgsign = false
GITCFG
export GIT_CONFIG_GLOBAL="$HERMETIC_HOME/gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
# Block hooks a host may have configured globally.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null

# --- suite list ----------------------------------------------------------------
SLOW_SUITES="pr-emitter-simulation.sh code-proposer-simulation.sh"

# Seat integrations are explicit gates: keep them in the aggregate even if the
# general simulation glob or their filenames change later. The live GLM gate is
# safe here because it skips unless CO_EVOLVE_LIVE_GLM_TEST=1 is set.
declare -a SUITES=(
  "$SCRIPT_DIR/glm-launcher-simulation.sh"
  "$SCRIPT_DIR/kimi-seat-simulation.sh"
  "$SCRIPT_DIR/live-glm-seat-simulation.sh"
)
for t in "$SCRIPT_DIR"/*-simulation.sh; do
  [[ -f "$t" ]] || continue
  base=$(basename "$t")
  case "$base" in
    glm-launcher-simulation.sh|kimi-seat-simulation.sh|live-glm-seat-simulation.sh) continue ;;
  esac
  if [[ "$QUICK" == true ]] && printf '%s' "$SLOW_SUITES" | grep -qF "$base"; then
    continue
  fi
  SUITES+=("$t")
done
if [[ "$QUICK" == false ]]; then
  SUITES+=("$REPO_ROOT/evals/tests/scorer-verification.sh")
  SUITES+=("$REPO_ROOT/evals/tests/bounce-scorer-verification.sh")
  # Benchmark suite: all stubbed (no LLM calls, no spend). The judge-lib
  # extraction test guards judge-bounce.sh's behavior after the refactor.
  SUITES+=("$REPO_ROOT/evals/tests/test-judge-lib-extraction.sh")
  SUITES+=("$REPO_ROOT/benchmarks/tests/smoke.sh")
  SUITES+=("$REPO_ROOT/benchmarks/tests/test-panel.sh")
  SUITES+=("$REPO_ROOT/benchmarks/tests/test-judging.sh")
  SUITES+=("$REPO_ROOT/benchmarks/tests/test-report.sh")
fi

# --- run -----------------------------------------------------------------------
TOTAL=0
SKIPPED=0
START_ALL=$(date +%s)

# run_one_suite SUITE — runs it, prints one result line, records the ledger
# entry. In parallel mode a FAIL's detail stays in the per-suite ledger log
# (interleaving 20-line dumps from concurrent jobs would shred the output);
# serial mode keeps the historical inline dump.
run_one_suite() {
  local suite="$1"
  local name start out_file rc elapsed last_line
  name=$(basename "$suite")
  start=$(date +%s)
  out_file="$TALLY_DIR/$name.log"
  rc=0
  bash "$suite" < /dev/null > "$out_file" 2>&1 || rc=$?
  elapsed=$(( $(date +%s) - start ))
  last_line=$(tail -1 "$out_file" | head -c 100)
  if (( rc == 0 )); then
    printf 'PASS  %-50s %4ss  %s\n' "$name" "$elapsed" "$last_line"
    printf 'PASS %s\n' "$elapsed" > "$TALLY_DIR/$name.result"
  else
    printf 'FAIL  %-50s %4ss  (exit %d)\n' "$name" "$elapsed" "$rc"
    printf 'FAIL %s %s\n' "$rc" "$elapsed" > "$TALLY_DIR/$name.result"
    if (( JOBS == 1 )); then
      printf -- '------ %s: last 20 lines ------\n' "$name"
      tail -20 "$out_file"
      printf -- '------ end %s ------\n' "$name"
    else
      printf -- '------ %s failed: full output in %s ------\n' "$name" "$out_file"
    fi
  fi
  return "$rc"
}

printf 'co-evolution test suite — %d suites%s%s\n' "${#SUITES[@]}" \
  "$([[ $QUICK == true ]] && printf ' (--quick)')" \
  "$( (( JOBS > 1 )) && printf ' (jobs=%d)' "$JOBS")"
printf -- '----------------------------------------------------------------------\n'

# Resume: drop suites the ledger already marks PASS. The skip list is printed
# so a green summary can never silently hide what was not re-run.
declare -a TODO=()
# ${arr[@]+...} guard: bash 3.2 under set -u errors on empty-array expansion.
for suite in ${SUITES[@]+"${SUITES[@]}"}; do
  TOTAL=$((TOTAL + 1))
  name=$(basename "$suite")
  if [[ "$RESUME" == true && -f "$LEDGER_DIR/$name.result" ]] \
     && read -r prev _ < "$LEDGER_DIR/$name.result" && [[ "$prev" == "PASS" ]]; then
    SKIPPED=$((SKIPPED + 1))
    printf 'SKIP  %-50s       (ledger PASS)\n' "$name"
    continue
  fi
  TODO+=("$suite")
done

if (( JOBS == 1 )); then
  for suite in ${TODO[@]+"${TODO[@]}"}; do
    run_one_suite "$suite" || true
  done
else
  active=0
  for suite in ${TODO[@]+"${TODO[@]}"}; do
    if (( active >= JOBS )); then
      wait -n || true
      active=$((active - 1))
    fi
    run_one_suite "$suite" &
    active=$((active + 1))
  done
  while (( active > 0 )); do
    wait -n || true
    active=$((active - 1))
  done
fi

# The gate is cumulative: a suite counts as green iff its tally file says
# PASS — written this run, or (with --resume) by a previous run on this tree.
FAILED=0
for suite in ${SUITES[@]+"${SUITES[@]}"}; do
  name=$(basename "$suite")
  if ! { [[ -f "$TALLY_DIR/$name.result" ]] \
         && read -r st _ < "$TALLY_DIR/$name.result" && [[ "$st" == "PASS" ]]; }; then
    FAILED=$((FAILED + 1))
  fi
done

printf -- '----------------------------------------------------------------------\n'
if [[ "$USE_LEDGER" == true ]]; then
  printf '%d/%d suites green (%d run now, %d from ledger) in %ss\n' \
    "$((TOTAL - FAILED))" "$TOTAL" "$((TOTAL - SKIPPED))" "$SKIPPED" "$(( $(date +%s) - START_ALL ))"
else
  printf '%d/%d suites passed in %ss\n' "$((TOTAL - FAILED))" "$TOTAL" "$(( $(date +%s) - START_ALL ))"
fi

if (( FAILED > 0 )); then
  exit 1
fi
