#!/usr/bin/env bash
# Build the results site's data file from evaluator output and run logs, then
# render the leaderboard and methodology pages from it.
#
# The published pages render this JSON and nothing else, so anything that is
# not traceable to a file on disk cannot reach the page. Standardized
# benchmarks only: the retired document suite is not a source here.
#
#   bash benchmarks/site/aggregate.sh --suite swebench-verified-random50
#   bash benchmarks/site/aggregate.sh --suite swebench-verified-random50 --run-label base50-light
#
# Without --run-label every run registered for the suite in
# benchmarks/code/runs.json is read. The results tree may live in a sibling
# checkout; point CODE_BENCH_RESULTS_ROOT at it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_ROOT="${CODE_BENCH_RESULTS_ROOT:-$REPO_ROOT/benchmarks/results/code}"
SUITE="swebench-verified-canary"
RUN_LABELS=()
OUTPUT="$RESULTS_ROOT/site/leaderboard.json"
ALSO=()
OBSERVATORY=false

while (( $# > 0 )); do
  case "$1" in
    --suite) SUITE="${2:?--suite needs a value}"; shift 2 ;;
    --run-label) RUN_LABELS+=("${2:?--run-label needs a value}"); shift 2 ;;
    --output) OUTPUT="${2:?--output needs a value}"; shift 2 ;;
    --also) ALSO+=("${2:?--also needs LABEL=HREF}"); shift 2 ;;
    --observatory) OBSERVATORY=true; shift ;;
    *) printf 'ERROR: unknown aggregate option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v python >/dev/null 2>&1 || { printf 'ERROR: python is required\n' >&2; exit 1; }

# An observatory refresh must target the registered current export, never an
# archived edition. Verify before the builder can overwrite any output.
if [[ "$OBSERVATORY" == true ]]; then
  python - "$SCRIPT_DIR" "$SUITE" "$OUTPUT" <<'PY'
import json
from pathlib import Path
import sys
site, suite, output = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
catalog = json.loads((site / 'observatory-catalog.json').read_text(encoding='utf-8'))
archive = json.loads((site / 'archive-manifest.json').read_text(encoding='utf-8'))
entry = next((s for s in catalog['suites'] if s['id'] == suite), None)
if output.name in archive['files'] or not entry or output.name != entry['data']:
    raise SystemExit('ERROR: --observatory requires the registered current data filename for the selected suite; archived exports are protected')
PY
fi

[[ -d "$RESULTS_ROOT/evaluation" ]] || { printf 'ERROR: no evaluation directory under %s\n' "$RESULTS_ROOT" >&2; exit 1; }

label_args=()
for label in ${RUN_LABELS[@]+"${RUN_LABELS[@]}"}; do label_args+=(--run-label "$label"); done
also_args=()
for link in ${ALSO[@]+"${ALSO[@]}"}; do also_args+=(--also "$link"); done

python "$SCRIPT_DIR/build-site-data.py" \
  --repo-root "$REPO_ROOT" \
  --results-root "$RESULTS_ROOT" \
  --suite "$SUITE" \
  --output "$OUTPUT" \
  ${label_args[@]+"${label_args[@]}"} \
  --generated-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python "$SCRIPT_DIR/render-page.py" --data "$OUTPUT" \
  --output "${OUTPUT%%.json}.html" \
  --methodology "${OUTPUT%%.json}-methodology.html" \
  ${also_args[@]+"${also_args[@]}"}

if [[ "$OBSERVATORY" == true ]]; then
  python "$SCRIPT_DIR/build-observatory.py" --data-dir "$(dirname "$OUTPUT")" \
    --output "$(dirname "$OUTPUT")/index.html"
fi
