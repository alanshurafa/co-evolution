#!/usr/bin/env bash
# STUB HARNESS -- DO NOT INVOKE IN PRODUCTION
#
# Hermetic test double for benchmarks/run-panel.sh, wired in through
# BENCH_PANEL_SCRIPT by benchmarks/tests/smoke.sh. Implements only the
# interface run-benchmark.sh depends on:
#   in:   --task-file <corpus file> --out-dir <dir>
#   out:  <out-dir>/final.md and <out-dir>/panel-state.json
#   exit: 0 final written | 1 compose/synthesis failure | 4 retryable quota/auth
#
# STUB_PANEL_RC forces a non-zero exit so the failure and pending-quota
# branches can be exercised without a live panel.

set -euo pipefail

echo 'STUB PANEL -- DO NOT INVOKE IN PRODUCTION' >&2

TASK_FILE=""
OUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-file) TASK_FILE="${2:-}"; shift 2 ;;
    --out-dir)   OUT_DIR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$TASK_FILE" && -f "$TASK_FILE" ]] || { echo 'stub panel: --task-file missing' >&2; exit 1; }
[[ -n "$OUT_DIR" ]] || { echo 'stub panel: --out-dir missing' >&2; exit 1; }

mkdir -p "$OUT_DIR"

RC="${STUB_PANEL_RC:-0}"

jq -n --arg rc "$RC" '{
  schema: "bench-panel/1.0",
  status: (if $rc == "0" then "complete" else "failed" end),
  kimi_status: "ok",
  degraded: false,
  phases: { compose: "ok", "critique-codex": "ok", "critique-glm": "ok", "critique-kimi": "ok", synthesis: "ok" },
  tokens: { phases: {}, totals: { claude_input: 900, claude_output: 350, claude_cache_read: 0, claude_cost_usd: 0.009, codex_total_tokens: 1024 } },
  stub: "benchmarks/tests/fixtures/orchestrator/bin/run-panel-stub.sh"
}' > "$OUT_DIR/panel-state.json"

if [[ "$RC" != "0" ]]; then
  exit "$RC"
fi

cat > "$OUT_DIR/final.md" <<'DOC_EOF'
# Delivery Scheduling Plan

## Measurement

Two weeks of hourly sell-through per product per location, taken from the till
exports, give a demand curve per shop that the production order is fitted to.

## Production order

Trailing two-week median for the weekday, rounded to the nearest tray, plus a
ten percent buffer on the two highest-variance products.

## Timetable

Two waves: one ninety minutes before the earliest opening, one at midday sized
from the morning's actual sell-through against confirmed van capacity.

## Shortfall handling

Proportional allocation against forecast demand, with the affected shops told
before the van leaves.

## Verification

Weekly stockout hours and units discarded at close. Success is falling stockout
hours with flat or falling discards, reviewed at four weeks.
DOC_EOF
