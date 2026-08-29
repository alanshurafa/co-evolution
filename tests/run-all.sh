#!/usr/bin/env bash
# tests/run-all.sh — aggregate test runner (v1.3 Phase 2; closes audit F-3).
#
# Runs every hermetic gate in the repo and reports one PASS/FAIL line per
# suite plus a final summary. Exits nonzero if any suite fails.
#
#   bash tests/run-all.sh            # everything
#   bash tests/run-all.sh --quick    # skip the slow suites (pr-emitter,
#                                    # code-proposer, scorer-verification)
#
# Hermetic against host git config: tests that create scratch repos must not
# depend on (or be broken by) the host's user identity, autocrlf, hooks, or
# default-branch settings, so a throwaway global config is injected for the
# whole run.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

# --- hermetic git environment ------------------------------------------------
HERMETIC_HOME=$(mktemp -d -t run-all-git-XXXXXX)
cleanup() { rm -rf "$HERMETIC_HOME"; }
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
fi

# --- run -----------------------------------------------------------------------
TOTAL=0
FAILED=0
START_ALL=$(date +%s)

printf 'co-evolution test suite — %d suites%s\n' "${#SUITES[@]}" "$([[ $QUICK == true ]] && printf ' (--quick)')"
printf -- '----------------------------------------------------------------------\n'

# ${arr[@]+...} guard: bash 3.2 under set -u errors on empty-array expansion.
for suite in ${SUITES[@]+"${SUITES[@]}"}; do
  TOTAL=$((TOTAL + 1))
  name=$(basename "$suite")
  start=$(date +%s)
  out_file=$(mktemp)
  rc=0
  bash "$suite" < /dev/null > "$out_file" 2>&1 || rc=$?
  elapsed=$(( $(date +%s) - start ))
  last_line=$(tail -1 "$out_file" | head -c 100)
  if (( rc == 0 )); then
    printf 'PASS  %-50s %4ss  %s\n' "$name" "$elapsed" "$last_line"
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL  %-50s %4ss  (exit %d)\n' "$name" "$elapsed" "$rc"
    printf -- '------ %s: last 20 lines ------\n' "$name"
    tail -20 "$out_file"
    printf -- '------ end %s ------\n' "$name"
  fi
  rm -f "$out_file"
done

printf -- '----------------------------------------------------------------------\n'
printf '%d/%d suites passed in %ss\n' "$((TOTAL - FAILED))" "$TOTAL" "$(( $(date +%s) - START_ALL ))"

if (( FAILED > 0 )); then
  exit 1
fi
