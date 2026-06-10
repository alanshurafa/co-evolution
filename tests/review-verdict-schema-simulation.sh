#!/usr/bin/env bash
# tests/review-verdict-schema-simulation.sh
# Hermetic gate for review-verdict.json canonicalization (audit finding F-2).
#
# The three review-verdict.json copies (schemas/, runners/codex-ps/schemas/,
# skills/dev-review/schemas/) had drifted into two shapes (a strict variant in the
# first two, the original loose variant in the skill copy). They are canonicalized
# to the single LOOSE shape that validate_review_verdict actually enforces and that
# both runners consume. This gate:
#   1. fails if the three copies ever drift apart again (structural diff via jq -S);
#   2. pins validate_review_verdict's loose contract with positive + negative
#      fixtures (none existed for the Bash validator before F-2).
#
# Requires jq (a declared project dependency).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/lib/co-evolution.sh"

S1="$REPO_ROOT/schemas/review-verdict.json"
S2="$REPO_ROOT/runners/codex-ps/schemas/review-verdict.json"
S3="$REPO_ROOT/skills/dev-review/schemas/review-verdict.json"

TEST_DIR="$(mktemp -d -t review-verdict-XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

TOTAL=0
FAILURES=0
pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1" >&2; FAILURES=$((FAILURES + 1)); }

# --- Scenario 1: drift guard -- all three copies structurally identical ---
TOTAL=$((TOTAL + 1))
if diff <(jq -S . "$S1") <(jq -S . "$S3") >/dev/null 2>&1 \
   && diff <(jq -S . "$S2") <(jq -S . "$S3") >/dev/null 2>&1; then
  pass "all three review-verdict.json copies are structurally identical"
else
  fail "review-verdict.json copies have drifted (schemas/ or runners/codex-ps/ != skills/dev-review/)"
fi

# Source the library to exercise the real validator.
# shellcheck disable=SC1090
source "$LIB" >/dev/null 2>&1

write_fixture() { local p="$TEST_DIR/$1.json"; printf '%s' "$2" > "$p"; printf '%s' "$p"; }

check_valid() {   # $1 desc, $2 json
  TOTAL=$((TOTAL + 1))
  local f; f="$(write_fixture "fx$TOTAL" "$2")"
  if validate_review_verdict "$f" >/dev/null 2>&1; then pass "$1"; else fail "$1 (expected accept, got reject)"; fi
}
check_invalid() { # $1 desc, $2 json
  TOTAL=$((TOTAL + 1))
  local f; f="$(write_fixture "fx$TOTAL" "$2")"
  if validate_review_verdict "$f" >/dev/null 2>&1; then fail "$1 (expected reject, got accept)"; else pass "$1"; fi
}

# --- Scenarios 2-3: validator accepts LOOSE verdicts (no strict-only fields) ---
check_valid "validator accepts a minimal APPROVED verdict (no file/line_range/suggestion)" \
  '{"verdict":"APPROVED","confidence":90,"summary":"looks good","issues":[]}'
check_valid "validator accepts REVISE with a loose issue (severity+description only)" \
  '{"verdict":"REVISE","confidence":60,"summary":"needs work","issues":[{"severity":"HIGH","description":"a real bug"}]}'

# --- Scenarios 4-5: validator rejects malformed verdicts ---
check_invalid "validator rejects a verdict missing the issues field" \
  '{"verdict":"APPROVED","confidence":90,"summary":"looks good"}'
check_invalid "validator rejects an unsupported verdict enum value" \
  '{"verdict":"MAYBE","confidence":90,"summary":"looks good","issues":[]}'

passed=$((TOTAL - FAILURES))
if (( FAILURES == 0 )); then
  echo "$passed/$TOTAL scenarios passed"
  exit 0
else
  echo "$passed/$TOTAL scenarios passed ($FAILURES failed)" >&2
  exit 1
fi
