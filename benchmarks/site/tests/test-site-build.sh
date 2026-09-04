#!/usr/bin/env bash
# Hermetic gate for the results-site aggregator and renderer.
#
# A synthetic results tree is laid out by make-fixture.py, the real
# build-site-data.py aggregates it, and the assertions read the JSON it wrote.
# No model call, no Docker, no network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SITE_DIR/../.." && pwd)"
TMP=$(mktemp -d -t site-build-test-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

TOTAL=0
FAILED=0
pass() { TOTAL=$((TOTAL + 1)); printf 'PASS: %s\n' "$1"; }
fail() { TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1"; }
check() { # check LABEL FILE JQ-EXPRESSION
  if jq -e "$3" "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi
}

build() { # build NAME SPEC-JSON [extra builder args...]
  local name="$1" spec="$2"; shift 2
  local root="$TMP/$name"
  printf '%s' "$spec" | python "$SCRIPT_DIR/make-fixture.py" --root "$root" >/dev/null || return 1
  python "$SITE_DIR/build-site-data.py" --repo-root "$REPO_ROOT" --results-root "$root" \
    --suite swebench-verified-canary --run-label fx --output "$root/site/leaderboard.json" \
    --generated-at 2026-09-04T00:00:00Z "$@" >/dev/null 2>"$root/build.stderr" \
    || { cat "$root/build.stderr" >&2; return 1; }
  printf '%s' "$root/site/leaderboard.json"
}

# --- T0.1: every seat is priced from its own log at the tracked list rate ----
# A: Claude only, cost is the CLI figure, complete and exact.
# B: two Codex phases with a --json split (exact) and three total-only
#    (estimated); complete, but flagged estimated with bounds.
# C: GLM review with a sidecar and Kimi review without one; incomplete.
SPEC_COST='{
  "run_label": "fx",
  "conditions": {
    "A": {"cells": {
      "sympy__sympy-20916": {"resolved": true,  "claude_cost": 1.0},
      "django__django-16819": {"resolved": true, "claude_cost": 1.0},
      "scikit-learn__scikit-learn-14141": {"resolved": false, "claude_cost": 1.0},
      "astropy__astropy-7166": {"resolved": true, "claude_cost": 1.0},
      "pallets__flask-5014": {"resolved": true, "claude_cost": 1.0}}},
    "B": {"cells": {
      "sympy__sympy-20916": {"resolved": true,  "claude_cost": 1.0, "codex": "exact"},
      "django__django-16819": {"resolved": true, "claude_cost": 1.0, "codex": "exact"},
      "scikit-learn__scikit-learn-14141": {"resolved": true, "claude_cost": 1.0, "codex": "total"},
      "astropy__astropy-7166": {"resolved": false, "claude_cost": 1.0, "codex": "total"},
      "pallets__flask-5014": {"resolved": true, "claude_cost": 1.0, "codex": "total"}}},
    "C": {"critics": ["glm", "kimi"], "cells": {
      "sympy__sympy-20916": {"resolved": true, "claude_cost": 2.0, "glm": "sidecar", "kimi": "bare"}}}
  }}'
out=$(build cost "$SPEC_COST") || fail "fixture builds"
[[ -f "$out" ]] && pass "fixture builds"

check "Claude-only arm is priced complete and exact" "$out" \
  '.rows[] | select(.condition == "A") | .telemetry
   | .cost_usd == 5.0 and .cost_is_complete == true and .cost_precision == "exact"
     and .codex_cost_usd == 0'
# Exact phase: 80k input of which 60k cached, 20k output at terra rates
# (2.00 / 0.20 / 12.00 per million) = 0.04 + 0.012 + 0.24 = 0.292 each.
# Total-only phase: 100k tokens at the recorded 0.70/0.20/0.10 split =
# 100k * (0.7*0.20 + 0.2*2.00 + 0.1*12.00) / 1e6 = 0.174 each.
check "Codex seat is priced from its own logs" "$out" \
  '.rows[] | select(.condition == "B") | .telemetry
   | (.codex_cost_usd == 1.106) and .codex_phases == 5
     and .codex_input_tokens == 160000 and .codex_cached_tokens == 120000
     and .codex_output_tokens == 40000'
check "a bounce arm now costs more than the solo arm it extends" "$out" \
  '([.rows[] | select(.condition == "B") | .telemetry.cost_usd] | .[0])
   > ([.rows[] | select(.condition == "A") | .telemetry.cost_usd] | .[0])'
check "total-only Codex logs mark the cost estimated with bounds" "$out" \
  '.rows[] | select(.condition == "B") | .telemetry
   | .cost_is_complete == true and .cost_precision == "estimated"
     and .cost_low_usd < .cost_usd and .cost_usd < .cost_high_usd'
check "Codex CLI version is read from the phase log" "$out" \
  '.rows[] | select(.condition == "B") | .telemetry.codex_cli_versions == ["0.144.5"]'
check "an unpriced critic seat keeps the arm cost incomplete" "$out" \
  '.rows[] | select(.condition == "C") | .telemetry
   | .cost_is_complete == false and .cost_precision == "unpriced"
     and .glm_calls == 1 and .kimi_calls == 1 and .glm_cost_usd > 0
     and .cost_per_resolved == null'
check "the page records which pricing file and date it used" "$out" \
  '.pricing.file == "benchmarks/code/pricing.json" and (.pricing.recorded_on | test("^2026-"))'
check "evidence paths stay under benchmarks/results/code" "$out" \
  '[.rows[] | select(.measured) | .per_task[] | .evidence | select(. != null)] | length > 0 and all(startswith("benchmarks/results/code/"))'

printf '%d/%d assertions passed' "$((TOTAL - FAILED))" "$TOTAL"
if (( FAILED > 0 )); then printf ' (%d failed)\n' "$FAILED"; exit 1; fi
printf '\n'
