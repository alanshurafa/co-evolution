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


# --- T0.4: uncertainty on every cell, paired contrasts, Rank(UB) -------------
if python "$SCRIPT_DIR/test_stats.py" >/dev/null 2>&1; then
  pass "statistics module reproduces the known values (Wilson 42/50 = 71-92, McNemar 2/5 p = 0.45)"
else
  fail "statistics module reproduces the known values"
fi

# A: 4/5, B: 4/5 with one rescued and one broken task -> p = 1.0, rank tie.
SPEC_STATS='{
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
      "scikit-learn__scikit-learn-14141": {"resolved": true, "claude_cost": 1.0, "codex": "exact"},
      "astropy__astropy-7166": {"resolved": false, "claude_cost": 1.0, "codex": "exact"},
      "pallets__flask-5014": {"resolved": true, "claude_cost": 1.0, "codex": "exact"}}}
  }}'
out=$(build stats "$SPEC_STATS") || fail "stats fixture builds"
check "every measured row carries a Wilson interval and a bootstrap interval" "$out" \
  '[.rows[] | select(.measured)] | length == 2 and all(.[];
     .score.n == 5 and .score.resolved == 4 and .score.wilson_low < 0.8 and .score.wilson_high > 0.8
     and .bootstrap.levels == ["repo","task","seed"] and .bootstrap.low <= .bootstrap.point
     and .bootstrap.point <= .bootstrap.high)'
check "overlapping intervals share Rank(UB) 1" "$out" \
  '[.rows[] | select(.measured) | .rank_ub] == [1, 1] and .schema == "code-bench-site/2.0"'
check "the paired contrast lists the rescued and broken tasks with an exact p" "$out" \
  '.contrasts | length == 1 and .[0].a_condition == "A" and .[0].b_condition == "B"
   and .[0].only_a == 1 and .[0].only_b == 1 and .[0].both == 3 and .[0].neither == 0
   and .[0].rescued_by_b == ["scikit-learn__scikit-learn-14141"]
   and .[0].broken_by_b == ["astropy__astropy-7166"]
   and .[0].mcnemar_exact_p == 1 and .[0].delta_b_minus_a.point == 0'
check "the contrast prices the cost delta per net flip only from complete costs" "$out" \
  '.contrasts[0].cost_is_complete == true and .contrasts[0].cost_delta_usd > 0
   and .contrasts[0].cost_per_net_flip_usd == null'
check "the page states which statistics it used" "$out" \
  '.statistics.bootstrap.draws == 2000 and (.statistics.module | endswith("stats.py"))'


# --- T0.6: inert repairs are counted per arm and flagged per task ------------
SPEC_INERT='{
  "run_label": "fx",
  "conditions": {
    "B": {"cells": {
      "sympy__sympy-20916": {"resolved": true,  "claude_cost": 1.0, "codex": "exact", "repair": "inert"},
      "django__django-16819": {"resolved": true, "claude_cost": 1.0, "codex": "exact", "repair": "active"},
      "scikit-learn__scikit-learn-14141": {"resolved": false, "claude_cost": 1.0, "codex": "exact", "repair": "inert"},
      "astropy__astropy-7166": {"resolved": true, "claude_cost": 1.0, "codex": "exact", "repair": "active"},
      "pallets__flask-5014": {"resolved": true, "claude_cost": 1.0, "codex": "exact", "repair": "active"}}}
  }}'
out=$(build inert "$SPEC_INERT") || fail "inert fixture builds"
check "inert repairs are counted per arm and flagged per task" "$out" \
  '.rows[] | select(.condition == "B")
   | .telemetry.repair_cells == 5 and .telemetry.repair_inert_count == 2
     and ([.per_task[] | select(.repair_inert == true) | .instance_id]
          == ["sympy__sympy-20916", "scikit-learn__scikit-learn-14141"])'


# --- Site redesign: every section renders from the JSON alone ----------------
PAGE="$TMP/stats/site/leaderboard.html"
METH="$TMP/stats/site/leaderboard-methodology.html"
if python "$SITE_DIR/render-page.py" --data "$TMP/stats/site/leaderboard.json" --output "$PAGE" --methodology "$METH" >/dev/null 2>&1 \
   && [[ -s "$PAGE" && -s "$METH" ]]; then
  pass "renderer writes the leaderboard and methodology pages"
else
  fail "renderer writes the leaderboard and methodology pages"
fi
if grep -q '<title>Co-Evolution: cross-vendor review benchmark for coding agents</title>' "$PAGE"; then
  pass "the page carries the new title"
else
  fail "the page carries the new title"
fi
if grep -q 'Rank(UB)' "$PAGE" && grep -q 'class="ci"' "$PAGE" && grep -q '± ' "$PAGE"; then
  pass "every row shows an interval and a Rank(UB) column"
else
  fail "every row shows an interval and a Rank(UB) column"
fi
if [[ "$(grep -o '<svg class="scatter"' "$PAGE" | wc -l | tr -d ' ')" == 3 ]] \
   && grep -q 'data-axis="wall"' "$PAGE" && grep -q 'class="pt' "$PAGE"; then
  pass "the Pareto scatter is inline SVG with a three-way axis toggle"
else
  fail "the Pareto scatter is inline SVG with a three-way axis toggle"
fi
if grep -q 'id="contrast-data"' "$PAGE" && grep -q 'id="contrast-a"' "$PAGE"; then
  pass "the paired-contrast panel embeds the precomputed contrasts"
else
  fail "the paired-contrast panel embeds the precomputed contrasts"
fi
if grep -q 'id="matrix"' "$PAGE" && grep -q 'data-sort="rescued"' "$PAGE" && grep -q 'tr class="group"' "$PAGE"; then
  pass "the task heatmap is grouped by difficulty and sortable by rescued"
else
  fail "the task heatmap is grouped by difficulty and sortable by rescued"
fi
if grep -q 'class="repro"' "$PAGE" && grep -q 'run-canary --run-id fx' "$PAGE" && grep -q 'data-filter="tier"' "$PAGE"; then
  pass "rows expand to a reproduce command and the page has tier/run/seed selectors"
else
  fail "rows expand to a reproduce command and the page has tier/run/seed selectors"
fi
if grep -q 'official evaluator</span>' "$PAGE" && grep -q 'harness' "$PAGE" \
   && grep -q 'prefers-color-scheme: dark' "$PAGE" && ! grep -qiE 'chart\.js|d3\.min|plotly|recharts' "$PAGE"; then
  pass "provenance badges render, dark mode is styled, no chart library is loaded"
else
  fail "provenance badges render, dark mode is styled, no chart library is loaded"
fi
if grep -q 'Pre-registered contrasts' "$METH" && grep -q 'Paired observations' "$METH" && grep -q 'Cost basis' "$METH"; then
  pass "the methodology page carries pre-registration, power and cost basis from the same JSON"
else
  fail "the methodology page carries pre-registration, power and cost basis from the same JSON"
fi
# The cost-completeness flag is visible, not a footnote.
cost_page="$TMP/cost/site/leaderboard.html"
python "$SITE_DIR/render-page.py" --data "$TMP/cost/site/leaderboard.json" --output "$cost_page" >/dev/null 2>&1
if grep -q 'class="flag"' "$cost_page" && grep -q 'incomplete' "$cost_page" && grep -q 'class="est"' "$cost_page"; then
  pass "an unpriced seat renders as an incomplete-cost flag and estimates are marked"
else
  fail "an unpriced seat renders as an incomplete-cost flag and estimates are marked"
fi
if grep -rq 'benchmarks/results/b1\|bounce-protocol\|judge' "$PAGE" "$METH"; then
  fail "nothing from the retired document suite reaches the page"
else
  pass "nothing from the retired document suite reaches the page"
fi

printf '%d/%d assertions passed' "$((TOTAL - FAILED))" "$TOTAL"
if (( FAILED > 0 )); then printf ' (%d failed)\n' "$FAILED"; exit 1; fi
printf '\n'
