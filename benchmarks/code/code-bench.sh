#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/code-bench-lib.sh
source "$SCRIPT_DIR/lib/code-bench-lib.sh"

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  check)
    code_check_manifests
    ;;
  estimate)
    exec bash "$SCRIPT_DIR/estimate-compute.sh" "$@"
    ;;
  fetch-metadata)
    suite_json=$(code_suite_json "$(code_suite_id)")
    subset=$(code_subset_path "$suite_json")
    output=$(code_metadata_path)
    exec python "$SCRIPT_DIR/scripts/fetch-swebench-metadata.py" \
      --subset "$subset" --lock "$SCRIPT_DIR/external-sources.lock.json" --output "$output"
    ;;
  draw-subset)
    exec python "$SCRIPT_DIR/scripts/draw-subset.py" \
      --lock "$SCRIPT_DIR/external-sources.lock.json" "$@"
    ;;
  annotate-difficulty)
    # Public dataset field only; no gold patch or hidden test is read.
    exec python "$SCRIPT_DIR/scripts/annotate-difficulty.py" \
      --lock "$SCRIPT_DIR/external-sources.lock.json" "$@"
    ;;
  setup)
    exec bash "$SCRIPT_DIR/scripts/setup-swebench.sh" "$@"
    ;;
  prepare-instance)
    exec bash "$SCRIPT_DIR/scripts/prepare-swebench-instance.sh" "$@"
    ;;
  run-workflow)
    exec bash "$SCRIPT_DIR/drivers/run-workflow.sh" "$@"
    ;;
  run-single-shot)
    exec bash "$SCRIPT_DIR/drivers/run-single-shot.sh" "$@"
    ;;
  run-canary)
    exec bash "$SCRIPT_DIR/scripts/run-canary.sh" "$@"
    ;;
  validate-predictions)
    exec bash "$SCRIPT_DIR/validate-predictions.sh" "$@"
    ;;
  probe-codex-sandbox)
    # One tiny Codex call per mode: not free, never run by the tests.
    exec bash "$SCRIPT_DIR/scripts/probe-codex-sandbox.sh" "$@"
    ;;
  gold-canary)
    exec bash "$SCRIPT_DIR/scripts/evaluate-swebench.sh" gold "$@"
    ;;
  evaluate)
    exec bash "$SCRIPT_DIR/scripts/evaluate-swebench.sh" predictions "$@"
    ;;
  -h|--help|help|"")
    cat <<'USAGE'
usage: code-bench.sh COMMAND [options]

  check                         validate checked-in manifests
  estimate [options]            report declared provider dispatches
  fetch-metadata                cache public inputs for the active suite
  draw-subset [options]         draw a reproducible random subset
  annotate-difficulty --subset F  write Verified difficulty labels into a subset
  setup --check|--install       inspect or install pinned SWE-bench tooling
  prepare-instance ID RUN COND  clone a clean public-input workspace
  run-workflow [options]        generate one capped condition prediction
  run-single-shot [options]     generate one single-shot tier prediction
  run-canary [options]          run a batch with one aggregate Claude cap
  validate-predictions FILE     validate JSONL before official scoring
  probe-codex-sandbox [--all]   check whether Codex can write under workspace-write here
  gold-canary [INSTANCE]        verify the official evaluator with a gold patch
  evaluate FILE                 score generated predictions officially

No command in this phase invokes a model. Live generation drivers are added
only after this offline harness and its compute cap are verified.
USAGE
    ;;
  *)
    code_die "unknown command: $COMMAND"; exit 2
    ;;
esac
