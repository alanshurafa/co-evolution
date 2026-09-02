#!/usr/bin/env bash
# Build the results site's data file from evaluator output and run logs.
#
# The published page renders this JSON and nothing else, so anything that is
# not traceable to a file on disk cannot reach the page. Standardized
# benchmarks only: the retired document suite is not a source here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_ROOT="${CODE_BENCH_RESULTS_ROOT:-$REPO_ROOT/benchmarks/results/code}"
SUITE="swebench-verified-canary"
OUTPUT="$RESULTS_ROOT/site/leaderboard.json"

while (( $# > 0 )); do
  case "$1" in
    --suite) SUITE="${2:?--suite needs a value}"; shift 2 ;;
    --output) OUTPUT="${2:?--output needs a value}"; shift 2 ;;
    *) printf 'ERROR: unknown aggregate option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v python >/dev/null 2>&1 || { printf 'ERROR: python is required\n' >&2; exit 1; }
[[ -d "$RESULTS_ROOT/evaluation" ]] || { printf 'ERROR: no evaluation directory under %s\n' "$RESULTS_ROOT" >&2; exit 1; }

python "$SCRIPT_DIR/build-site-data.py" \
  --repo-root "$REPO_ROOT" \
  --results-root "$RESULTS_ROOT" \
  --suite "$SUITE" \
  --output "$OUTPUT" \
  --generated-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python "$SCRIPT_DIR/render-page.py" --data "$OUTPUT" --output "${OUTPUT%%.json}.html"
