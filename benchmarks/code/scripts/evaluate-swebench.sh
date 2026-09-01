#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/code-bench-lib.sh
source "$CODE_DIR/lib/code-bench-lib.sh"

MODE="${1:-}"
shift || true
SUITE="swebench-verified-canary"
CACHE="$CODE_BENCH_RESULTS_ROOT/.cache"
if [[ -x "$CACHE/venv/Scripts/swebench.exe" ]]; then CLI="$CACHE/venv/Scripts/swebench.exe"; else CLI="$CACHE/venv/bin/swebench"; fi

[[ -x "$CLI" ]] || { code_die "SWE-bench is not installed; run code-bench.sh setup --install"; exit 1; }
# Python on Windows otherwise inherits CP1252 for pathlib.write_text(), which
# cannot encode some Unicode symbols present in official evaluation scripts.
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8
export HF_HUB_DISABLE_SYMLINKS_WARNING=1
# Unauthenticated Hub reads are rate-limited and the warning fires mid-run. A
# token is optional; it is read from the seat env file and never echoed.
code_load_env_key HF_TOKEN
if [[ -n "${HF_TOKEN:-}" ]]; then export HF_TOKEN; fi
if command -v timeout >/dev/null 2>&1; then
  timeout 10 docker info >/dev/null 2>&1 || { code_die "Docker engine is not running"; exit 1; }
else
  docker info >/dev/null 2>&1 || { code_die "Docker engine is not running"; exit 1; }
fi
EVAL_ROOT="$CODE_BENCH_RESULTS_ROOT/evaluation"
mkdir -p "$EVAL_ROOT"

case "$MODE" in
  gold)
    suite_json=$(code_suite_json "$SUITE")
    subset=$(code_subset_path "$suite_json")
    instance="${1:-$(jq -r '.instances[0].instance_id' "$subset" | tr -d '\r')}"
    jq -e --arg id "$instance" '.instances[] | select(.instance_id == $id)' "$subset" >/dev/null \
      || { code_die "gold instance is outside frozen subset: $instance"; exit 1; }
    run_id="gold-canary-$(date -u +%Y%m%dT%H%M%SZ)"
    (cd "$EVAL_ROOT" && "$CLI" eval verified --gold -i "$instance" --run-id "$run_id" -j 1)
    ;;
  predictions)
    predictions="${1:-}"
    [[ -n "$predictions" ]] || { code_die "predictions mode needs a JSONL file"; exit 2; }
    bash "$CODE_DIR/validate-predictions.sh" "$predictions" "$SUITE"
    predictions_dir=$(cd "$(dirname "$predictions")" && pwd -P)
    predictions="$predictions_dir/$(basename "$predictions")"
    run_id="code-bench-$(date -u +%Y%m%dT%H%M%SZ)"
    (cd "$EVAL_ROOT" && "$CLI" eval verified -p "$predictions" --run-id "$run_id" -j "${CODE_BENCH_EVAL_JOBS:-1}")
    ;;
  *)
    code_die "usage: evaluate-swebench.sh gold [INSTANCE]|predictions FILE"; exit 2
    ;;
esac
