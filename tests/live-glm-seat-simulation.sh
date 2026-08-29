#!/usr/bin/env bash
# Opt-in end-to-end GLM seat smoke. This may spend Z.AI free-tier requests and
# therefore skips unless the operator explicitly sets CO_EVOLVE_LIVE_GLM_TEST=1.

set -uo pipefail

if [[ "${CO_EVOLVE_LIVE_GLM_TEST:-}" != "1" ]]; then
  echo "SKIP: live GLM seat test (set CO_EVOLVE_LIVE_GLM_TEST=1 to enable)"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOUNCER="$REPO_ROOT/co-evolve-bouncer.sh"
TEST_DIR="$(mktemp -d -t live-glm-seat-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_DIR/doc.md" <<'DOC'
# Live GLM smoke

Rewrite this short document as two concise sentences. Do not add protocol
markers or a human summary; this is only an explicitly enabled transport smoke.
DOC

rc=0
CO_EVOLVE_RUNS_DIR="$TEST_DIR/runs" \
  bash "$BOUNCER" --vanilla --no-report --bounce-only --bounces 1 \
    --agents glm,glm "$TEST_DIR/doc.md" > "$TEST_DIR/out.log" 2>&1 || rc=$?

state_file=$(ls -dt "$TEST_DIR"/runs/co-evolve-*/state.json 2>/dev/null | head -1)
if [[ "$rc" -eq 0 && -n "$state_file" ]] \
   && grep -Fq 'glm:glm-5.3-flash@' "$state_file"; then
  echo "PASS: live GLM seat completed and recorded glm-5.3-flash"
  exit 0
fi

echo "FAIL: live GLM seat smoke did not complete" >&2
cat "$TEST_DIR/out.log" >&2
exit 1
